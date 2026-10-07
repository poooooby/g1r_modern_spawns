-- Red / Blue / Yellow: how the game's wild data and encounter hooks are
-- shaped, behind the interface every adapter offers (see gen2.lua for the
-- other one). The generator only ever sees `tables(mapId)` entries:
--   { kind, terrain, def = { rate, slots, buckets? }, weights }
-- and hands back the same shape with new species; everything that knows
-- what Encounter.roll, the Super Rod or encounter.table expect lives here.
--
--   encounters[mapId] = { grass = { rate, slots[10] }, water = {...} }
--   field.superRod[mapId] = { { species, level }, ... }   (2-4 entries)
--   odds: the 256-step ladder constants.encounterBuckets (or a table's own)
--
-- `reg.get(registry, id)` / `reg.ids(registry)` read mod.content.
-- `mod` (third arg) is the live game, for liveSlots only -- everything else
-- here still reads through `reg`.

return function(reg, MapContext, mod)
  local A = { generation = 1 }

  local DEFAULT_LADDER = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

  function A.defaultLadder()
    local ladder = reg.get("constants", "encounterBuckets")
    if type(ladder) == "table" and #ladder > 0 then return ladder end
    return DEFAULT_LADDER
  end

  local function encounter(mapId)
    local value = reg.get("encounters", mapId)
    return type(value) == "table" and value or nil
  end

  local function superRod(mapId)
    local groups = reg.get("field", "superRod")
    local group = type(groups) == "table" and groups[mapId] or nil
    return type(group) == "table" and #group > 0 and group or nil
  end

  function A.mapInfo(mapId)
    local value = reg.get("maps", mapId)
    return type(value) == "table" and value or nil
  end

  -- The game's own map order first, so history is deterministic; any map
  -- with wild data the order does not name follows, sorted.
  function A.mapOrder()
    local order, seen = {}, {}
    local mapOrder = reg.get("constants", "mapOrder")
    for _, id in ipairs(type(mapOrder) == "table" and mapOrder or {}) do
      if type(id) == "string" and not seen[id] then
        seen[id] = true
        order[#order + 1] = id
      end
    end
    local extra = {}
    for _, id in ipairs(reg.ids("encounters")) do
      if type(id) == "string" and not seen[id] then
        seen[id] = true
        extra[#extra + 1] = id
      end
    end
    local rods = reg.get("field", "superRod")
    for id in pairs(type(rods) == "table" and rods or {}) do
      if type(id) == "string" and not seen[id] then
        seen[id] = true
        extra[#extra + 1] = id
      end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do order[#order + 1] = id end
    return order
  end

  -- Per-slot odds from the ladder Encounter.roll will use for this table.
  -- Slots past the end of the ladder can never roll and weigh nothing.
  local function ladderWeights(def)
    local ladder = def.buckets or A.defaultLadder()
    local weights, prev = {}, 0
    for i = 1, #def.slots do
      local threshold = ladder[i]
      if threshold then
        weights[i] = math.max(0, threshold - prev)
        prev = threshold
      else
        weights[i] = 0
      end
    end
    return weights
  end

  -- Entry order and kind names are part of the SEEDED determinism key:
  -- grass, water, superRod, exactly as 0.1.0 generated them.
  function A.tables(mapId)
    local entries = {}
    local enc = encounter(mapId)
    local info = A.mapInfo(mapId)
    if enc then
      for _, spec in ipairs({ { "grass", MapContext.landTerrain(info) },
                              { "water", "water" } }) do
        local def = enc[spec[1]]
        if type(def) == "table" and type(def.slots) == "table" then
          entries[#entries + 1] = { kind = spec[1], terrain = spec[2], def = def,
                                    weights = ladderWeights(def) }
        end
      end
    end
    local rod = superRod(mapId)
    if rod then
      local weights = {}
      for i = 1, #rod do weights[i] = 1 end -- the rod's pick is uniform
      entries[#entries + 1] = { kind = "superRod", terrain = "fish",
                                def = { rate = 1, slots = rod }, weights = weights }
    end
    return entries
  end

  -- Generator output -> what the engine and the API expect.
  function A.assemble(_, kind, result)
    if kind == "superRod" then return result.slots end
    return result
  end

  -- ---------------------------------------------------------------- hooks

  -- encounter.roll / encounter.species: which generated table a roll uses.
  -- "indoor" (cave floors) rolls the grass table.
  function A.rollKind(ctx)
    if type(ctx) ~= "table" then return nil end
    return ctx.terrain == "water" and "water" or "grass"
  end

  -- The value to hand `next` in encounter.roll. Encounter.roll only reads
  -- `.grass`, and water rolls arrive as the same { grass = water } wrapper
  -- (OverworldController onStepComplete).
  function A.rollValue(_, _, _, table_)
    return { grass = table_ }
  end

  -- encounter.fishing: only the Super Rod has per-map groups. A map with no
  -- group (candidates nil) keeps "Not even a nibble!".
  function A.fishingKind(rod, _, candidates)
    if rod == "SUPER_ROD" and candidates ~= nil then return "superRod" end
    return nil
  end

  function A.fishingValue(_, _, group)
    return group
  end

  -- encounter.table preview: weight per species on the table's own ladder.
  function A.distribution(table_)
    local dist, prev = {}, 0
    local ladder = table_.buckets or A.defaultLadder()
    for i, threshold in ipairs(ladder) do
      local slot = table_.slots[i]
      if slot and slot.species then
        dist[slot.species] = (dist[slot.species] or 0) + (threshold - prev)
      end
      prev = threshold
    end
    return dist
  end

  -- Which slot of the generated table (by index) the engine just rolled,
  -- matched on the game's own table by species and level.
  function A.slotIndex(mapId, kind, _, rolled)
    local enc = encounter(mapId)
    local def = enc and enc[kind]
    for i, slot in ipairs(def and def.slots or {}) do
      if slot.species == rolled.species and slot.level == rolled.level then return i end
    end
    return nil
  end

  -- ------------------------------------------------------------ live sync

  -- The live slots array for a map/kind (src/live_sync.lua), as a
  -- single-element list -- see live_sync.lua's header for why a list.
  -- kind: "grass" | "water" | "superRod". mod.game is re-read every call,
  -- the same reason world.owned() is (the save is replaced on NEW GAME).
  function A.liveSlots(mapId, kind)
    local data = mod and mod.game and mod.game.data
    if not data then return nil end
    local slots
    if kind == "superRod" then
      local group = data.field and data.field.superRod and data.field.superRod[mapId]
      slots = (type(group) == "table" and #group > 0) and group or nil
    else
      local def = data.encounters and data.encounters[mapId]
      local area = def and def[kind]
      slots = (type(area) == "table" and type(area.slots) == "table") and area.slots or nil
    end
    return slots and { slots } or nil
  end

  -- ----------------------------------------------------------------- save

  function A.owned(game, id)
    local dex = game and game.save and game.save.pokedex
    return dex ~= nil and dex.owned ~= nil and dex.owned[id] == true
  end

  return A
end
