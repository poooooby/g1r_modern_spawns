-- Standalone: luajit mods/modern_spawns/tests/placement_test.lua (from the
-- gen1recomp root; needs Emerald imported under emerald/ and
-- mods/national_dex_gen3).
--
-- Themed places draw species that fit them. Hoenn's places used to have no
-- theme at all (every non-cave Gen 3 map read as a plain route), and any
-- shared habitat tag -- "route" included, which nearly every species has --
-- counted as a full habitat match, so Mt. Pyre held Shellos and Spritzee and
-- New Mauville Arcanine. These checks hold the fix: Gen 3 place keywords
-- (map_context.lua), a theme requirement in the strict tier, and a stronger
-- map_type score. Thresholds sit under what it measures (85-99%) and well
-- over the old behaviour.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local here = (arg[0]:gsub("\\", "/"):match("^(.*)/") or ".")
local H = dofile(here .. "/_helpers.lua")
local MapContext = dofile(here .. "/../src/map_context.lua")

local data = H.gen3Data("emerald")
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", spawn_mode = "seeded" }
local set, game = H.manager(loader)
game.data = data
local ms = loader.exports.modern_spawns

local function typesOf(id)
  local p = ms.profileOf(id)
  local out = {}
  for _, t in ipairs(p and p.types or {}) do out[(tostring(t):gsub("_TYPE$", ""))] = true end
  return out
end

-- share of a map's walking slots, over many seeds, holding a species of one
-- of the place's theme types
local SEEDS = 12
local PLACES = {
  { "EM_MT_PYRE_6F", 0.80, "Ghost in Mt. Pyre" },
  { "EM_NEW_MAUVILLE_INSIDE", 0.75, "Electric/Steel in New Mauville" },
  { "EM_PETALBURG_WOODS", 0.75, "Bug/Grass in Petalburg Woods" },
  { "EM_GRANITE_CAVE_1F", 0.70, "Rock/Steel/Fighting in Granite Cave" },
  { "EM_SHOAL_CAVE_LOW_TIDE_ICE_ROOM", 0.70, "Ice/Water in Shoal Cave's ice room" },
  { "EM_ROUTE111", 0.80, "Ground/Rock in the desert" },
}
local fit, total = {}, {}
for s = 1, SEEDS do
  loader.modSave.modern_spawns = { seed = "PLACE" .. s }
  ms.invalidate()
  for _, place in ipairs(PLACES) do
    local mapId = place[1]
    local theme = MapContext.describe(mapId, nil, "grass").types
    for _, slot in ipairs((ms.tableFor(mapId, "land") or {}).slots or {}) do
      total[mapId] = (total[mapId] or 0) + 1
      for t in pairs(typesOf(slot.species)) do
        if theme[t] then fit[mapId] = (fit[mapId] or 0) + 1 break end
      end
    end
  end
end
for _, place in ipairs(PLACES) do
  local mapId, want, label = place[1], place[2], place[3]
  local share = (fit[mapId] or 0) / math.max(1, total[mapId] or 0)
  T.check((total[mapId] or 0) > 0, mapId .. " has a land table")
  T.check(share >= want, string.format("%s: %d%% (want %d%%+)", label,
    math.floor(share * 100 + 0.5), math.floor(want * 100)))
end

-- ordinary routes stay open to everything: no theme, so no theme filter
T.eq(next(MapContext.describe("EM_ROUTE101", nil, "grass").types), nil, "Route 101 has no theme type")

run.release()
T.finish("modern_spawns placement (Emerald)")
