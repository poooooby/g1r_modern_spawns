-- Standalone: luajit mods/modern_spawns/tests/dex1025_compat_test.lua (from
-- the gen1recomp root; needs Pokemon FireRed imported under firered/ and
-- mods/national_dex_gen3 installed).
-- Beside 1025Dex, Modern Spawns decides FireRed's grass/cave/surf encounters
-- while ON, and 1025Dex's WILD GENS keeps everything else: fishing, Rock
-- Smash, and every wild battle while Modern Spawns is OFF. A stub 1025Dex
-- patches a stand-in battle bridge exactly the way the real one does.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")

-- the engine's battle bridge, reduced to "which foe does the battle get"
package.loaded["src.core.game3.battle_bridge"] = {
  start = function(_, _, foe) return foe end,
}
local Bridge = package.loaded["src.core.game3.battle_bridge"]

local data = H.gen3Data()
local P = data.gen3Pokemon
local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/gen3/1025dex",
                             "mods/national_dex_gen3", "mods/modern_spawns" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean beside 1025Dex (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
T.check(not loader.exports.national_dex_gen3.isActive(),
        "national_dex_gen3 steps aside for 1025Dex")
loader.modSave.modern_spawns = { seed = "KANTO" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
H.manager(loader)
T.check(Bridge.__modernSpawnsWrapped, "Modern Spawns wraps the bridge outside 1025Dex")

local slot = data.gen3Encounters.FR_ROUTE_1.land.slots[1]
local function step()
  return Runtime.call("encounter.species", function(e) return e end,
    { species = P.keyName(slot.species), speciesId = slot.species, level = slot.minLevel },
    { mapId = "FR_ROUTE_1", terrain = "land", rng = function() return 1 end })
end
local function battle(foe, wild)
  return Bridge.start(nil, nil, { species = foe.speciesId or foe.species,
                                  speciesId = foe.speciesId, level = foe.level },
                      { wild = wild ~= false })
end

-- ------- ON: our encounters reach the battle; everything else is WILD GENS'

local ours = step()
local foe = battle(ours)
T.eq(foe.species, ours.speciesId, "ON: the encounter Modern Spawns decided is the one battled")
T.neq(foe.species, 999, "WILD GENS left it alone")

local fishing = battle({ species = 129, speciesId = 129, level = 5 })
T.eq(fishing.species, 999, "a fishing encounter (no hook) still gets WILD GENS")

step()
local stale = battle({ species = 129, speciesId = 129, level = 5 })
T.eq(stale.species, 999, "a battle whose foe is not our encounter is WILD GENS'")
T.eq(battle({ species = 129, speciesId = 129, level = 5 }).species, 999,
     "and the marker never outlives one battle")

local trainer = battle({ species = 25, speciesId = 25, level = 12 }, false)
T.eq(trainer.species, 25, "trainer battles are nobody's business")

-- ------- OFF: WILD GENS as it always was

loader.modOptions.modern_spawns.enabled = "off"
local offEnc = step()
T.eq(battle(offEnc).species, 999, "OFF: WILD GENS replaces the encounter")

run.release()
package.loaded["src.core.game3.battle_bridge"] = nil
T.finish("modern_spawns 1025Dex compat")
