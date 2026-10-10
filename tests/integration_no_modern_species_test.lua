-- Standalone: luajit mods/modern_spawns/tests/integration_no_modern_species_test.lua
-- (from the gen1recomp root; needs Red's imported data under red/).
-- No species past #151 registered -- national_dex installed with NATIONAL DEX OFF (its default),
-- which is the same as no species mod at all. Since 0.12.0 Modern Spawns works on the cart's own
-- species: GEN 1-9 is capped at Gen 1, every table is shuffled among Red's 151, and COMPLETE
-- (the default mode) puts every one of them somewhere. A separate process from
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

T.check(api.isActive(), "the cart's own species are enough: active")
T.eq(api.maxGeneration(), 1, "capped at what is registered (Gen 1)")
T.eq(api.spawnMode(), "complete", "COMPLETE is the default")
local t = api.tableFor("ROUTE_1", "grass")
T.check(t ~= nil, "Route 1 has a generated table")
local plain = Data.encounters.ROUTE_1
local rolled = Runtime.call("encounter.roll", function(def) return def end, plain,
                            { mapId = "ROUTE_1", terrain = "grass" })
T.check(rolled ~= plain, "the engine rolls the generated table")

-- every Gen 1 species (but the legendaries) lives somewhere
local seen = {}
for mapId in pairs(Data.encounters) do
  for _, terrain in ipairs({ "grass", "water" }) do
    for _, list in pairs(api.poolFor(mapId, terrain) or {}) do
      for _, id in ipairs(list) do seen[id] = true end
    end
  end
end
local missing = {}
for _, c in ipairs(api.candidates({ maxGeneration = 1 })) do
  if not seen[c.id] then missing[#missing + 1] = c.id end
end
T.eq(#missing, 0, "COMPLETE: every Gen 1 species is catchable (" .. table.concat(missing, ", ", 1, math.min(#missing, 8)) .. ")")

run.release()
T.finish("modern_spawns integration (no modern species)")
