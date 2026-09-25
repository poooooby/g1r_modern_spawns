-- Standalone: luajit mods/modern_spawns/tests/integration_test.lua (from the
-- gen1recomp root; needs Red's imported data under red/). Loads the real mod
-- beside a national_dex test stub and drives the engine's own hook seams:
-- encounter.roll / encounter.fishing / encounter.table, the Mod Manager's
-- option writer, and the mod.exports framework surface.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local ROOT = H.modRoot()
local vanillaRoute1 = H.serialize(Data.encounters.ROUTE_1)

local function load(stub)
  local run = T.sdk.loadMods({ ROOT .. "/tests/fixtures/" .. stub .. "/national_dex",
                               "mods/modern_spawns" }, { data = Data })
  T.eq(#run.errors, 0, stub .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local mod = run.mods.modern_spawns
  T.check(mod ~= nil and mod.state == "loaded", stub .. ": modern_spawns is loaded")
  run.loader.modSave.modern_spawns = { seed = 777 }
  run.loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  H.manager(run.loader) -- a stub live game, never the engine singleton
  return run, run.loader.exports.modern_spawns
end

local function setOption(run, key, value)
  run.loader.modOptions.modern_spawns[key] = value
end

local function roll(mapId, terrain, encDef)
  -- the vanilla link hands back whatever table it was asked to roll on
  return Runtime.call("encounter.roll", function(def) return def end, encDef,
                      { mapId = mapId, terrain = terrain, rng = function() return 0 end })
end

local function registered(id) return Data.pokemon[id] ~= nil end

-- ================================================ national_dex with species

local run, api = load("modern")
T.check(api and api.apiVersion >= 1, "exports are published")
T.check(api.isActive(), "active with modern species registered")
T.eq(api.maxGeneration(), 9, "cap is GEN 1-9")

-- ------- grass: structure kept, species redistributed

local vanillaGrass = Data.encounters.ROUTE_1
local rolled = roll("ROUTE_1", "grass", vanillaGrass)
T.check(rolled ~= vanillaGrass, "ROUTE_1 grass rolls on the generated table")
T.eq(rolled.grass.rate, vanillaGrass.grass.rate, "rate kept")
T.eq(#rolled.grass.slots, #vanillaGrass.grass.slots, "slot count kept")
local levelsKept, allRegistered = true, true
for i, slot in ipairs(vanillaGrass.grass.slots) do
  if rolled.grass.slots[i].level ~= slot.level then levelsKept = false end
  if not registered(rolled.grass.slots[i].species) then allRegistered = false end
end
T.check(levelsKept, "every slot level kept")
T.check(allRegistered, "every species is registered")
T.eq(H.serialize(Data.encounters.ROUTE_1), vanillaRoute1, "game data is untouched")

-- caves roll the grass table as "indoor"
local cave = roll("MT_MOON_1F", "indoor", Data.encounters.MT_MOON_1F)
T.eq(#cave.grass.slots, #Data.encounters.MT_MOON_1F.grass.slots, "indoor keeps its slots")

-- ------- water keeps the { grass = water } wrapper shape

local water = Data.encounters.ROUTE_19.water
local wet = roll("ROUTE_19", "water", { grass = water })
T.check(wet.grass ~= water, "surfing rolls on the generated water table")
T.eq(wet.grass.rate, water.rate, "water rate kept")
T.eq(#wet.grass.slots, #water.slots, "water slot count kept")

-- ------- Super Rod

local rodMap
for mapId in pairs(Data.field.superRod) do rodMap = mapId break end
local rodPool = Data.field.superRod[rodMap]
local fished = Runtime.call("encounter.fishing", function(_, _, c) return c end,
                            "SUPER_ROD", rodMap, rodPool)
T.check(fished ~= rodPool, "the Super Rod uses the generated group")
T.eq(#fished, #rodPool, "and keeps its size")
local oldRod = Runtime.call("encounter.fishing", function(_, _, c) return c end,
                            "OLD_ROD", rodMap, nil)
T.eq(oldRod, nil, "the Old Rod is left alone")

-- ------- legendary never, generation cap respected

local function eachGenerated(fn)
  for mapId, enc in pairs(Data.encounters) do
    for _, terrain in ipairs({ "grass", "water" }) do
      local tbl = api.tableFor(mapId, terrain)
      if tbl and enc[terrain] then
        for _, slot in ipairs(tbl.slots) do fn(slot.species, mapId) end
      end
    end
  end
end
local modern = 0
eachGenerated(function(id, mapId)
  T.check(id ~= "RAIKOU", "no legendary on " .. mapId)
  if Data.pokemon[id].dex > 151 then modern = modern + 1 end
end)
T.check(modern > 0, "modern species actually appear (" .. modern .. " slots)")

setOption(run, "max_generation", "2")
eachGenerated(function(id, mapId)
  T.check(Data.pokemon[id].dex <= 251, id .. " respects GEN 1-2 on " .. mapId)
end)
setOption(run, "max_generation", "9")

-- ------- determinism per save

local first = H.serialize(api.tableFor("ROUTE_1", "grass"))
T.eq(H.serialize(api.tableFor("ROUTE_1", "grass")), first, "stable for one save")
run.loader.modSave.modern_spawns.seed = 778
api.invalidate()
local changed = false
for _, mapId in ipairs({ "ROUTE_1", "ROUTE_2", "ROUTE_3", "ROUTE_22", "VIRIDIAN_FOREST" }) do
  local before = H.serialize(api.tableFor(mapId, "grass"))
  run.loader.modSave.modern_spawns.seed = 777
  api.invalidate()
  if H.serialize(api.tableFor(mapId, "grass")) ~= before then changed = true end
  run.loader.modSave.modern_spawns.seed = 778
  api.invalidate()
end
T.check(changed, "a different save seed gives different tables")
run.loader.modSave.modern_spawns.seed = 777
api.invalidate()

-- ------- explain + candidates + profileOf

local explain = api.explain("ROUTE_1", "grass")
T.eq(#explain, #Data.encounters.ROUTE_1.grass.slots, "one explain record per slot")
T.check(#api.candidates({ maxGeneration = 1 }) > 100, "candidates lists the Gen 1 pool")
for _, c in ipairs(api.candidates()) do
  T.check(not c.special, "candidates leaves out special species by default")
end
T.eq(api.profileOf("PIDGEY").profileSource, "profile", "PIDGEY uses the shipped profile")
T.eq(api.profileOf("LECHONK").profileSource, "estimate",
     "LECHONK (no PokéAPI wild data) is estimated from runtime data")
T.eq(api.profileOf("FURRET").evolveLevel, 15, "national_dex evolutions reach the pool")

-- ------- preview matches the roll

local WorldAPI = require("src.world.WorldAPI")
local preview = WorldAPI.new({ data = Data }, "test"):effectiveEncounters("ROUTE_1", "grass")
for species in pairs(preview.dist) do
  local inTable = false
  for _, slot in ipairs(api.tableFor("ROUTE_1", "grass").slots) do
    if slot.species == species then inTable = true end
  end
  T.check(inTable, species .. " in the preview is in the rolled table")
end

-- ------- OFF and GEN 1 hand back the game's own tables

setOption(run, "enabled", "off")
T.eq(roll("ROUTE_1", "grass", vanillaGrass), vanillaGrass, "OFF rolls the original table")
T.check(not api.isActive(), "and reports inactive")
setOption(run, "enabled", "on")
setOption(run, "max_generation", "1")
T.eq(roll("ROUTE_1", "grass", vanillaGrass), vanillaGrass, "GEN 1 rolls the original table")
T.eq(api.tableFor("ROUTE_1", "grass"), nil, "and tableFor answers nil")
setOption(run, "max_generation", "9")

-- ------- settings live only in MODS -> Modern Spawns

local topLevel = { { id = "text_speed" } }
local rows = Runtime.call("ui.options.rows", function(_, r) return r end,
                          { data = Data }, topLevel)
T.eq(#rows, 1, "nothing is added to the top-level OPTION screen")

local schema, byKey = H.schema()
local keys = {}
for i, row in ipairs(schema) do keys[i] = row.key end
T.eq(table.concat(keys, ","),
     "enabled,max_generation,spawn_mode,legendaries,seed,reroll_seed",
     "the Mod Manager schema carries every setting, in menu order")
T.eq(byKey.enabled.label, "MODERN SPAWNS", "MODERN SPAWNS row")
T.eq(byKey.max_generation.label, "GENERATIONS", "GENERATIONS row")
T.eq(byKey.seed.type, "text", "SEED is a text row")
T.eq(byKey.seed.maxLen, 10, "with room for a 10-character seed")

-- the manager's own writer drives the mod live
local set = H.manager(run.loader)
set("max_generation", "2")
eachGenerated(function(id, mapId)
  T.check(Data.pokemon[id].dex <= 251, id .. " follows a MODS menu GEN 1-2 on " .. mapId)
end)
set("enabled", "off")
T.eq(roll("ROUTE_1", "grass", vanillaGrass), vanillaGrass, "MODS menu OFF rolls the original table")
set("enabled", "on")
set("max_generation", "9")
T.check(api.isActive(), "and back ON")

run.release()
T.finish("modern_spawns integration")
