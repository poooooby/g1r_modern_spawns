-- Standalone: luajit mods/modern_spawns/tests/gen3_test.lua (from the
-- gen1recomp root; needs Pokemon FireRed imported under firered/ and
-- mods/national_dex_gen3 installed -- the species mod FireRed depends on).
-- FireRed's roll ignores the table handed to encounter.roll's `next`, so
-- the Gen 3 adapter swaps species AFTER the roll, in encounter.species, and
-- hands the engine numeric species slots. These checks drive the hooks with
-- the engine's own result shape ({ species = name, speciesId, level }).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")

local data = H.gen3Data()
local P = data.gen3Pokemon
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean on FireRed (" .. tostring(run.errors[1]) .. ")")
T.check(run.mods.modern_spawns and run.mods.modern_spawns.state == "loaded",
        "modern_spawns targets FireRed")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "KANTO" }
-- LIMITED: these checks are about one fixed table per map (COMPLETE, the default, draws a
-- pool per encounter)
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", spawn_mode = "seeded" }
local set, game = H.manager(loader)
local api = loader.exports.modern_spawns
T.eq(api.generation(), 3, "the Gen 3 adapter runs")
T.check(api.isActive(), "active with national_dex_gen3's species")

local function wraps(name)
  for _, w in ipairs(Runtime.hooks.chains[name] or {}) do
    if w.owner == "modern_spawns" then return true end
  end
  return false
end
T.check(wraps("encounter.species"), "encounter.species is wrapped")
T.check(wraps("encounter.fishing"), "encounter.fishing is wrapped (Good and Super Rods)")

local live = data.gen3Encounters

-- the engine's own result for a vanilla slot (src/core/game3/encounters.lua
-- mod_encounter: species is Pokemon.keyName, e.g. NIDORAN_F), run through
-- the hooks
local function encounter(mapId, kind, slot)
  local name = P.keyName(slot.species)
  return Runtime.call("encounter.species", function(e) return e end,
    { species = name, speciesId = slot.species, level = slot.minLevel },
    { mapId = mapId, terrain = kind, rng = function() return 4321 end })
end

-- the maps the game runs under: FR_ aliases with a map record
local runtimeMaps = {}
for id, rec in pairs(live) do
  if type(id) == "string" and id:match("^FR_") and data.maps[id]
    and (rec.land or rec.water) then
    runtimeMaps[#runtimeMaps + 1] = id
  end
end
table.sort(runtimeMaps)
T.check(#runtimeMaps > 80, "FireRed's wild maps (" .. #runtimeMaps .. ")")

local function eachSlot(fn)
  for _, mapId in ipairs(runtimeMaps) do
    for _, kind in ipairs({ "land", "water" }) do
      local area = live[mapId][kind]
      if area and area.rate and area.rate > 0 then
        for i, slot in ipairs(area.slots) do fn(mapId, kind, i, slot) end
      end
    end
  end
end

-- ------- every slot: a registered species, as a slot number, at its level

local mapping = {}
eachSlot(function(mapId, kind, i, slot)
  local out = encounter(mapId, kind, slot)
  local where = mapId .. " " .. kind .. " slot " .. i
  T.eq(type(out.species), "number", where .. " comes back as a species slot")
  T.eq(out.speciesId, out.species, where .. " speciesId agrees")
  T.check(P._names[out.species] ~= nil, where .. " is a registered species")
  T.eq(out.level, slot.minLevel, where .. " keeps the rolled level")
  -- slots that held one species share one new species -- except in a table whose every slot
  -- held the same one (all-Magikarp water), which gets a species per slot
  local area = live[mapId][kind]
  local distinct = {}
  for _, s in ipairs(area.slots) do distinct[s.species] = true end
  local single = next(distinct, next(distinct)) == nil
  local key = mapId .. kind .. slot.species
  if not single and mapping[key] and mapping[key] ~= out.species then
    T.check(false, where .. ": one vanilla species became two")
  end
  mapping[key] = out.species
  -- and it is what the published table says for a slot this roll could have come from (same
  -- cart species, level in range: several, when the cart's slots all held one species)
  local tbl = api.tableFor(mapId, kind)
  local fits = false
  for j, s in ipairs(area.slots) do
    if s.species == slot.species and slot.minLevel >= s.minLevel and slot.minLevel <= s.maxLevel then
      local rec = loader.content.pokemon:get(tbl.slots[j].species)
      if rec and rec.index == out.species then fits = true end
    end
  end
  T.check(fits, where .. " matches tableFor")
end)

-- the roll itself is left to the engine: its table is never swapped
local rec = live.FR_ROUTE_1
T.eq(Runtime.call("encounter.roll", function(v) return v end, rec,
     { mapId = "FR_ROUTE_1", terrain = "land" }), rec, "encounter.roll passes FireRed's record through")

-- modern species really appear
local modern = 0
for _, slot in pairs(mapping) do
  if (P.national(slot) or 0) > 386 or slot > 450 then modern = modern + 1 end
end
T.check(modern > 0, "species past #386 appear (" .. modern .. " roles)")

-- ------- generation caps and OFF

set("max_generation", "3")
eachSlot(function(mapId, kind, i, slot)
  local out = encounter(mapId, kind, slot)
  T.check(out.species <= 411, mapId .. " slot " .. i .. " respects GEN 1-3")
end)
-- GEN 1 shuffles the Gen 1 species (#1-151) like any other cap
set("max_generation", "1")
eachSlot(function(mapId, kind, i, slot)
  local out = encounter(mapId, kind, slot)
  local n = P.national and P.national(out.species) or out.species
  T.check(tonumber(n) and tonumber(n) <= 151, mapId .. " slot " .. i .. " respects GEN 1")
end)
set("max_generation", "9")
set("enabled", "off")
plain = encounter("FR_ROUTE_1", "land", live.FR_ROUTE_1.land.slots[1])
T.eq(plain.species, P.keyName(live.FR_ROUTE_1.land.slots[1].species), "OFF: the game's own encounter")
set("enabled", "on")

-- ------- preview

local dist = Runtime.call("encounter.table", function(d) return d end, {},
                          { mapId = "FR_ROUTE_1", terrain = "grass", preview = true })
local total = 0
for id, w in pairs(dist) do
  total = total + w
  T.check(loader.content.pokemon:get(id) ~= nil, id .. " in the preview is a species")
end
T.eq(total, 100, "the preview's weights are FireRed's land percentages")

-- ------- RANDOM and EVERY MAP

set("spawn_mode", "random")
local seen = {}
for _ = 1, 30 do
  local out = encounter("FR_ROUTE_1", "land", live.FR_ROUTE_1.land.slots[1])
  T.check(P._names[out.species] ~= nil, "RANDOM draws a registered species")
  seen[out.species] = true
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
T.check(distinct > 1, "RANDOM varies on FireRed (" .. distinct .. ")")
set("spawn_mode", "map")
loader.events:emit("map.entered", { mapId = "FR_ROUTE_2" })
local first = H.serialize(api.tableFor("FR_ROUTE_2", "land"))
local changed = false
for _ = 1, 8 do
  loader.events:emit("map.entered", { mapId = "FR_ROUTE_1" })
  loader.events:emit("map.entered", { mapId = "FR_ROUTE_2" })
  if H.serialize(api.tableFor("FR_ROUTE_2", "land")) ~= first then changed = true break end
end
T.check(changed, "EVERY MAP redraws on FireRed")
set("spawn_mode", "seeded")

-- ------- fishing: the Good and Super Rods get new species, the Old Rod stays

-- what the engine hands encounter.fishing for one rod (src/core/game3/
-- encounters.lua fishing_pool): that rod's slots with levels and odds
local RANGES = { OLD_ROD = { 1, 2 }, GOOD_ROD = { 3, 5 }, SUPER_ROD = { 6, 10 } }
local function candidates(mapId, rod)
  local out, r = {}, RANGES[rod]
  for i = r[1], r[2] do
    local s = live[mapId].fishing.slots[i]
    out[#out + 1] = { species = P.keyName(s.species), level = s.minLevel, minLevel = s.minLevel,
                      maxLevel = s.maxLevel, chance = 10 * i }
  end
  return out
end
-- the list the engine would roll, after the hooks
local function cast(mapId, rod)
  return Runtime.call("encounter.fishing", function(_, _, list) return list end,
    rod, mapId, candidates(mapId, rod))
end

local FISH_MAP = "FR_ROUTE_10"
local old = cast(FISH_MAP, "OLD_ROD")
T.eq(H.serialize(old), H.serialize(candidates(FISH_MAP, "OLD_ROD")), "the Old Rod is the game's own")
local fishable, kept, levelsKept = true, true, true
for _, rod in ipairs({ "GOOD_ROD", "SUPER_ROD" }) do
  local before, after = candidates(FISH_MAP, rod), cast(FISH_MAP, rod)
  local generated = api.tableFor(FISH_MAP, rod == "GOOD_ROD" and "fish.good" or "fish.super")
  T.check(generated ~= nil and #generated.slots == #before, rod .. ": a generated table per rod")
  for i, entry in ipairs(after) do
    if type(entry.species) ~= "number" then kept = false end
    if entry.minLevel ~= before[i].minLevel or entry.maxLevel ~= before[i].maxLevel
      or entry.chance ~= before[i].chance then levelsKept = false end
    local p = api.profileOf(generated.slots[i].species)
    local terrains = {}
    for _, t in ipairs(p and p.terrains or {}) do terrains[t] = true end
    local types = {}
    for _, t in ipairs(p and p.types or {}) do types[t] = true end
    if not (terrains.water or terrains.fish or types.WATER) then fishable = false end
    if loader.content.pokemon:get(generated.slots[i].species).index ~= entry.species then kept = false end
  end
end
T.check(kept, "a cast hands the engine the generated species, as species slots")
T.check(levelsKept, "levels and odds stay the game's own")
T.check(fishable, "only water species are fished")
T.eq(H.serialize(api.tableFor(FISH_MAP, "fish")), H.serialize(api.tableFor(FISH_MAP, "fish.super")), "\"fish\" means the Super Rod")

-- every rod table holds only registered species
local allRegistered = true
for _, mapId in ipairs(runtimeMaps) do
  for _, terrain in ipairs({ "fish.good", "fish.super" }) do
    for _, slot in ipairs((api.tableFor(mapId, terrain) or {}).slots or {}) do
      if not loader.content.pokemon:get(slot.species) then allRegistered = false end
    end
  end
end
T.check(allRegistered, "every rod slot is a registered species")

-- COMPLETE: a rod slot is drawn from its pool, which keeps the game's own fish
set("spawn_mode", "complete")
local pools = api.poolFor(FISH_MAP, "fish.super")
T.check(pools ~= nil and #pools == 5, "COMPLETE gives the Super Rod's slots pools")
local ownKept = true
for i = 6, 10 do
  local own = P.keyName(live[FISH_MAP].fishing.slots[i].species)
  local found = false
  for _, id in ipairs(pools and pools[i - 5] or {}) do
    if loader.content.pokemon:get(id).index == live[FISH_MAP].fishing.slots[i].species then found = true end
  end
  if not found then ownKept = false end
end
T.check(ownKept, "each Super Rod pool keeps the game's own fish for that slot")
local seen = {}
for _ = 1, 200 do
  for _, entry in ipairs(cast(FISH_MAP, "SUPER_ROD")) do seen[entry.species] = true end
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
T.check(distinct > 5, "COMPLETE casts draw across the pools (" .. distinct .. " species)")
set("spawn_mode", "seeded")

-- ------- legendaries: rare, hosted, stop once owned

set("legendaries", "on")
local homes = api.legendaryHomes()
T.check(homes.FR_POWER_PLANT ~= nil, "the Power Plant hosts legendaries")
-- the game's own FLAG_SYS_GAME_CLEAR (set by the Hall of Fame) unlocks the roll,
-- read the way the engine reads it: the live flag store, the version's numeric id
-- (a name key in the save snapshot is not a flag the engine ever writes)
local Flags = require("src.core.game3.scripting.flags")
game.session = { version = "firered", flags = {}, vars = {} }
game.save.flags = { FLAG_SYS_GAME_CLEAR = true }
local CLEAR = Flags.active(game.session).IDS.FLAG_SYS_GAME_CLEAR
T.eq(CLEAR, 0x82C, "FireRed's FLAG_SYS_GAME_CLEAR")
local hostIndex = {}
for _, h in ipairs(homes.FR_POWER_PLANT.land) do
  hostIndex[loader.content.pokemon:get(h.id).index] = true
end
local early = false
for _ = 1, 5000 do
  local out = encounter("FR_POWER_PLANT", "land", live.FR_POWER_PLANT.land.slots[1])
  if hostIndex[out.species] then early = true break end
end
T.check(not early, "no legendary before FLAG_SYS_GAME_CLEAR (a name key in the snapshot does not count)")
local Space = package.loaded["src.core.game3.scripting.space"]
Flags.setFlag((Space and Space.store) or game.session, nil, CLEAR, true)
T.eq(homes.FR_ROUTE_1, nil, "Route 1 hosts none")
local hosts, hostSlots = {}, {}
for _, h in ipairs(homes.FR_POWER_PLANT.land) do
  hosts[h.id] = true
  hostSlots[loader.content.pokemon:get(h.id).index] = true
end
local slot = live.FR_POWER_PLANT.land.slots[1]
local hit
for _ = 1, 20000 do
  local out = encounter("FR_POWER_PLANT", "land", slot)
  if hostSlots[out.species] then hit = out break end
end
T.check(hit ~= nil, "a hosted legendary eventually appears in the Power Plant")
T.eq(hit and hit.level, slot.minLevel, "at the rolled level")
local owned = {}
for s in pairs(hostSlots) do owned[s] = true end
game.session.dex = { owned = owned, seen = {}, caught = {} }
local again = false
for _ = 1, 20000 do
  if hostSlots[encounter("FR_POWER_PLANT", "land", slot).species] then again = true break end
end
T.check(not again, "owned legendaries (session.dex.owned) never appear again")
game.session = nil

-- ------- the Sevii Islands' places have themes (see placement_test.lua)

local MapContext = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/../src/map_context.lua")
local SEVII = {
  { "FR_FIVE_ISLAND_LOST_CAVE_ROOM1", 0.40, "Ghost in the Lost Cave" },
  { "FR_FOUR_ISLAND_ICEFALL_CAVE_1F", 0.75, "Ice/Water in Icefall Cave" },
  { "FR_THREE_ISLAND_BERRY_FOREST", 0.75, "Bug/Grass in Berry Forest" },
  { "FR_MT_EMBER_EXTERIOR", 0.55, "Fire/Rock on Mt. Ember" },
}
local fitN, allN = {}, {}
for s = 1, 8 do
  loader.modSave.modern_spawns = { seed = "SEVII" .. s }
  api.invalidate()
  for _, place in ipairs(SEVII) do
    local theme = MapContext.describe(place[1], nil, "grass").types
    for _, slot in ipairs((api.tableFor(place[1], "land") or {}).slots or {}) do
      allN[place[1]] = (allN[place[1]] or 0) + 1
      local p = api.profileOf(slot.species)
      for _, t in ipairs(p and p.types or {}) do
        if theme[(tostring(t):gsub("_TYPE$", ""))] then fitN[place[1]] = (fitN[place[1]] or 0) + 1 break end
      end
    end
  end
end
for _, place in ipairs(SEVII) do
  local share = (fitN[place[1]] or 0) / math.max(1, allN[place[1]] or 0)
  T.check(share >= place[2], string.format("%s: %d%% (want %d%%+)", place[3],
    math.floor(share * 100 + 0.5), math.floor(place[2] * 100)))
end

run.release()
T.finish("modern_spawns gen3")
