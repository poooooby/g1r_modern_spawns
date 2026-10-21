-- FireRed / LeafGreen: the same interface as gen1.lua / gen2.lua over the
-- game3 engine.
--
--   encounters[mapId] = { mapGroup, mapNum, land = { rate, slots[12] },
--                         water = { rate, slots[5] }, fishing, rocks }
--   slot = { species, minLevel, maxLevel }   (registry reads give names)
--   odds: land 20/20/10/10/10/10/5/5/4/4/1/1, water 60/30/5/4/1 (percent)
--
-- The encounters registry lists every map under several aliases (FR_ROUTE_1,
-- ROUTE1, "3:19", ...); the one the game runs under is the alias that also
-- has a map record, and only that one is generated.
--
-- The difference that shapes this adapter: FireRed's own roll ignores the
-- table a mod hands encounter.roll's `next` (src/core/game3/encounters.lua
-- re-reads the map's record). So nothing is swapped before the roll
-- (rollValue answers nil); instead `substituteAfterRoll` asks the runtime to
-- map the slot the engine rolled to the generated species in
-- encounter.species. Roles group slots by vanilla species, so that mapping
-- is exact. The engine takes the species back as its numeric slot
-- (withSpecies): a mod species has no name the engine can look up.
--
-- Fishing: one 10-slot table per map, Old Rod 1-2, Good Rod 3-5, Super Rod
-- 6-10 (src/core/game3/encounters.lua FISHING_RANGES). The Good and Super
-- Rods are generated as tables of their own ("fish.good", "fish.super"); the
-- engine hands encounter.fishing that rod's candidate list (species, levels,
-- odds) and rolls whatever list comes back, so only the species change. The
-- Old Rod stays the game's own, as on Gen 1 and 2.
--
-- Left as the game has them: the Old Rod, Rock Smash (no hook), static and
-- scripted encounters.

return function(reg, MapContext, mod)
  local A = { generation = 3, substituteAfterRoll = true }

  local LAND_WEIGHTS = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
  local WATER_WEIGHTS = { 60, 30, 5, 4, 1 }
  local KINDS = { { "land", LAND_WEIGHTS }, { "water", WATER_WEIGHTS } }
  -- the rods this mod generates: slot range of the map's fishing table and
  -- each slot's odds (percent)
  local RODS = {
    { kind = "fish.good", rod = "GOOD_ROD", first = 3, last = 5, weights = { 60, 20, 20 } },
    { kind = "fish.super", rod = "SUPER_ROD", first = 6, last = 10, weights = { 40, 40, 15, 4, 1 } },
  }
  local ROD_KIND = {}
  for _, r in ipairs(RODS) do ROD_KIND[r.rod] = r.kind end

  local function record(id)
    local value = reg.get("encounters", id)
    return type(value) == "table" and value or nil
  end

  local function slotsOf(rec, kind)
    local area = rec and rec[kind]
    return type(area) == "table" and type(area.slots) == "table"
      and #area.slots > 0 and (area.rate or 0) > 0 and area or nil
  end

  -- runtime map id -> encounter record, one per mapGroup:mapNum
  local canonical
  local function maps()
    if canonical then return canonical end
    canonical = {}
    local chosen = {}
    local ids = reg.ids("encounters")
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
      local rec = type(id) == "string" and record(id)
      if rec and rec.mapGroup and rec.mapNum then
        local key = rec.mapGroup .. ":" .. rec.mapNum
        local hasMap = reg.get("maps", id) ~= nil
        local current = chosen[key]
        -- prefer the alias with a map record; else the first FR_/LG_ one
        if not current or (hasMap and not current.hasMap) then
          if hasMap or id:match("^%u%u_") then
            chosen[key] = { id = id, hasMap = hasMap }
          end
        end
      end
    end
    for _, pick in pairs(chosen) do canonical[pick.id] = record(pick.id) end
    return canonical
  end

  function A.mapInfo(mapId)
    local value = reg.get("maps", mapId)
    if type(value) ~= "table" then return nil end
    -- MAP_TYPE_UNDERGROUND (4): caves roll the land table on every tile.
    -- Town (1), city (2), underwater (5), ocean route (6) and indoor (8:
    -- only its place keywords say what it is); routes (3) read as routes.
    local environment = ({ [1] = "TOWN", [2] = "TOWN", [4] = "CAVE", [5] = "OCEAN",
                           [6] = "OCEAN", [8] = "INDOOR" })[value.mapType] or "ROUTE"
    return { tileset = value.tileset, mapType = value.mapType, environment = environment }
  end

  -- No map order exists on Gen 3; the average wild level of a map's tables
  -- stands in for progression, so "recent maps" in the rolling history are
  -- maps of similar strength.
  function A.mapOrder()
    local order, level = {}, {}
    for id, rec in pairs(maps()) do
      local sum, n = 0, 0
      for _, spec in ipairs(KINDS) do
        local area = slotsOf(rec, spec[1])
        for _, s in ipairs(area and area.slots or {}) do
          sum = sum + ((s.minLevel or 0) + (s.maxLevel or s.minLevel or 0)) / 2
          n = n + 1
        end
      end
      if n > 0 then
        order[#order + 1] = id
        level[id] = sum / n
      end
    end
    table.sort(order, function(a, b)
      if level[a] ~= level[b] then return level[a] < level[b] end
      return a < b
    end)
    return order
  end

  function A.tables(mapId)
    local entries = {}
    local rec = maps()[mapId]
    if not rec then return entries end
    local info = A.mapInfo(mapId)
    for _, spec in ipairs(KINDS) do
      local kind, weights = spec[1], spec[2]
      local area = slotsOf(rec, kind)
      if area then
        local slots, w = {}, {}
        for i, s in ipairs(area.slots) do
          slots[i] = { species = s.species, level = s.minLevel or 1,
                       maxLevel = s.maxLevel or s.minLevel or 1 }
          w[i] = weights[i] or 0
        end
        entries[#entries + 1] = {
          kind = kind,
          terrain = kind == "water" and "water" or MapContext.landTerrain(info),
          def = { rate = area.rate, slots = slots }, weights = w,
        }
      end
    end
    -- Good / Super Rod: COMPLETE gives their slots pools (`pooled`), and
    -- their picks stay out of the map's shared memory (`isolated`), so adding
    -- fishing never moved a walking or surfing roster
    local fishing = slotsOf(rec, "fishing")
    for _, r in ipairs(RODS) do
      if fishing and #fishing.slots >= r.last then
        local slots, w = {}, {}
        for i = r.first, r.last do
          local s = fishing.slots[i]
          slots[#slots + 1] = { species = s.species, level = s.minLevel or 1,
                                maxLevel = s.maxLevel or s.minLevel or 1 }
          w[#w + 1] = r.weights[i - r.first + 1]
        end
        entries[#entries + 1] = {
          kind = r.kind, terrain = "fish", pooled = true, isolated = true,
          def = { rate = fishing.rate, slots = slots }, weights = w,
        }
      end
    end
    return entries
  end

  -- Generator output -> the game's own area shape.
  function A.assemble(_, _, result)
    local slots = {}
    for i, s in ipairs(result.slots) do
      slots[i] = { species = s.species, minLevel = s.level, maxLevel = s.maxLevel or s.level }
    end
    return { rate = result.rate, slots = slots }
  end

  -- ---------------------------------------------------------------- hooks

  -- ctx.terrain is "land" / "water" at a roll, "grass" / "indoor" / "water"
  -- in a preview.
  function A.rollKind(ctx)
    if type(ctx) ~= "table" then return nil end
    if ctx.terrain == "water" then return "water" end
    if ctx.terrain == "land" or ctx.terrain == "grass" or ctx.terrain == "indoor" then return "land" end
    -- no terrain from the engine (Emerald's rules read the tile themselves): a surfing
    -- player's roll is a water roll, as the rules decide it (encounter_rules/rse.lua classify)
    local Player = package.loaded["src.core.game3.player"]
    if type(Player) == "table" and Player.surfing == true then return "water" end
    return "land"
  end
  A.kindOfTerrain = function(terrain)
    if terrain == "water" then return "water" end
    if terrain == "land" or terrain == "grass" or terrain == "indoor" then return "land" end
    if terrain == "fish" or terrain == "superRod" or terrain == "fish.super" then return "fish.super" end
    if terrain == "goodRod" or terrain == "fish.good" then return "fish.good" end
    return nil
  end

  function A.rollValue() return nil end

  -- encounter.fishing hands (rod, mapId, candidates): the rod as a name
  -- ("OLD_ROD" / "GOOD_ROD" / "SUPER_ROD") and that rod's slots as
  -- { species, level, minLevel, maxLevel, item, chance }. The Old Rod and a
  -- map without fish answer nil (left as the game has it).
  function A.fishingKind(rod, mapId, candidates)
    local kind = ROD_KIND[rod]
    if not kind or type(candidates) ~= "table" or #candidates == 0 then return nil end
    return kind
  end

  -- The rod's candidate list with each slot's species swapped for the
  -- generated one (its numeric species slot, as the engine stores it); levels,
  -- odds and held items stay the game's own. nil (left alone) if any slot
  -- has no species the engine can take.
  function A.fishingValue(candidates, _, assembled)
    local out = {}
    for i, entry in ipairs(candidates) do
      local gen = assembled.slots[i]
      local slot = gen and A.liveValue(gen.species)
      if not slot then return nil end
      local copy = {}
      for k, v in pairs(entry) do copy[k] = v end
      copy.species = slot
      out[i] = copy
    end
    return out
  end

  function A.distribution(table_, kind)
    local weights = kind == "water" and WATER_WEIGHTS or LAND_WEIGHTS
    for _, r in ipairs(RODS) do
      if kind == r.kind then weights = r.weights end
    end
    local dist = {}
    for i, slot in ipairs(table_.slots) do
      if slot.species then
        dist[slot.species] = (dist[slot.species] or 0) + (weights[i] or 0)
      end
    end
    return dist
  end

  -- Every slot the engine's roll could have come from: same species, level inside the slot's
  -- range. `rolled.species` is the engine's name for it. Live sync puts the generated species
  -- into the game's own table, which is what the engine rolls on, so that table is asked first:
  -- its slots now hold different species, which pins the slot down. The cart's own table comes
  -- second; there several slots can match (all five of Sootopolis' surf slots are Magikarp), and
  -- the caller then picks among them by their odds.
  function A.slotCandidates(mapId, kind, _, rolled)
    local area = slotsOf(maps()[mapId], kind)
    if not area then return {} end
    local want = rolled.species
    if type(want) == "number" then
      local rec = reg.get("pokemon", want)
      want = type(rec) == "table" and rec.id or want
    end
    local level = tonumber(rolled.level)
    local wantSlot = tonumber(rolled.speciesId)
    local function same(name)
      if name == want then return true end
      -- a spelling the registry does not share: compare species slots
      local rec = wantSlot and reg.get("pokemon", name)
      return type(rec) == "table" and tonumber(rec.index) == wantSlot
    end
    local function inRange(s)
      return not level or (level >= (s.minLevel or level) and level <= (s.maxLevel or level))
    end
    local out = {}
    local live = A.liveSlots and A.liveSlots(mapId, kind)
    for i, s in ipairs(live and live[1] or {}) do
      local sp = s.species
      local hit = sp == want or (wantSlot ~= nil and tonumber(sp) == wantSlot)
        or (type(sp) == "string" and same(sp))
      if hit and inRange(s) then out[#out + 1] = i end
    end
    if #out > 0 then return out end
    for i, s in ipairs(area.slots) do
      if same(s.species) and inRange(s) then out[#out + 1] = i end
    end
    return out
  end

  -- The first of them (enough to tell a land roll from a water one), or nil.
  function A.slotIndex(mapId, kind, ctx, rolled)
    return A.slotCandidates(mapId, kind, ctx, rolled)[1]
  end

  -- The cart's odds per slot of a kind, for picking among several candidates.
  function A.slotWeights(kind)
    return kind == "water" and WATER_WEIGHTS or LAND_WEIGHTS
  end

  -- What live sync writes into a slot: the species' numeric slot, as the cart stores it (the
  -- engine's roll reads `tonumber(entry.species)`), or nil to leave that slot alone.
  function A.liveValue(id)
    local rec = reg.get("pokemon", id)
    return type(rec) == "table" and tonumber(rec.index) or nil
  end

  -- The encounter handed back to the engine: the species as its numeric
  -- slot (src/core/game3/encounters.lua engine_encounter).
  function A.withSpecies(out, id)
    local rec = reg.get("pokemon", id)
    local slot = type(rec) == "table" and tonumber(rec.index) or nil
    if not slot then return nil end
    local copy = {}
    for k, v in pairs(out) do copy[k] = v end
    copy.species, copy.speciesId = slot, slot
    return copy
  end

  -- ctx.rng is the game's own 16-bit stream and takes no range; this mod
  -- never draws from it (the runtime uses its seeded fallback instead).
  A.useEngineRng = false

  -- ------------------------------------------------------------ live sync

  -- Every alias id sharing mapId's mapGroup:mapNum. The encounters registry
  -- lists one map under several aliases (FR_ROUTE_1, ROUTE1, "3:19", ...),
  -- and -- confirmed empirically, unlike Gen 1/2 -- these are SEPARATE
  -- table objects, not the same one under different keys: writing through
  -- one alias does not update another, so every one of them has to be
  -- written for a raw reader keyed by any of them to see it.
  local function aliasIds(mapId)
    local rec = maps()[mapId]
    if not (rec and rec.mapGroup and rec.mapNum) then return { mapId } end
    local key, out = rec.mapGroup .. ":" .. rec.mapNum, {}
    for _, id in ipairs(reg.ids("encounters")) do
      if type(id) == "string" then
        local other = record(id)
        if other and other.mapGroup and other.mapNum
          and (other.mapGroup .. ":" .. other.mapNum) == key then
          out[#out + 1] = id
        end
      end
    end
    return #out > 0 and out or { mapId }
  end

  -- The map's mapGroup, mapNum (the Pokedex AREA page keys maps by them).
  function A.mapGroupNum(mapId)
    local rec = maps()[mapId]
    if not rec then return nil end
    return tonumber(rec.mapGroup), tonumber(rec.mapNum)
  end

  -- kind: "land" | "water". See gen1.lua's liveSlots and live_sync.lua's
  -- header for why this returns one array per alias, not one array.
  function A.liveSlots(mapId, kind)
    local data = mod and mod.game and mod.game.data
    local byId = data and data.gen3Encounters
    if not byId then return nil end
    local out = {}
    for _, id in ipairs(aliasIds(mapId)) do
      local area = byId[id] and byId[id][kind]
      if type(area) == "table" and type(area.slots) == "table" then
        out[#out + 1] = area.slots
      end
    end
    return #out > 0 and out or nil
  end

  -- ----------------------------------------------------------------- save

  -- The live Pokedex is game.session.dex, keyed by species slot.
  function A.owned(game, id)
    local dex = game and game.session and game.session.dex
    local rec = reg.get("pokemon", id)
    local slot = type(rec) == "table" and tonumber(rec.index) or nil
    return dex ~= nil and slot ~= nil and dex.owned ~= nil and dex.owned[slot] == true
  end

  -- The League is beaten once the game's own FLAG_SYS_GAME_CLEAR is set (the
  -- Hall of Fame sets it); game.save.flags is the engine's live flag view.
  function A.leagueCleared(game)
    local ok, value = pcall(function()
      local flags = game and game.save and game.save.flags
      return flags and flags.FLAG_SYS_GAME_CLEAR
    end)
    return ok and value == true
  end

  return A
end
