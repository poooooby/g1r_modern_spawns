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
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local set, game = H.manager(loader)
local api = loader.exports.modern_spawns
T.eq(api.generation(), 3, "the Gen 3 adapter runs")
T.check(api.isActive(), "active with national_dex_gen3's species")

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
set("max_generation", "1")
local plain = encounter("FR_ROUTE_1", "land", live.FR_ROUTE_1.land.slots[1])
T.eq(plain.species, P.keyName(live.FR_ROUTE_1.land.slots[1].species), "GEN 1: the game's own encounter")
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

-- ------- legendaries: rare, hosted, stop once owned

set("legendaries", "on")
local homes = api.legendaryHomes()
T.check(homes.FR_POWER_PLANT ~= nil, "the Power Plant hosts legendaries")
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
game.session = { dex = { owned = owned, seen = {}, caught = {} } }
local again = false
for _ = 1, 20000 do
  if hostSlots[encounter("FR_POWER_PLANT", "land", slot).species] then again = true break end
end
T.check(not again, "owned legendaries (session.dex.owned) never appear again")
game.session = nil

run.release()
T.finish("modern_spawns gen3")
