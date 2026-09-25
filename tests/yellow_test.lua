-- Standalone: luajit mods/modern_spawns/tests/yellow_test.lua (from the
-- gen1recomp root; needs Pokemon Yellow imported under yellow/).
-- Yellow runs the Gen 1 adapter over its own tables: different species and
-- levels, eight water tables instead of Red's three, and four-entry Super
-- Rod groups. Blue shares Red's layout exactly and is not imported here.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("yellow")
local Data = require("src.core.Data")
Data:load()
-- Headless, Data:load cannot see the versioned yellow/ cache (CacheFs reads
-- through love.filesystem) and falls back to the developer copy under
-- data/generated -- Red. Put Yellow's own wild data in place: its
-- encounters, Super Rod groups, maps and map order.
local function yellow(name) return dofile("yellow/data/generated/" .. name .. ".lua") end
Data.encounters = yellow("encounters")
Data.field.superRod = yellow("field").superRod
Data.maps = yellow("maps")
Data.constants.mapOrder = yellow("constants").mapOrder

local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/modern/national_dex",
                             "mods/modern_spawns" }, { data = Data })
T.eq(#run.errors, 0, "loads clean on Yellow (" .. tostring(run.errors[1]) .. ")")
T.check(run.mods.modern_spawns and run.mods.modern_spawns.state == "loaded",
        "modern_spawns targets Yellow")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "PIKACHU" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
H.manager(loader)
local api = loader.exports.modern_spawns
T.eq(api.generation(), 1, "the Gen 1 adapter runs")
T.check(api.isActive(), "active")

-- ------- every table keeps its structure

local waterMaps, grassMaps = 0, 0
for mapId, enc in pairs(Data.encounters) do
  for _, terrain in ipairs({ "grass", "water" }) do
    local vanilla = enc[terrain]
    if vanilla and vanilla.rate > 0 and #vanilla.slots > 0 then
      if terrain == "water" then waterMaps = waterMaps + 1 else grassMaps = grassMaps + 1 end
      local ctxTerrain = terrain
      local rolled = Runtime.call("encounter.roll", function(def) return def end,
        terrain == "water" and { grass = vanilla } or enc,
        { mapId = mapId, terrain = ctxTerrain })
      local g = rolled.grass
      T.check(g ~= vanilla, mapId .. " " .. terrain .. " rolls on a generated table")
      T.eq(g.rate, vanilla.rate, mapId .. " " .. terrain .. " rate kept")
      T.eq(#g.slots, #vanilla.slots, mapId .. " " .. terrain .. " slot count kept")
      for i, slot in ipairs(vanilla.slots) do
        T.eq(g.slots[i].level, slot.level, mapId .. " " .. terrain .. " slot " .. i .. " level")
        T.check(Data.pokemon[g.slots[i].species] ~= nil,
                mapId .. " " .. terrain .. " slot " .. i .. " is registered")
      end
    end
  end
end
T.eq(waterMaps, 8, "all eight of Yellow's water tables are redistributed")
T.check(grassMaps > 40, "and its grass/cave tables (" .. grassMaps .. ")")

for mapId, group in pairs(Data.field.superRod) do
  local fished = Runtime.call("encounter.fishing", function(_, _, c) return c end,
                              "SUPER_ROD", mapId, group)
  T.eq(#fished, #group, mapId .. " Super Rod keeps its " .. #group .. " entries")
end

-- ------- OFF / GEN 1 hand back the game's own table

loader.modOptions.modern_spawns.enabled = "off"
T.eq(Runtime.call("encounter.roll", function(def) return def end,
                  Data.encounters.ROUTE_1, { mapId = "ROUTE_1", terrain = "grass" }),
     Data.encounters.ROUTE_1, "OFF rolls Yellow's own table")
loader.modOptions.modern_spawns.enabled = "on"
loader.modOptions.modern_spawns.max_generation = "1"
T.eq(Runtime.call("encounter.roll", function(def) return def end,
                  Data.encounters.ROUTE_1, { mapId = "ROUTE_1", terrain = "grass" }),
     Data.encounters.ROUTE_1, "GEN 1 rolls Yellow's own table")

run.release()
GameVersion.set("red")
T.finish("modern_spawns yellow")
