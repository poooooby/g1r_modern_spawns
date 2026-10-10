-- Standalone: luajit mods/modern_spawns/tests/frlg_area_test.lua (from the
-- gen1recomp root; needs FireRed imported under firered/ and
-- mods/national_dex_gen3).
--
-- The FireRed/LeafGreen Pokedex AREA page (src/dex_area.lua) marks named
-- areas. Under COMPLETE every placed species must come out with at least one
-- area that has a marker: Kanto's on the Kanto map, the Sevii Islands' on
-- their island maps (national_dex_gen3 draws those), and a Sevii map with no
-- marker of its own (Six Island's Green Path) borrows its island's. Measured
-- on the seed RMMLCVGS that first showed the gap: 382 species were Sevii-only
-- and 2 had no area at all. The cart's area data and map-section names are
-- read straight from the cache, which is not mounted headlessly.
package.path = "./?.lua;./?/init.lua;" .. package.path
require("src.core.GameVersion").set("firered")

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local CacheBlob = require("src.import.CacheBlob")
local function readLua(path)
  local f = assert(io.open(path, "rb"))
  local src = CacheBlob.decode(path, f:read("*a"))
  f:close()
  return load(src, "@" .. path, "t", {})()
end

local data = H.gen3Data("firered")
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "RMMLCVGS" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9",
                                    spawn_mode = "complete", legendaries = "on" }
local set, game = H.manager(loader)
game.data = data
local ms = loader.exports.modern_spawns

local root = "firered/data/generated/gba"
require("src.import.gba.map_sections_extract").installNames(readLua(root .. "/region_map/names.lua").names)
local PD = require("src.core.game3.pokedex_data")
PD._entries = {}
PD._areaData = readLua(root .. "/pokemon/pokedex/area_markers.lua")

local located, noMarker, sevii = 0, {}, 0
for _, c in ipairs(ms.candidates({ maxGeneration = 9, includeSpecial = true })) do
  if next(ms.locate(c.id) or {}) then
    located = located + 1
    local marked, kanto = 0, 0
    for _, area in ipairs(PD.getWildAreasForSpecies(tonumber(loader.content.pokemon:get(c.id).index))) do
      if PD.getAreaMarker(area) then
        marked = marked + 1
        if PD.getAreaMapKey(area) == "kanto" then kanto = kanto + 1 end
      end
    end
    if marked == 0 then noMarker[#noMarker + 1] = c.id end
    if marked > 0 and kanto == 0 then sevii = sevii + 1 end
  end
end
T.check(located > 900, "COMPLETE places the whole dex (" .. located .. ")")
T.eq(#noMarker, 0, "every placed species has an area with a marker ("
  .. table.concat(noMarker, ", ", 1, math.min(#noMarker, 8)) .. ")")
T.check(sevii > 0, "some live only on the Sevii Islands (" .. sevii .. "), so the island maps matter")

-- Six Island's Green Path: no marker of its own, its island's instead
local greenPath
for _, c in ipairs(ms.candidates({ maxGeneration = 9 })) do
  local maps = ms.locate(c.id) or {}
  if maps.FR_SIX_ISLAND_GREEN_PATH then greenPath = c.id break end
end
if greenPath then
  local areas = PD.getWildAreasForSpecies(tonumber(loader.content.pokemon:get(greenPath).index))
  local six = false
  for _, a in ipairs(areas) do if a == "DEX_AREA_SIX_ISLAND" then six = true end end
  T.check(six, "a species on Green Path is marked on Six Island (" .. greenPath .. ")")
end

run.release()
T.finish("modern_spawns FireRed AREA page")
