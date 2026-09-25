-- Standalone: luajit mods/modern_spawns/tests/integration_no_modern_species_test.lua
-- (from the gen1recomp root; needs Red's imported data under red/).
-- national_dex installed with NATIONAL DEX OFF -- its default -- registers
-- nothing past #151. Modern spawns must stay out of the way entirely: the
-- engine rolls the game's own tables. A separate process from
-- integration_test.lua because a mod load merges into the shared Data.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/empty/national_dex",
                             "mods/modern_spawns" }, { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.modSave.modern_spawns = { seed = 777 }
run.loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
H.manager(run.loader) -- a stub live game, never the engine singleton
local api = run.loader.exports.modern_spawns

T.check(not api.isActive(), "nothing past #151 registered: inactive")
T.eq(api.maxGeneration(), nil, "no cap in force")
T.eq(api.tableFor("ROUTE_1", "grass"), nil, "tableFor answers nil")
local plain = Data.encounters.ROUTE_1
local rolled = Runtime.call("encounter.roll", function(def) return def end, plain,
                            { mapId = "ROUTE_1", terrain = "grass" })
T.eq(rolled, plain, "the engine rolls the game's own table")

run.release()
T.finish("modern_spawns integration (no modern species)")
