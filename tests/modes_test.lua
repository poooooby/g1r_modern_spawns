-- Standalone: luajit mods/modern_spawns/tests/modes_test.lua (from the
-- gen1recomp root; needs Red's imported data under red/).
-- SPAWN MODE (SEEDED / EVERY MAP / RANDOM) and the seed controls: the seed
-- survives mode changes, only reroll/typing changes it, EVERY MAP redraws on
-- map entry, RANDOM redraws per encounter while keeping the engine's slot.
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
loader.modSave.modern_spawns = { seed = 777 } -- a 0.1.0-style numeric seed
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local api = loader.exports.modern_spawns
local set, game = H.manager(loader)

local function setOption(key, value)
  loader.modOptions.modern_spawns[key] = value
  loader.events:emit("mod.options_changed", { mod = "modern_spawns", key = key, value = value })
end

local function enterMap(mapId)
  loader.events:emit("map.entered", { mapId = mapId })
end

local function roll(mapId)
  return Runtime.call("encounter.roll", function(def) return def end,
                      Data.encounters[mapId], { mapId = mapId, terrain = "grass" })
end

local function species(mapId, enc)
  return Runtime.call("encounter.species", function(e) return e end, enc,
                      { mapId = mapId, terrain = "grass" })
end

-- ------- seed: old numeric seeds, persistence across modes

T.eq(api.seed(), "777", "a 0.1.0 numeric seed reads back as its digits")
T.eq(api.spawnMode(), "seeded", "SEEDED is the default mode")
local seededRoute1 = H.serialize(api.tableFor("ROUTE_1", "grass"))

setOption("spawn_mode", "map")
T.eq(api.seed(), "777", "switching to EVERY MAP keeps the seed")
setOption("spawn_mode", "random")
T.eq(api.seed(), "777", "switching to RANDOM keeps the seed")
setOption("spawn_mode", "seeded")
T.eq(api.seed(), "777", "switching back keeps the seed")
T.eq(H.serialize(api.tableFor("ROUTE_1", "grass")), seededRoute1,
     "and SEEDED gives the same tables as before the round trip")

-- ------- seed: reroll and typed seeds

local rerolled = api.rerollSeed()
T.check(type(rerolled) == "string" and rerolled ~= "777", "reroll picks a new seed")
T.eq(loader.modSave.modern_spawns.seed, rerolled, "stored in the save's bucket")
T.check(rerolled:match("^[A-Z]+$") ~= nil, "a letter code the naming screen can type")

T.eq(api.setSeed("PALLET"), "PALLET", "a typed seed is accepted")
local pallet = H.serialize(api.tableFor("ROUTE_1", "grass"))
api.setSeed("CERULEAN")
api.setSeed("PALLET")
T.eq(H.serialize(api.tableFor("ROUTE_1", "grass")), pallet,
     "the same typed seed reproduces the same tables")
T.eq(api.setSeed("   "), nil, "an empty seed is refused")
T.eq(api.seed(), "PALLET", "and leaves the seed alone")
T.eq(#api.setSeed("ABCDEFGHIJKLMNOP"), 10, "seeds are capped at 10 characters")
api.setSeed("PALLET")

-- ------- EVERY MAP

setOption("spawn_mode", "map")
enterMap("ROUTE_1")
local visit1 = H.serialize(api.tableFor("ROUTE_1", "grass"))
T.eq(H.serialize(api.tableFor("ROUTE_1", "grass")), visit1, "stable within one visit")
T.eq(roll("ROUTE_1").grass.slots[1].species, api.tableFor("ROUTE_1", "grass").slots[1].species,
     "the roll uses the current visit's table")
local changed = false
for _ = 1, 8 do
  enterMap("ROUTE_2")
  enterMap("ROUTE_1")
  if H.serialize(api.tableFor("ROUTE_1", "grass")) ~= visit1 then changed = true break end
end
T.check(changed, "re-entering the map draws a new roster")
local levelsKept = true
for i, slot in ipairs(Data.encounters.ROUTE_1.grass.slots) do
  if api.tableFor("ROUTE_1", "grass").slots[i].level ~= slot.level then levelsKept = false end
end
T.check(levelsKept, "every visit keeps the slot levels")
T.eq(api.seed(), "PALLET", "visits never touch the seed")

-- ------- RANDOM

setOption("spawn_mode", "random")
T.eq(api.tableFor("ROUTE_1", "grass"), nil, "RANDOM has no fixed table")
T.eq(roll("ROUTE_1"), Data.encounters.ROUTE_1, "the engine rolls the game's own table")
local vanillaSlot = Data.encounters.ROUTE_1.grass.slots[1]
local seen, allRegistered, levelKept = {}, true, true
for _ = 1, 30 do
  local out = species("ROUTE_1", { species = vanillaSlot.species, level = vanillaSlot.level })
  seen[out.species] = true
  if not Data.pokemon[out.species] then allRegistered = false end
  if out.level ~= vanillaSlot.level then levelKept = false end
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
T.check(distinct > 1, "encounters draw different species (" .. distinct .. " seen)")
T.check(allRegistered, "every drawn species is registered")
T.check(levelKept, "the rolled level is kept")
T.check(not seen.RAIKOU, "a legendary is never drawn")
local foreign = species("ROUTE_1", { species = "MEWTWO", level = 70 })
T.eq(foreign.species, "MEWTWO", "an encounter that is not from the table is left alone")
local rodMap
for mapId in pairs(Data.field.superRod) do rodMap = mapId break end
local fished = Runtime.call("encounter.fishing", function(_, _, c) return c end,
                            "SUPER_ROD", rodMap, Data.field.superRod[rodMap])
T.eq(#fished, #Data.field.superRod[rodMap], "RANDOM Super Rod groups keep their size")

-- drawFor: a fresh table per call for consumers that pick species themselves
local drawn, sameShape = {}, true
for i = 1, 10 do
  local t = api.drawFor("ROUTE_1", "grass")
  if not (t and #t.slots == #Data.encounters.ROUTE_1.grass.slots) then sameShape = false end
  drawn[H.serialize(t)] = true
end
local draws = 0
for _ in pairs(drawn) do draws = draws + 1 end
T.check(sameShape, "RANDOM drawFor keeps the game's slot count")
T.check(draws > 1, "RANDOM drawFor draws afresh each call (" .. draws .. " distinct)")

-- SEEDED ignores the species hook
setOption("spawn_mode", "seeded")
local kept = species("ROUTE_1", { species = "PIDGEY", level = 3 })
T.eq(kept.species, "PIDGEY", "SEEDED leaves the rolled species to the table")
T.eq(H.serialize(api.drawFor("ROUTE_1", "grass")), H.serialize(api.tableFor("ROUTE_1", "grass")),
     "SEEDED drawFor is the fixed table")
setOption("enabled", "off")
T.eq(api.drawFor("ROUTE_1", "grass"), nil, "drawFor answers nil while OFF")
setOption("enabled", "on")

-- ------- SEED and REROLL SEED in MODS -> Modern Spawns

local _, schemaByKey = H.schema()
T.eq(schemaByKey.spawn_mode.label, "SPAWN MODE", "SPAWN MODE is a Mod Manager row")
T.eq(schemaByKey.reroll_seed.default, "idle", "REROLL SEED rests on '-'")

local bucket = function() return loader.modOptions.modern_spawns end
set("spawn_mode", "map")
T.eq(api.spawnMode(), "map", "SPAWN MODE set from the MODS menu")
set("spawn_mode", "seeded")
T.eq(game.save.options.modOptions.modern_spawns.spawn_mode, "seeded",
     "written to the save's option bucket, like any manager option")

-- the SEED row mirrors the loaded save's seed
api.setSeed("PALLET")
T.eq(bucket().seed, "PALLET", "the SEED row shows the save's seed")
set("seed", "VIRIDIAN")
T.eq(api.seed(), "VIRIDIAN", "typing a seed in the MODS menu sets the save's seed")
set("seed", "")
T.eq(api.seed(), "VIRIDIAN", "an empty entry keeps the seed")
T.eq(bucket().seed, "VIRIDIAN", "and the row reads it again")

set("reroll_seed", "reroll")
T.neq(api.seed(), "VIRIDIAN", "REROLL draws a new seed")
T.eq(bucket().seed, api.seed(), "the SEED row follows it")
T.eq(bucket().reroll_seed, "idle", "and the REROLL row snaps back to '-'")

-- RESET DEFAULTS writes each row's default: it must not wipe or reroll
local before = api.seed()
for _, row in ipairs((H.schema())) do set(row.key, row.default) end
T.eq(api.seed(), before, "RESET DEFAULTS keeps the seed")
T.eq(bucket().seed, before, "and the SEED row still shows it")

-- a seed typed before NEW GAME is the new game's seed
set("seed", "CINNABAR")
loader.modSave.modern_spawns = {}            -- the new save's empty bucket
loader.events:emit("save.created", {})
T.eq(api.seed(), "CINNABAR", "NEW GAME starts with the seed typed in the MODS menu")
-- CONTINUE keeps the loaded save's own seed, and the row shows it
loader.modSave.modern_spawns = { seed = "SAFFRON" }
loader.events:emit("save.loaded", {})
T.eq(api.seed(), "SAFFRON", "CONTINUE keeps that save's seed")
T.eq(bucket().seed, "SAFFRON", "and the SEED row switches to it")
-- with nothing typed, a new game gets a fresh seed
loader.modSave.modern_spawns = {}
loader.events:emit("save.created", {})
T.check(api.seed() ~= "SAFFRON" and api.seed() ~= "CINNABAR",
        "a NEW GAME with nothing typed gets its own seed (" .. api.seed() .. ")")
T.eq(bucket().seed, api.seed(), "shown in the SEED row")

run.release()
T.finish("modern_spawns modes")
