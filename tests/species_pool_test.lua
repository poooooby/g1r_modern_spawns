-- Standalone: luajit mods/modern_spawns/tests/species_pool_test.lua (from the
-- gen1recomp root). How runtime species become candidates: profiles vs.
-- runtime estimates, evolution links from both sources, forms left out.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local Config = H.module("src/config.lua")
local SpeciesPool = H.module("src/species_pool.lua")
local Rng = H.module("src/rng.lua")
local MapContext = H.module("src/map_context.lua")

-- national_dex's evolutionsOf shape, for a species the runtime record
-- leaves without evolutions
local function evolutionOf(id)
  if id == "SENTRET" then
    return { chainId = 70, evolvesInto = { { id = "FURRET" } } }
  end
  if id == "FURRET" then
    return { chainId = 70, evolvesFrom = { id = "SENTRET",
             methods = { { level = 15, trigger = "level-up" } } } }
  end
  return nil
end

local species = H.species()
species[#species + 1] = H.mon("FURRET", 162, { "NORMAL" }, { 85, 76, 64, 90, 50 })
local world = H.world({ species = species, evolutionOf = evolutionOf })
local pool = SpeciesPool.build(world, H.profiles(), Config.generationOfDex)

T.check(pool.byId.PIDGEY ~= nil, "a runtime species is a candidate")
T.eq(pool.byId.PIDGEY_FORM, nil, "an alternate form is left out")
T.eq(pool.byId.PIDGEY.source, "profile", "a profiled species uses its profile")
T.eq(pool.byId.PIDGEY.lo, 3, "profile level window")
T.eq(pool.byId.LECHONK.source, "estimate", "an unprofiled species is estimated")
T.eq(pool.byId.LECHONK.gen, 9, "generation from the dex number")
T.eq(pool.byId.RAIKOU.special, "legendary", "legendary status comes from the profile data")
-- H.profiles gives RAIKOU a bogus "common, L2-10" wild profile, like the
-- Let's Go wandering birds in the real data: specials ignore it
T.eq(pool.byId.RAIKOU.source, "estimate", "a special species uses the runtime estimate")
T.check(pool.byId.RAIKOU.lo >= 30, "which puts a legendary late-game (lo " .. pool.byId.RAIKOU.lo .. ")")

-- the engine spells Psychic "PSYCHIC_TYPE"; rules see "PSYCHIC"
local psy = SpeciesPool.build(H.world({ species = {
  H.mon("ABRA", 63, { "PSYCHIC_TYPE" }, { 25, 20, 15, 90, 105 }) } }), nil, Config.generationOfDex)
T.check(psy.byId.ABRA.types.PSYCHIC, "PSYCHIC_TYPE is read as PSYCHIC")
T.eq(psy.byId.ABRA.typeList[1], "PSYCHIC_TYPE", "the engine id is kept for callers")
T.check(psy.byId.ABRA.habitats.ruins, "and gets Psychic's habitats")

-- evolution links: the ROM record's own list...
T.eq(pool.byId.PIDGEOTTO.evolveLevel, 18, "runtime evolutions give the evolve level")
T.eq(pool.byId.PIDGEOTTO.stage, 2, "and the stage")
T.eq(pool.byId.PIDGEY.family, pool.byId.PIDGEOTTO.family, "and one family")
T.check(pool.byId.PIDGEY.evolves, "a base form knows it evolves")
-- ...and national_dex's export for the species the runtime left empty
T.eq(pool.byId.FURRET.evolveLevel, 15, "national_dex evolutions fill the gap")
T.eq(pool.byId.SENTRET.family, pool.byId.FURRET.family, "national_dex links the family")
T.eq(pool.byId.FURRET.source, "estimate", "FURRET has no profile here")
T.eq(pool.byId.FURRET.lo, 15, "an estimated evolved form starts at its evolve level")

-- estimates by type
local wiglett = pool.byId.WIGLETT
T.check(wiglett.terrains.water and wiglett.terrains.fish, "a pure Water type swims")
T.check(not wiglett.terrains.grass, "and does not walk the grass")
T.check(wiglett.habitats.water, "and lives by the water")
local lechonk = pool.byId.LECHONK
T.check(lechonk.terrains.grass and not lechonk.terrains.water, "a Normal type walks")

-- cave dwellers from profiles count for cave floors
T.check(pool.byId.ZUBAT.terrains.cave, "cave species keep their cave terrain")

-- ------- map context

local cave = MapContext.describe("MT_MOON_1F", { tileset = "CAVERN" }, "cave")
T.check(cave.habitats.cave and cave.habitats.mountain, "Mt. Moon is a mountain cave")
T.eq(MapContext.landTerrain({ tileset = "CAVERN" }), "cave", "a cavern floor rolls as cave")
T.eq(MapContext.landTerrain({ tileset = "FOREST" }), "grass", "a forest rolls as grass")
local tower = MapContext.describe("POKEMON_TOWER_3F", { tileset = "CEMETERY" }, "grass")
T.check(tower.types.GHOST, "the tower favours ghosts")
local sea = MapContext.describe("ROUTE_19", { tileset = "OVERWORLD" }, "water")
T.check(sea.habitats.water and sea.habitats.coast, "a sea route is water and coast")

-- ------- rng

local r1, r2 = Rng.new(Rng.hash(1, "A")), Rng.new(Rng.hash(1, "A"))
local same = true
for _ = 1, 20 do if r1:next() ~= r2:next() then same = false end end
T.check(same, "the same hash seeds the same sequence")
T.neq(Rng.hash("ab", "c"), Rng.hash("a", "bc"), "hash separates its fields")
local r = Rng.new(7)
for _ = 1, 200 do
  local v = r:next()
  if v < 0 or v >= 1 then T.check(false, "next() stays in [0, 1)") break end
end
T.eq(Rng.new(3):weighted({ 0, 0, 5 }), 3, "weighted never picks a zero weight")
T.eq(Rng.new(3):weighted({ 0, 0 }), nil, "all-zero weights pick nothing")

T.finish("modern_spawns species_pool")
