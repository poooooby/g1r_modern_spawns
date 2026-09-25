-- Standalone: luajit mods/modern_spawns/tests/legendaries_test.lua (from the
-- gen1recomp root; needs Red's imported data under red/).
-- LEGENDARIES: hosted legendary/mythical encounters at 1/1024 and 1/2048,
-- only on their home maps, never once owned, never in the tables themselves.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/modern/national_dex",
                             "mods/modern_spawns" }, { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "PALLET" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local api = loader.exports.modern_spawns
local set, game = H.manager(loader)

local function setOption(key, value)
  loader.modOptions.modern_spawns[key] = value
  loader.events:emit("mod.options_changed", { mod = "modern_spawns", key = key, value = value })
end

-- an encounter the engine rolled, run through encounter.species with a
-- fixed integer RNG (1 always wins a 1-in-N roll, 2 never does)
local function encounter(mapId, terrain, rngValue)
  local def = Data.encounters[mapId][terrain == "water" and "water" or "grass"]
  local slot = def.slots[1]
  return Runtime.call("encounter.species", function(e) return e end,
    { species = slot.species, level = slot.level },
    { mapId = mapId, terrain = terrain, rng = function(lo) return rngValue or lo end }), slot
end

local function homeOf(homes, id)
  local found = {}
  for mapId, byKind in pairs(homes) do
    for kind, list in pairs(byKind) do
      for _, h in ipairs(list) do
        if h.id == id then found[#found + 1] = mapId .. ":" .. kind end
      end
    end
  end
  table.sort(found)
  return found
end

-- ------- homes

T.eq(api.settings().legendaries, false, "LEGENDARIES defaults to OFF")
local homes = api.legendaryHomes()
T.check(type(homes) == "table", "homes are computed")
local function anyAt(mapId, prefix)
  for _, where in ipairs(homeOf(homes, mapId)) do
    if where:sub(1, #prefix) == prefix then return true end
  end
  return false
end
T.check(anyAt("ZAPDOS", "POWER_PLANT"), "Zapdos lives in the Power Plant ("
  .. table.concat(homeOf(homes, "ZAPDOS"), ", ") .. ")")
T.check(anyAt("ARTICUNO", "SEAFOAM_ISLANDS"), "Articuno lives in the Seafoam Islands ("
  .. table.concat(homeOf(homes, "ARTICUNO"), ", ") .. ")")
T.check(anyAt("MEWTWO", "CERULEAN_CAVE"), "Mewtwo lives in Cerulean Cave ("
  .. table.concat(homeOf(homes, "MEWTWO"), ", ") .. ")")
for _, early in ipairs({ "ROUTE_1", "ROUTE_2", "VIRIDIAN_FOREST", "MT_MOON_1F", "ROUTE_3" }) do
  T.eq(homes[early], nil, early .. " hosts no legendary")
end
for mapId, byKind in pairs(homes) do
  for kind in pairs(byKind) do
    local top = 0
    for _, slot in ipairs(Data.encounters[mapId][kind].slots) do
      top = math.max(top, slot.level)
    end
    T.check(top >= 30, mapId .. " " .. kind .. " reaches level 30")
  end
end

-- ------- the rare roll

local plain = encounter("POWER_PLANT", "grass", 1)
T.neq(plain.species, "ZAPDOS", "OFF: even a winning roll gives no legendary")

setOption("legendaries", "on")
local hostList = homes.POWER_PLANT.grass
local hostSet = {}
for _, h in ipairs(hostList) do hostSet[h.id] = h.category end
local won, slot = encounter("POWER_PLANT", "grass", 1)
T.check(hostSet[won.species] ~= nil, "ON + winning roll: a Power Plant host appears ("
  .. tostring(won.species) .. ")")
T.eq(won.level, slot.level, "at the level the engine rolled")
T.eq(hostSet[won.species], "legendary", "the legendary roll comes first")
local lost = encounter("POWER_PLANT", "grass", 2)
T.check(hostSet[lost.species] == nil, "a losing roll changes nothing")
local elsewhere = encounter("ROUTE_1", "grass", 1)
T.check(Data.pokemon[elsewhere.species] and not hostSet[elsewhere.species],
        "a map with no home never gets one")

-- the odds the roll asks for
local asked = {}
Runtime.call("encounter.species", function(e) return e end,
  { species = Data.encounters.POWER_PLANT.grass.slots[1].species,
    level = Data.encounters.POWER_PLANT.grass.slots[1].level },
  { mapId = "POWER_PLANT", terrain = "grass",
    rng = function(lo, hi) asked[#asked + 1] = hi return 2 end })
T.eq(asked[1], 1024, "legendaries roll 1 in 1024")

-- ------- owned species stop appearing

local owned = {}
for _, h in ipairs(hostList) do
  if h.category == "legendary" then owned[h.id] = true end
end
game.save.pokedex = { owned = owned, seen = {} }
local afterCatch = encounter("POWER_PLANT", "grass", 1)
T.check(not owned[afterCatch.species], "an owned legendary never appears again ("
  .. tostring(afterCatch.species) .. ")")
if next(owned) then
  local mythicalLeft = false
  for _, h in ipairs(hostList) do
    if h.category == "mythical" then mythicalLeft = true end
  end
  if mythicalLeft then
    T.eq(hostSet[afterCatch.species], "mythical", "a mythical host can still appear")
  end
end
game.save.pokedex = nil

-- ------- every SPAWN MODE, and the tables stay clean

setOption("spawn_mode", "random")
local randomWin = encounter("POWER_PLANT", "grass", 1)
T.check(hostSet[randomWin.species] ~= nil, "RANDOM mode still rolls legendaries first")
setOption("spawn_mode", "map")
T.check(hostSet[encounter("POWER_PLANT", "grass", 1).species] ~= nil,
        "EVERY MAP mode too")
setOption("spawn_mode", "seeded")
for mapId in pairs(Data.encounters) do
  for _, terrain in ipairs({ "grass", "water" }) do
    local tbl = api.tableFor(mapId, terrain)
    for _, s in ipairs(tbl and tbl.slots or {}) do
      T.check(not hostSet[s.species] and s.species ~= "MEWTWO" and s.species ~= "MEW",
              "no special species in " .. mapId .. " " .. terrain)
    end
  end
end

-- ------- the MODS -> Modern Spawns row

local _, schemaByKey = H.schema()
T.eq(schemaByKey.legendaries.label, "LEGENDARIES", "LEGENDARIES is a Mod Manager row")
T.eq(schemaByKey.legendaries.default, "off", "defaulting to OFF")
set("legendaries", "off")
T.eq(api.settings().legendaries, false, "turned OFF from the MODS menu")
T.check(not hostSet[encounter("POWER_PLANT", "grass", 1).species],
        "and a winning roll gives no legendary")

run.release()
T.finish("modern_spawns legendaries")
