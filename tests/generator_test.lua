-- Standalone: luajit mods/modern_spawns/tests/generator_test.lua (from the
-- gen1recomp root). Pure generator behaviour against a hand-built world:
-- determinism, structure preservation, special-species protection, the
-- generation cap, graceful degradation and diversity.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local Config = H.module("src/config.lua")
local Rng = H.module("src/rng.lua")
local MapContext = H.module("src/map_context.lua")
local SpeciesPool = H.module("src/species_pool.lua")
local Generator = H.module("src/generator.lua")

local function build(opts)
  opts = opts or {}
  local world = opts.world or H.world()
  local pool = SpeciesPool.build(world, opts.profiles or H.profiles(),
                                 Config.generationOfDex)
  return Generator.buildAll({
    world = world, pool = pool, seed = opts.seed or 1234,
    maxGen = opts.maxGen or 9, config = opts.config or Config.SpawnConfig,
    dataVersion = 1, MapContext = MapContext, Rng = Rng,
  }), pool
end

local encounters = H.encounters()

-- ------- determinism

local a = build({ seed = 42 })
local b = build({ seed = 42 })
T.eq(H.serialize(a), H.serialize(b), "the same seed produces identical tables")

local differs = false
for seed = 43, 60 do
  if H.serialize(build({ seed = seed })) ~= H.serialize(a) then differs = true break end
end
T.check(differs, "different seeds can produce different tables")

-- Pinned: a save's SEEDED rosters must survive upgrades. If a deliberate
-- balance change moves these, update them and say so in CHANGELOG.md; an
-- accidental change (0.2.0 once added a field to the RNG hash) reshuffles
-- every existing playthrough.
-- Re-pinned at 0.11.0: the shortlist became a softmax within a score window and
-- plausible basics were admitted at low levels (SpawnConfig.selection /
-- plausible_basic), which moved ROUTE_B's middle role. ROUTE_A did not move.
local function speciesList(tbl)
  local out = {}
  for i, slot in ipairs(tbl.slots) do out[i] = slot.species end
  return table.concat(out, ",")
end
T.eq(speciesList(a.ROUTE_A.grass),
     "HOOTHOOT,STARLY,HOOTHOOT,STARLY,HOOTHOOT,STARLY,HOOTHOOT,STARLY,HOOTHOOT,STARLY",
     "seed 42 ROUTE_A is unchanged")
T.eq(speciesList(a.ROUTE_B.grass), "PIDGEY,RATTATA,MARILL", "seed 42 ROUTE_B is unchanged")

-- ------- structure preservation

for mapId, vanilla in pairs(encounters) do
  for _, kind in ipairs({ "grass", "water" }) do
    local v, g = vanilla[kind], a[mapId] and a[mapId][kind]
    if v then
      T.check(g ~= nil, mapId .. " " .. kind .. " was generated")
      T.eq(g.rate, v.rate, mapId .. " " .. kind .. " keeps its rate")
      T.eq(#g.slots, #v.slots, mapId .. " " .. kind .. " keeps its slot count")
      local levelsSame = true
      for i, slot in ipairs(v.slots) do
        if g.slots[i].level ~= slot.level then levelsSame = false end
      end
      T.check(levelsSame, mapId .. " " .. kind .. " keeps every slot level")
      T.eq(H.serialize(g.buckets), H.serialize(v.buckets),
           mapId .. " " .. kind .. " keeps its odds ladder")
      T.check(g ~= v and g.slots ~= v.slots, mapId .. " " .. kind .. " is a copy")
    end
  end
end
T.eq(#a.TOWN.superRod.slots, 2, "the Super Rod group keeps its size")
T.eq(a.TOWN.superRod.slots[1].level, 15, "and its levels")
T.eq(encounters.ROUTE_A.grass.slots[1].species, "PIDGEY",
     "the source tables are never modified")

-- roles: slots that shared a species still share one
local r = a.ROUTE_A.grass.slots
T.eq(r[1].species, r[3].species, "a role's slots stay one species (slot 1 = 3)")
T.eq(r[2].species, r[4].species, "a role's slots stay one species (slot 2 = 4)")
T.neq(r[1].species, r[2].species, "two roles get two different species")

-- ------- terrain sanity

local function speciesIn(tbl)
  local set = {}
  for _, slot in ipairs(tbl.slots or tbl) do set[slot.species] = true end
  return set
end
local _, pool = build()
for id in pairs(speciesIn(a.SEA_ROUTE.water)) do
  local c = pool.byId[id]
  T.check(c.terrains.water or c.terrains.fish or c.types.WATER,
          id .. " in a water table is a water species")
end
for id in pairs(speciesIn(a.TOWN.superRod)) do
  local c = pool.byId[id]
  T.check(c.terrains.water or c.terrains.fish or c.types.WATER,
          id .. " on the Super Rod is a water species")
end

-- ------- special species and the generation cap

for seed = 1, 25 do
  local tables = build({ seed = seed })
  for mapId, entry in pairs(tables) do
    for _, kind in ipairs({ "grass", "water", "superRod" }) do
      if entry[kind] then
        T.check(not speciesIn(entry[kind]).RAIKOU,
                "legendary never placed (seed " .. seed .. ", " .. mapId .. ")")
      end
    end
  end
end

local capped = build({ maxGen = 2 })
for mapId, entry in pairs(capped) do
  for _, kind in ipairs({ "grass", "water", "superRod" }) do
    for id in pairs(entry[kind] and speciesIn(entry[kind]) or {}) do
      T.check(pool.byId[id].gen <= 2, id .. " respects GEN 1-2 on " .. mapId)
    end
  end
end

local gen1 = build({ maxGen = 1 })
for id in pairs(speciesIn(gen1.ROUTE_A.grass)) do
  T.check(pool.byId[id].dex <= 151, id .. " respects a GEN 1 cap")
end

-- ------- graceful degradation

-- only one land species exists: the table is still complete
local thin = H.world({ species = { H.mon("RATTATA", 19, { "NORMAL" }, { 30, 56, 35, 72, 25 }),
                                   H.mon("PIDGEY", 16, { "NORMAL", "FLYING" }, { 40, 45, 40, 56, 35 }) },
                       order = { "ROUTE_A" } })
local thinTables = build({ world = thin })
for i, slot in ipairs(thinTables.ROUTE_A.grass.slots) do
  T.check(slot.species == "RATTATA" or slot.species == "PIDGEY",
          "a constrained pool still fills slot " .. i)
end

-- nothing but a legendary: every role keeps its vanilla species
local onlySpecial = H.world({
  species = { H.mon("RAIKOU", 243, { "ELECTRIC" }, { 90, 85, 75, 115, 115 }) },
  order = { "ROUTE_A" } })
local kept = build({ world = onlySpecial })
T.eq(kept.ROUTE_A.grass.slots[1].species, "PIDGEY",
     "with no eligible species the vanilla species is kept, never the legendary")
T.eq(kept.ROUTE_A.explain.grass[1].reasons[1], "kept_vanilla",
     "and the explain record says so")

-- ------- diversity across neighbouring maps

local same = {}
for _, id in ipairs({ "R1", "R2", "R3" }) do same[id] = encounters.ROUTE_A end
local diverse = build({ world = H.world({ encounters = same, order = { "R1", "R2", "R3" },
  maps = { R1 = { tileset = "OVERWORLD" }, R2 = { tileset = "OVERWORLD" },
           R3 = { tileset = "OVERWORLD" } }, superRod = {} }) })
local s1, s2 = speciesIn(diverse.R1.grass), speciesIn(diverse.R2.grass)
local shared = 0
for id in pairs(s1) do if s2[id] then shared = shared + 1 end end
T.eq(shared, 0, "the next map avoids the previous map's species")

-- floors of one area are exempt from the recent-map penalty
T.eq(Generator._areaOf("MT_MOON_B2F"), "MT_MOON", "B2F floors share an area")
T.eq(Generator._areaOf("ROCK_TUNNEL_1F"), "ROCK_TUNNEL", "1F floors share an area")
T.eq(Generator._areaOf("ROUTE_1"), "ROUTE_1", "a route is its own area")

-- ------- legendary homes

do
  local species = H.species()
  species[#species + 1] = H.mon("ARTICUNO", 144, { "ICE", "FLYING" }, { 90, 85, 100, 85, 125 })
  species[#species + 1] = H.mon("MEW", 151, { "PSYCHIC_TYPE" }, { 100, 100, 100, 100, 100 })
  local profiles = H.profiles()
  profiles.special[144], profiles.special[151] = "legendary", "mythical"
  local encs = H.encounters()
  encs.SEAFOAM_ISLANDS_B1F = { grass = { rate = 10, slots = H.slots({
    { 36, "ZUBAT" }, { 38, "GEODUDE" }, { 40, "ZUBAT" }, { 42, "GEODUDE" } }) } }
  encs.CERULEAN_CAVE_1F = { grass = { rate = 10, slots = H.slots({
    { 46, "ZUBAT" }, { 50, "GEODUDE" }, { 52, "ZUBAT" }, { 55, "GEODUDE" } }) } }
  local world = H.world({ species = species, encounters = encs,
    order = { "ROUTE_A", "ROUTE_B", "CAVE_1F", "SEA_ROUTE", "SEAFOAM_ISLANDS_B1F",
              "CERULEAN_CAVE_1F" },
    maps = { ROUTE_A = { tileset = "OVERWORLD" }, ROUTE_B = { tileset = "OVERWORLD" },
             CAVE_1F = { tileset = "CAVERN" }, SEA_ROUTE = { tileset = "OVERWORLD" },
             SEAFOAM_ISLANDS_B1F = { tileset = "CAVERN" },
             CERULEAN_CAVE_1F = { tileset = "CAVERN" } } })
  local lpool = SpeciesPool.build(world, profiles, Config.generationOfDex)
  local function homesAt(maxGen)
    return Generator.legendaryHomes({ world = world, pool = lpool, maxGen = maxGen,
      config = Config.SpawnConfig, MapContext = MapContext, Rng = Rng })
  end
  local homes = homesAt(9)
  local function hosts(mapId, id)
    for _, list in pairs(homes[mapId] or {}) do
      for _, h in ipairs(list) do if h.id == id then return h end end
    end
    return nil
  end
  local articuno = hosts("SEAFOAM_ISLANDS_B1F", "ARTICUNO")
  T.check(articuno ~= nil, "Articuno lives in the icy cave")
  T.eq(articuno and articuno.category, "legendary", "tagged legendary")
  local mew = hosts("CERULEAN_CAVE_1F", "MEW")
  T.check(mew ~= nil, "Mew lives in the psychic cave (PSYCHIC_TYPE is read as PSYCHIC)")
  T.eq(mew and mew.category, "mythical", "tagged mythical")
  for _, low in ipairs({ "ROUTE_A", "ROUTE_B", "CAVE_1F" }) do
    T.eq(homes[low], nil, low .. " is too low-level to host a legendary")
  end
  local count = {}
  for mapId, byKind in pairs(homes) do
    for kind, list in pairs(byKind) do
      T.check(#list <= Config.SpawnConfig.legendary.max_per_map,
              mapId .. " " .. kind .. " hosts at most max_per_map species")
      for _, h in ipairs(list) do count[h.id] = (count[h.id] or 0) + 1 end
    end
  end
  for id, n in pairs(count) do
    T.check(n <= Config.SpawnConfig.legendary.homes_per_species, id .. " has at most two homes")
  end
  local gen1 = homesAt(1)
  for _, byKind in pairs(gen1) do
    for _, list in pairs(byKind) do
      for _, h in ipairs(list) do
        T.check(lpool.byId[h.id].gen <= 1, h.id .. " respects the generation cap")
      end
    end
  end
  -- the tables themselves still never contain one
  local tables = Generator.buildAll({ world = world, pool = lpool, seed = 5, maxGen = 9,
    config = Config.SpawnConfig, dataVersion = 1, MapContext = MapContext, Rng = Rng })
  for mapId, entry in pairs(tables) do
    for _, kind in ipairs({ "grass", "water", "superRod" }) do
      for id in pairs(entry[kind] and speciesIn(entry[kind]) or {}) do
        T.check(not lpool.byId[id].special, id .. " in a table on " .. mapId .. " is not special")
      end
    end
  end
end

-- ------- explain records

local explain = a.ROUTE_A.explain.grass
T.eq(#explain, 10, "one explain record per slot")
T.check(type(explain[1].score) == "number", "records carry the score")
T.check(#explain[1].reasons > 0, "and at least one reason")
T.eq(explain[1].replaced, "PIDGEY", "and the vanilla species it replaced")

T.finish("modern_spawns generator")
