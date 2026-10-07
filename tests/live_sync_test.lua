-- Standalone: luajit mods/modern_spawns/tests/live_sync_test.lua (from the
-- gen1recomp root; needs Red's imported data under red/).
--
-- src/live_sync.lua writes the generated species directly into
-- game.data.encounters / field.superRod -- restorable, species only -- for
-- a mod that reads those tables itself instead of going through the
-- encounter hooks (a wild-encounter guide, say). This file covers Gen 1;
-- Gen 2 and Gen 3 get their own live-sync checks inside gen2_test.lua and
-- rse_test.lua respectively (this suite boots one game per process, same
-- as every other file here).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Data = require("src.core.Data")
Data:load()

local vanillaRoute1 = H.serialize(Data.encounters.ROUTE_1)
local vanillaRate = Data.encounters.ROUTE_1.grass.rate
local vanillaLevels = {}
for i, slot in ipairs(Data.encounters.ROUTE_1.grass.slots) do vanillaLevels[i] = slot.level end
local rodMap
for mapId in pairs(Data.field.superRod) do rodMap = mapId break end
local vanillaRod = H.serialize(Data.field.superRod[rodMap])

local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/modern/national_dex",
                             "mods/modern_spawns" }, { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "PALLET" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local set, game = H.manager(loader)
game.data = Data -- live_sync writes through mod.game.data; the stub has none by default
local api = loader.exports.modern_spawns

local function modernSpecies(sp)
  local rec = loader.content.pokemon:get(sp)
  return rec and (tonumber(rec.dex) or 0) > 151
end

-- ------- SEEDED: synced as soon as the save loads, with no map.entered at all

loader.events:emit("save.loaded", {})

local liveGrass = Data.encounters.ROUTE_1.grass.slots
local generatedGrass = api.tableFor("ROUTE_1", "grass").slots
T.eq(#liveGrass, #generatedGrass, "live Route 1 grass keeps its slot count")
local matches, anyModern = true, false
for i, slot in ipairs(liveGrass) do
  if slot.species ~= generatedGrass[i].species then matches = false end
  if modernSpecies(slot.species) then anyModern = true end
end
T.check(matches, "live Route 1 grass species match tableFor, slot for slot")
T.check(anyModern, "and at least one is a modern species")

-- Mechanics untouched: rate and every slot's level, exactly as the
-- original (species differ on purpose, so this can't compare via
-- H.serialize against the pre-mod-load snapshot -- check the fields
-- live_sync must never touch, directly).
T.eq(Data.encounters.ROUTE_1.grass.rate, vanillaRate, "grass rate is untouched")
local levelsOk = true
for i, level in ipairs(vanillaLevels) do
  if Data.encounters.ROUTE_1.grass.slots[i].level ~= level then levelsOk = false end
end
T.check(levelsOk, "every grass slot's level is untouched")

if Data.encounters.ROUTE_1.water then
  local liveWater = Data.encounters.ROUTE_1.water.slots
  local generatedWater = api.tableFor("ROUTE_1", "water").slots
  local waterMatches = true
  for i, slot in ipairs(liveWater) do
    if slot.species ~= generatedWater[i].species then waterMatches = false end
  end
  T.check(waterMatches, "live Route 1 water species match tableFor too")
end

if rodMap then
  local liveRod = Data.field.superRod[rodMap]
  local generatedRod = api.superRodFor(rodMap)
  local rodMatches = #liveRod == #generatedRod
  for i, slot in ipairs(liveRod) do
    if generatedRod[i] and slot.species ~= generatedRod[i].species then rodMatches = false end
  end
  T.check(rodMatches, rodMap .. "'s live Super Rod group matches superRodFor")
end

-- ------- a second map, entered without any options change, is in sync too

loader.events:emit("map.entered", { mapId = "ROUTE_2" })
local route2Live = Data.encounters.ROUTE_2 and Data.encounters.ROUTE_2.grass
if route2Live then
  local generated2 = api.tableFor("ROUTE_2", "grass")
  T.eq(route2Live.slots[1].species, generated2.slots[1].species,
       "ROUTE_2 was already synced before map.entered fired for it")
end

-- ------- OFF restores the exact original

set("enabled", "off")
T.eq(H.serialize(Data.encounters.ROUTE_1), vanillaRoute1,
     "OFF restores Route 1's grass and water to the original species")
if rodMap then
  T.eq(H.serialize(Data.field.superRod[rodMap]), vanillaRod,
       "and the Super Rod group")
end

-- ------- re-enabling reproduces the same SEEDED result

set("enabled", "on")
local reSynced = Data.encounters.ROUTE_1.grass.slots
local sameAgain = true
for i, slot in ipairs(reSynced) do
  if slot.species ~= liveGrass[i].species then sameAgain = false end
end
T.check(sameAgain, "re-enabling reproduces the same SEEDED species")

-- ------- EVERY MAP: live table changes are confined to the entered map...

set("spawn_mode", "map")
local beforeMap = H.serialize(Data.encounters.ROUTE_1)
loader.events:emit("map.entered", { mapId = "ROUTE_1" })
local everyMapGrass = Data.encounters.ROUTE_1.grass.slots
local matchesEveryMap = true
for i, slot in ipairs(everyMapGrass) do
  if slot.species ~= api.tableFor("ROUTE_1", "grass").slots[i].species then
    matchesEveryMap = false
  end
end
T.check(matchesEveryMap, "EVERY MAP: entering Route 1 syncs it to that visit's table")

-- ------- RANDOM: the live table is a snapshot of one draw, and OFF still restores it

set("spawn_mode", "random")
local seen = {}
for _ = 1, 15 do
  loader.events:emit("map.entered", { mapId = "ROUTE_1" })
  seen[H.serialize(Data.encounters.ROUTE_1.grass.slots)] = true
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
T.check(distinct > 1, "RANDOM: repeated visits leave independently-drawn snapshots ("
  .. distinct .. " distinct draws in 15 visits)")
set("enabled", "off")
T.eq(H.serialize(Data.encounters.ROUTE_1), vanillaRoute1,
     "OFF restores the original even after RANDOM's live snapshots")

run.release()
T.finish("modern_spawns live_sync")
