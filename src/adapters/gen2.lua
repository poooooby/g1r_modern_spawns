-- Gold / Silver / Crystal: the same interface as gen1.lua over Gen 2's data.
--
-- Gen 2 keys its wild data by KIND first (src/mods/Schemas.lua routes the
-- encounters registry to data.gen2Encounters):
--   grass[mapId] = { rates = {MORN,DAY,NITE}, slots = {MORN={7}, DAY={7}, NITE={7}} }
--   water[mapId] = { rate, slots = {3} }
--   fishGroups[group] = { chance, old = rows, good = rows, super = rows }
--     rows: { chance (cumulative /256), species, level [, timeGroup, day, nite] }
-- and a map's fish group comes from its map header (maps[id].fishGroup).
-- Odds are percent (src/battle/gen2/Encounter.lua): grass 30/30/20/10/5/4/1,
-- water 60/30/10.
--
-- Grass is handed to the generator as ONE 21-slot table (MORN 1-7, DAY
-- 8-14, NITE 15-21). Roles group slots by vanilla species across all three
-- times, so Pidgey-by-day becomes one species everywhere it appeared and a
-- night-only Hoothoot becomes a different one: the game's day/night
-- structure survives the redistribution.
--
-- Left as the game has them: the Old Rod (parity with Gen 1), Bug Contest
-- and `randomwildmon` script rolls (a script roll needs a species with a ROM
-- index), swarms, and -- because the engine raises no hook for them --
-- Headbutt, Rock Smash and roamers.

return function(reg, MapContext, mod)
  local A = { generation = 2 }

  local TIMES = { "MORN", "DAY", "NITE" }
  local GRASS_WEIGHTS = { 30, 30, 20, 10, 5, 4, 1 }
  local WATER_WEIGHTS = { 60, 30, 10 }
  local ROD_KEYS = { GOOD_ROD = "good", SUPER_ROD = "super" }
  local FISH_KINDS = { good = "fish.good", super = "fish.super" }

  local function kindTable(kind)
    local value = reg.get("encounters", kind)
    return type(value) == "table" and value or {}
  end

  function A.mapInfo(mapId)
    local value = reg.get("maps", mapId)
    return type(value) == "table" and value or nil
  end

  local function fishGroup(mapId)
    local info = A.mapInfo(mapId)
    local id = info and info.fishGroup
    if not id or id == 0 or id == "FISHGROUP_NONE" then return nil, nil end
    local group = kindTable("fishGroups")[id]
    return type(group) == "table" and group or nil, id
  end

  -- Maps with a grass or water table, in geographic order: by landmark
  -- (the map header's index into constants.landmarkOrder, which walks Johto
  -- then Kanto), ties by the ROM's own map order. constants.mapOrder alone
  -- is map-GROUP order (it starts in Olivine), which would make "the
  -- previous few maps" in the rolling history meaningless.
  function A.mapOrder()
    local ids, seen = {}, {}
    for _, kind in ipairs({ "grass", "water" }) do
      for id in pairs(kindTable(kind)) do
        if type(id) == "string" and not seen[id] then
          seen[id] = true
          ids[#ids + 1] = id
        end
      end
    end
    local romIndex = {}
    local order = reg.get("constants", "mapOrder")
    for i, id in ipairs(type(order) == "table" and order or {}) do romIndex[id] = i end
    local function key(id)
      local info = A.mapInfo(id)
      return tonumber(info and info.landmark) or 999, romIndex[id] or 9999
    end
    table.sort(ids, function(a, b)
      local la, ra = key(a)
      local lb, rb = key(b)
      if la ~= lb then return la < lb end
      if ra ~= rb then return ra < rb end
      return a < b
    end)
    return ids
  end

  local function copySlot(slot)
    return { level = slot.level, species = slot.species }
  end

  -- The map's fish rows for one rod, as generator slots + weights (the
  -- difference between consecutive cumulative chances). A row with day/nite
  -- variants contributes its default species.
  local function fishEntry(group, rodKey)
    local rows = group and group[rodKey]
    if type(rows) ~= "table" or #rows == 0 then return nil end
    local slots, weights, prev = {}, {}, 0
    for i, row in ipairs(rows) do
      if type(row.species) ~= "string" or row.species == "NO_ITEM" then return nil end
      slots[i] = copySlot(row)
      weights[i] = math.max(0, (row.chance or 0) - prev)
      prev = row.chance or prev
    end
    return { kind = FISH_KINDS[rodKey], terrain = "fish",
             def = { rate = 1, slots = slots }, weights = weights }
  end

  function A.tables(mapId)
    local entries = {}
    local info = A.mapInfo(mapId)
    local grass = kindTable("grass")[mapId]
    if type(grass) == "table" and type(grass.slots) == "table" then
      local slots, weights, times, rate = {}, {}, {}, 0
      for _, time in ipairs(TIMES) do
        local list = grass.slots[time] or {}
        for i = 1, #GRASS_WEIGHTS do
          if list[i] then
            slots[#slots + 1] = list[i]
            weights[#weights + 1] = GRASS_WEIGHTS[i]
            times[#times + 1] = time
          end
        end
        rate = math.max(rate, tonumber(grass.rates and grass.rates[time]) or 0)
      end
      if #slots > 0 then
        entries[#entries + 1] = { kind = "grass", terrain = MapContext.landTerrain(info),
                                  def = { rate = rate, slots = slots }, weights = weights,
                                  times = times }
      end
    end
    local water = kindTable("water")[mapId]
    if type(water) == "table" and type(water.slots) == "table" and #water.slots > 0 then
      local weights = {}
      for i = 1, #water.slots do weights[i] = WATER_WEIGHTS[i] or 0 end
      entries[#entries + 1] = { kind = "water", terrain = "water",
                                def = { rate = water.rate, slots = water.slots },
                                weights = weights }
    end
    -- Fish groups are shared by many maps (FISHGROUP_SHORE is on hundreds of
    -- headers, most of them indoors), so only maps with wild tables get
    -- their own redistributed rods; the rest keep the game's.
    if #entries > 0 then
      local group = fishGroup(mapId)
      for _, rodKey in ipairs({ "good", "super" }) do
        local entry = fishEntry(group, rodKey)
        if entry then entries[#entries + 1] = entry end
      end
    end
    return entries
  end

  -- A species' habit on the game's own clock: "night" if the cart only ever
  -- puts it in NITE grass lists (Hoothoot, Gastly, ...), "day" if never at
  -- night, nil when it is both or absent (every modern species). Read once
  -- from the runtime tables; the generator keeps night roles nocturnal.
  local habits
  function A.timeOf(id)
    if not habits then
      habits = {}
      local seen = {}
      for _, entry in pairs(kindTable("grass")) do
        for _, time in ipairs(TIMES) do
          for _, slot in ipairs(type(entry) == "table" and entry.slots
                                and entry.slots[time] or {}) do
            local s = seen[slot.species] or {}
            seen[slot.species] = s
            s[time == "NITE" and "night" or "day"] = true
          end
        end
      end
      for species, s in pairs(seen) do
        if s.night and not s.day then habits[species] = "night"
        elseif s.day and not s.night then habits[species] = "day" end
      end
    end
    return habits[id]
  end

  -- Generator output -> the engine's own shapes.
  function A.assemble(mapId, kind, result)
    if kind == "grass" then
      local vanilla = kindTable("grass")[mapId] or {}
      local slots, n = {}, 0
      for _, time in ipairs(TIMES) do
        local list = {}
        for i = 1, #((vanilla.slots or {})[time] or {}) do
          n = n + 1
          list[i] = result.slots[n]
        end
        slots[time] = list
      end
      local rates = {}
      for k, v in pairs(vanilla.rates or {}) do rates[k] = v end
      return { map = mapId, rates = rates, slots = slots }
    end
    if kind == "water" then
      local vanilla = kindTable("water")[mapId] or {}
      return { map = mapId, rate = vanilla.rate, slots = result.slots }
    end
    -- fish: the vanilla rows' cumulative chances with new species; day/nite
    -- variants dropped so Encounter.fish reads the row's own species
    local group = fishGroup(mapId)
    local rodKey = kind == "fish.good" and "good" or "super"
    local rows = {}
    for i, row in ipairs(group and group[rodKey] or {}) do
      local slot = result.slots[i] or row
      rows[i] = { chance = row.chance, species = slot.species, level = slot.level }
    end
    return rows
  end

  -- ---------------------------------------------------------------- hooks

  local function isNight(ctx)
    local t = ctx and (ctx.daytime or ctx.tod)
    return t == "NITE" or t == "DARK"
  end

  -- Only ordinary steps and SWEET SCENT roll the wild tables this mod
  -- redistributes; the Bug Contest and `randomwildmon` scripts stay vanilla.
  function A.rollKind(ctx)
    if type(ctx) ~= "table" then return nil end
    if ctx.kind ~= nil and ctx.kind ~= "wild" and ctx.kind ~= "sweet_scent" then
      return nil
    end
    return ctx.terrain == "water" and "water" or "grass"
  end

  -- encounter.roll pipes the whole kind-first table (or a swarm view of it).
  -- Replace just this map's entry; pass a swarm through untouched.
  function A.rollValue(tables, ctx, kind, table_)
    if type(tables) ~= "table" then return nil end
    local live = kindTable(kind)[ctx.mapId]
    local piped = tables[kind] and tables[kind][ctx.mapId]
    if piped ~= live then return nil end -- a swarm substituted this map
    local out = {}
    for k, v in pairs(tables) do out[k] = v end
    out[kind] = setmetatable({ [ctx.mapId] = table_ }, { __index = tables[kind] })
    return out
  end

  function A.fishingKind(rod, mapId, candidates, ctx)
    local rodKey = ROD_KEYS[rod]
    if not rodKey or type(candidates) ~= "table" then return nil end
    -- a fishing swarm swaps the group; keep the swarm's own fish
    local swarm = type(ctx) == "table" and tonumber(ctx.swarm) or 0
    if swarm ~= 0 then return nil end
    local _, groupId = fishGroup(mapId)
    if type(ctx) == "table" and ctx.fishGroup and ctx.fishGroup ~= groupId then
      return nil
    end
    return FISH_KINDS[rodKey]
  end

  -- The group row handed down the chain: the vanilla row with this rod's
  -- list replaced (the bite gate `chance` and the other rods untouched).
  function A.fishingValue(candidates, kind, rows)
    local out = {}
    for k, v in pairs(candidates) do out[k] = v end
    out[kind == "fish.good" and "good" or "super"] = rows
    return out
  end

  -- encounter.table preview (percent weights). The preview has no time of
  -- day, so grass shows the DAY list.
  function A.distribution(table_, kind)
    local dist = {}
    local slots, weights = table_.slots, WATER_WEIGHTS
    if kind == "grass" then
      slots, weights = table_.slots.DAY or {}, GRASS_WEIGHTS
    end
    for i, slot in ipairs(slots) do
      if slot and slot.species then
        dist[slot.species] = (dist[slot.species] or 0) + (weights[i] or 0)
      end
    end
    return dist
  end

  -- Which generated slot (flat index) the engine rolled. Gen 2 results carry
  -- the slot index; grass adds the time-of-day block offset.
  function A.slotIndex(mapId, kind, ctx, rolled)
    local vanilla = kindTable(kind)[mapId]
    if type(vanilla) ~= "table" then return nil end
    local list, offset = vanilla.slots, 0
    if kind == "grass" then
      local time = isNight(ctx) and "NITE"
        or ((ctx and (ctx.daytime or ctx.tod)) == "MORN" and "MORN" or "DAY")
      for _, t in ipairs(TIMES) do
        if t == time then break end
        offset = offset + #((vanilla.slots or {})[t] or {})
      end
      list = (vanilla.slots or {})[time]
    end
    if type(list) ~= "table" then return nil end
    local i = tonumber(rolled.slot)
    if not (i and list[i] and list[i].species == rolled.species) then
      i = nil
      for j, slot in ipairs(list) do
        if slot.species == rolled.species and slot.level == rolled.level then i = j break end
      end
    end
    return i and offset + i or nil
  end

  -- ------------------------------------------------------------ live sync

  -- kind: "grass" | "water"; time ("MORN"/"DAY"/"NITE") applies to grass
  -- only. See gen1.lua's liveSlots and live_sync.lua's header.
  function A.liveSlots(mapId, kind, time)
    local data = mod and mod.game and mod.game.data
    local byMap = data and data.gen2Encounters and data.gen2Encounters[kind]
    local entry = byMap and byMap[mapId]
    if not entry or type(entry.slots) ~= "table" then return nil end
    local list = (kind == "grass") and time and entry.slots[time] or entry.slots
    return (type(list) == "table" and #list > 0) and { list } or nil
  end

  -- ----------------------------------------------------------------- save

  -- Gold writes save.pokedex.caught (BattleState), not Gen 1's `owned`.
  function A.owned(game, id)
    local dex = game and game.save and game.save.pokedex
    if not dex then return false end
    return (dex.caught ~= nil and dex.caught[id] == true)
      or (dex.owned ~= nil and dex.owned[id] == true)
  end

  return A
end
