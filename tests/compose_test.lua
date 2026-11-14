-- Standalone: luajit mods/modern_spawns/tests/compose_test.lua (from the
-- gen1recomp root; needs Emerald imported under emerald/ and
-- mods/national_dex_gen3 installed).
--
-- A species randomizer layered on top (fixtures/outer_randomizer: wraps
-- encounter.species and encounter.fishing at priority 100) must see
-- WoobleSpawns' choice and have the last word, in every SPAWN MODE. This is
-- the contract DEVELOPMENT.md "Changing species on top" documents.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
require("src.core.GameVersion").set("emerald")

local data = H.gen3Data("emerald")
local P = data.gen3Pokemon
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns",
                             "mods/modern_spawns/tests/fixtures/outer_randomizer" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "COMPOSE" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
-- the stub game keeps no data, so live sync writes nothing and the map's slots
-- below stay the cart's own (live sync is live_sync_test's job)
local set = H.manager(loader)
local api, outer = loader.exports.modern_spawns, loader.exports.outer_randomizer
T.check(api.isActive(), "WoobleSpawns is active")

local function order(name)
  local out = {}
  for _, w in ipairs(Runtime.hooks.chains[name] or {}) do out[#out + 1] = w.owner end
  return table.concat(out, " > ")
end
T.eq(order("encounter.species"), "outer_randomizer > modern_spawns",
     "encounter.species: the randomizer wraps WoobleSpawns")
T.eq(order("encounter.fishing"), "outer_randomizer > modern_spawns",
     "encounter.fishing: the randomizer wraps WoobleSpawns")

-- a wild map with land slots and Super Rod slots
local mapId
for id, rec in pairs(data.gen3Encounters) do
  if type(id) == "string" and data.maps[id] and rec.land and rec.fishing
    and api.tableFor(id, "land") then
    if not mapId or id < mapId then mapId = id end
  end
end
T.check(mapId ~= nil, "a map with land and fishing slots (" .. tostring(mapId) .. ")")
local area, fish = data.gen3Encounters[mapId].land, data.gen3Encounters[mapId].fishing

-- the engine's own result shapes (src/core/game3/encounters.lua mod_encounter)
local function step(i)
  local slot = area.slots[(i - 1) % #area.slots + 1]
  return Runtime.call("encounter.species", function(e) return e end,
    { species = P.keyName(slot.species), speciesId = slot.species, level = slot.minLevel },
    { mapId = mapId, terrain = "land", rng = function() return 1000 + i end })
end
local function cast()
  local list = {}
  for i = 6, 10 do
    local s = fish.slots[i]
    list[#list + 1] = { species = P.keyName(s.species), level = s.minLevel,
      minLevel = s.minLevel, maxLevel = s.maxLevel, chance = 20 * (i - 5) }
  end
  -- the engine's next rolls the (possibly replaced) list and returns ONE encounter
  return Runtime.call("encounter.fishing", function(_, _, candidates)
    local c = candidates[1]
    local id = tonumber(c.species) or P.speciesFromName(c.species)
    return { species = P.keyName(id), speciesId = id, level = c.level }
  end, "SUPER_ROD", mapId, list)
end

local TARGET = (loader.content.pokemon:get("PIKACHU") or {}).index
T.check(type(TARGET) == "number", "Pikachu has a numeric slot")

for _, mode in ipairs({ "seeded", "complete", "map", "random" }) do
  set("spawn_mode", mode)
  api.invalidate()

  -- what the randomizer is handed: WoobleSpawns' species, as numbers
  outer.target = nil
  for k in pairs(outer.seen.species) do outer.seen.species[k] = nil end
  for k in pairs(outer.seen.fishing) do outer.seen.fishing[k] = nil end
  local moved, numeric = false, true
  for i = 1, 24 do
    local r = step(i)
    if type(r.species) ~= "number" or r.speciesId ~= r.species then numeric = false end
    local vanilla = area.slots[(i - 1) % #area.slots + 1].species
    if r.species ~= vanilla then moved = true end
  end
  T.check(numeric, mode .. ": the randomizer is handed numeric species and speciesId")
  T.check(moved, mode .. ": the randomizer is handed WoobleSpawns' species, not the cart's")
  T.eq(#outer.seen.species, 24, mode .. ": the randomizer runs on every step encounter")
  local f = cast()
  T.check(type(f) == "table" and type(f.speciesId) == "number" and f.level ~= nil,
          mode .. ": fishing hands the randomizer one rolled encounter")

  -- what the engine gets back: the randomizer's species, everything else kept
  outer.target = TARGET
  local kept = true
  for i = 1, 12 do
    local slot = area.slots[(i - 1) % #area.slots + 1]
    local r = step(i)
    if r.species ~= TARGET or r.speciesId ~= TARGET or r.level ~= slot.minLevel then kept = false end
  end
  T.check(kept, mode .. ": the randomizer's species wins, the level stays the game's")
  local g = cast()
  T.check(g and g.species == TARGET and g.level == f.level,
          mode .. ": the randomizer's species wins on the Super Rod, the level stays")
end

run.release()
T.finish("modern_spawns composes under a randomizer")
