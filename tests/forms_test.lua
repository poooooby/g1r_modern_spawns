-- Standalone: luajit mods/modern_spawns/tests/forms_test.lua (from the gen1recomp
-- root). The alternate forms national_dex_gen3 registers: which of them spawn, and how.
-- Regional forms (Galarian Darumaka) are candidates of their own; looks (Flabebe's
-- colours, Rotom's appliances) are swapped in for their base species after it is chosen.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local Config = H.module("src/config.lua")
local Rng = H.module("src/rng.lua")
local MapContext = H.module("src/map_context.lua")
local SpeciesPool = H.module("src/species_pool.lua")
local Generator = H.module("src/generator.lua")

local function form(id, dex, base, name, types, stats, evolutions)
  return H.mon(id, dex, types, stats, evolutions, { form = name, baseSpecies = base })
end

local function species()
  local list = H.species()
  local function add(r) list[#list + 1] = r end
  add(H.mon("FLABEBE", 669, { "FAIRY" }, { 44, 38, 39, 42, 61 }))
  for _, c in ipairs({ "YELLOW", "ORANGE", "BLUE", "WHITE" }) do
    add(form("FLABEBE_" .. c, 669, "FLABEBE", c, { "FAIRY" }, { 44, 38, 39, 42, 61 }))
  end
  add(H.mon("DARUMAKA", 554, { "FIRE" }, { 70, 90, 45, 50, 45 },
            { { method = "EVO_LEVEL", level = 35, species = "DARMANITAN" } }))
  add(H.mon("DARMANITAN", 555, { "FIRE" }, { 105, 140, 55, 95, 55 }))
  add(form("DARUMAKA_GALAR", 554, "DARUMAKA", "GALAR", { "ICE" }, { 70, 90, 45, 50, 45 },
           { { method = "EVO_ITEM", species = "DARMANITAN_GALAR_STANDARD" } }))
  add(form("DARMANITAN_GALAR_STANDARD", 555, "DARMANITAN", "GALAR_STANDARD", { "ICE" }, { 105, 140, 55, 95, 55 }))
  add(H.mon("ROTOM", 479, { "ELECTRIC", "GHOST" }, { 50, 50, 77, 91, 95 }))
  add(form("ROTOM_HEAT", 479, "ROTOM", "HEAT", { "ELECTRIC", "FIRE" }, { 50, 65, 107, 86, 105 }))
  add(H.mon("GIRATINA", 487, { "GHOST", "DRAGON" }, { 150, 100, 120, 90, 120 }))
  add(form("GIRATINA_ORIGIN", 487, "GIRATINA", "ORIGIN", { "GHOST", "DRAGON" }, { 150, 120, 100, 90, 120 }))
  add(H.mon("FLOETTE", 670, { "FAIRY" }, { 54, 45, 47, 52, 75 }))
  add(form("FLOETTE_ETERNAL", 670, "FLOETTE", "ETERNAL", { "FAIRY" }, { 74, 65, 67, 92, 125 }))
  add(H.mon("LYCANROC", 745, { "ROCK" }, { 75, 115, 65, 112, 80 }))
  add(form("LYCANROC_MIDNIGHT", 745, "LYCANROC", "MIDNIGHT", { "ROCK" }, { 85, 115, 75, 82, 82 }))
  add(form("LYCANROC_DUSK", 745, "LYCANROC", "DUSK", { "ROCK" }, { 75, 117, 65, 110, 76 }))
  return list
end

local function worldOf(generation)
  local world = H.world({ species = species() })
  world.generation = generation
  return world
end

-- ------- the pool

local pool = SpeciesPool.build(worldOf(3), H.profiles(), Config.generationOfDex)
T.check(pool.byId.DARUMAKA_GALAR ~= nil, "a Galarian Darumaka is a candidate of its own")
T.eq(pool.byId.DARUMAKA_GALAR.source, "estimate", "scored on the runtime estimate, not Darumaka's profile")
T.check(pool.byId.DARUMAKA_GALAR.types.ICE and not pool.byId.DARUMAKA_GALAR.types.FIRE, "from its own typing")
T.check(pool.byId.DARUMAKA_GALAR.habitats.snow, "and its own habitats")
T.eq(pool.byId.DARUMAKA_GALAR.family, pool.byId.DARUMAKA.family, "it shares its base species' family")
T.eq(pool.byId.DARMANITAN_GALAR_STANDARD.stage, 2, "and keeps its place in its own evolution line")
T.check(pool.byId.DARMANITAN_GALAR_STANDARD ~= nil, "regional evolutions are candidates too")

for _, id in ipairs({ "FLABEBE_YELLOW", "ROTOM_HEAT", "LYCANROC_MIDNIGHT" }) do
  T.eq(pool.byId[id], nil, id .. " is a look, not a candidate")
end
T.eq(table.concat(pool.byId.FLABEBE.variants, ","),
     "FLABEBE_BLUE,FLABEBE_ORANGE,FLABEBE_WHITE,FLABEBE_YELLOW", "Flabebe's colours hang off it, in a fixed order")
T.eq(table.concat(pool.byId.ROTOM.variants, ","), "ROTOM_HEAT", "Rotom's appliance")
T.eq(pool.byId.PIDGEY.variants, nil, "a species with no looks has none")
for _, id in ipairs({ "GIRATINA_ORIGIN", "FLOETTE_ETERNAL", "LYCANROC_DUSK" }) do
  T.eq(pool.byId[id], nil, id .. " is not a wild Pokemon: left out")
end
T.eq(pool.byId.GIRATINA.variants, nil, "and not offered as a look either")
T.eq(pool.byId.FLOETTE.variants, nil, "Floette Eternal is not Floette's look")
T.eq(#pool.byId.LYCANROC.variants, 1, "Lycanroc has Midnight only")

-- Gen 1 and Gen 2 keep leaving every form out, whatever its id
local old = SpeciesPool.build(worldOf(1), H.profiles(), Config.generationOfDex)
T.eq(old.byId.DARUMAKA_GALAR, nil, "no regional form outside Gen 3")
T.eq(old.byId.FLABEBE.variants, nil, "and no looks")
local gen2 = SpeciesPool.build(worldOf(2), H.profiles(), Config.generationOfDex)
T.eq(gen2.byId.DARUMAKA_GALAR, nil, "nor on Gen 2")

-- ------- the generator swaps a look in for its species

local function run(seed)
  local world = worldOf(3)
  local p = SpeciesPool.build(world, H.profiles(), Config.generationOfDex)
  return Generator.buildAll({
    world = world, pool = p, seed = seed, maxGen = 9, config = Config.SpawnConfig,
    dataVersion = 1, MapContext = MapContext, Rng = Rng,
  })
end

local seen, flabebe, others = {}, 0, {}
for seed = 1, 600 do
  local tables = run(seed)
  for _, map in pairs(tables) do
    for _, def in pairs(map) do
      for _, slot in ipairs(def.slots or {}) do
        seen[slot.species] = (seen[slot.species] or 0) + 1
      end
    end
  end
end
local looks = { "FLABEBE", "FLABEBE_YELLOW", "FLABEBE_ORANGE", "FLABEBE_BLUE", "FLABEBE_WHITE" }
local min, max = math.huge, 0
for _, id in ipairs(looks) do
  T.check((seen[id] or 0) > 0, id .. " spawns somewhere across 600 seeds (" .. tostring(seen[id]) .. ")")
  min, max = math.min(min, seen[id] or 0), math.max(max, seen[id] or 0)
end
T.check(max <= min * 3, "the five looks are about equally likely (" .. min .. " to " .. max .. ")")
T.eq(seen.FLABEBE_FAKE, nil, "no id that was never registered")
T.eq(seen.GIRATINA_ORIGIN, nil, "an item form never spawns")
T.eq(seen.FLOETTE_ETERNAL, nil, "nor Floette Eternal")
T.eq(seen.LYCANROC_DUSK, nil, "nor Dusk Lycanroc")

T.finish("modern_spawns forms")
