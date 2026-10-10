-- The candidate pool: every species the running game can actually spawn,
-- described well enough to score against an encounter slot.
--
-- Runtime first, appended data second:
--   * which species exist, their dex number, types and base stats come from
--     the live pokemon registry (so a species national_dex did not register
--     can never be picked -- BattleState.newWild has no guard for that);
--   * evolution links come from the records' own `evolutions` (the ROM's
--     151) and, for the species national_dex registers with none, from its
--     evolutionsOf export;
--   * only what the runtime cannot answer -- observed wild level window,
--     habitats, terrains, rarity, legendary/mythical -- comes from the
--     generated spawn_profiles.lua, keyed by dex number;
--   * a species PokéAPI has no wild data for (all of Gen 9, some of Gen 8)
--     gets an ESTIMATED profile from its evolution stage, base stats and
--     types instead of being left out.
--
-- Alternate forms (records with `form`/`baseSpecies`) are left out, with one
-- exception: on Gen 3, the forms national_dex_gen3 registers that are wild
-- Pokemon in the real games. Which ones is this file's own list (REGIONAL,
-- LOOKS below); item and fusion forms (Origin, Therian, Crowned, ...), Floette
-- Eternal, Dusk Lycanroc and Ursaluna Bloodmoon are not on it, and neither are
-- megas or gigantamax.
--   * a REGIONAL form (Galarian Darumaka, Hisuian Zorua, ...) has its own typing
--     and habitat, so it is a candidate of its own, scored like any species on
--     the runtime estimate from its own types; it shares its base's family;
--   * a LOOK (Rotom's appliances, Oricorio's styles, Flabebe's colours, ...) is
--     not a candidate. The base species is chosen exactly as before, and the
--     generator then swaps it for one of its looks (or leaves it) with equal
--     odds -- `variants` on the base's candidate -- so a species with many looks
--     does not spawn more often than one with none.

local SpeciesPool = {}

local function set(list)
  local out = {}
  for _, id in ipairs(list) do out[id] = true end
  return out
end

local REGIONAL = set({
  "DARUMAKA_GALAR", "DARMANITAN_GALAR_STANDARD", "YAMASK_GALAR", "STUNFISK_GALAR",
  "ZORUA_HISUI", "ZOROARK_HISUI", "LILLIGANT_HISUI", "BRAVIARY_HISUI", "SLIGGOO_HISUI",
  "GOODRA_HISUI", "AVALUGG_HISUI",
})

local LOOKS = set({
  "WORMADAM_SANDY", "WORMADAM_TRASH",
  "ROTOM_HEAT", "ROTOM_WASH", "ROTOM_FROST", "ROTOM_FAN", "ROTOM_MOW",
  "ORICORIO_PAU", "ORICORIO_POM_POM", "ORICORIO_SENSU",
  "PUMPKABOO_SMALL", "PUMPKABOO_LARGE", "PUMPKABOO_SUPER",
  "GOURGEIST_SMALL", "GOURGEIST_LARGE", "GOURGEIST_SUPER",
  "LYCANROC_MIDNIGHT",
  "SHELLOS_EAST", "GASTRODON_EAST",
  "FLABEBE_YELLOW", "FLABEBE_ORANGE", "FLABEBE_BLUE", "FLABEBE_WHITE",
  "FLOETTE_YELLOW", "FLOETTE_ORANGE", "FLOETTE_BLUE", "FLOETTE_WHITE",
  "FLORGES_YELLOW", "FLORGES_ORANGE", "FLORGES_BLUE", "FLORGES_WHITE",
  "ALCREMIE_RUBY_CREAM", "ALCREMIE_MATCHA_CREAM", "ALCREMIE_MINT_CREAM",
  "ALCREMIE_LEMON_CREAM", "ALCREMIE_SALTED_CREAM", "ALCREMIE_RUBY_SWIRL",
  "ALCREMIE_CARAMEL_SWIRL", "ALCREMIE_RAINBOW_SWIRL",
  "BASCULIN_WHITE_STRIPED", "BASCULEGION_FEMALE",
  "SINISTEA_ANTIQUE", "POLTEAGEIST_ANTIQUE", "POLTCHAGEIST_ARTISAN", "SINISTCHA_MASTERPIECE",
})

-- "regional" / "look" for a form record this mod spawns, nil for any other
local function formKind(record)
  if REGIONAL[record.id] then return "regional" end
  if LOOKS[record.id] then return "look" end
  return nil
end

local STAT_KEYS = { "hp", "attack", "defense", "speed" }

local function bst(record)
  local stats = type(record.baseStats) == "table" and record.baseStats or {}
  local total = 0
  for _, key in ipairs(STAT_KEYS) do total = total + (tonumber(stats[key]) or 0) end
  -- Gen 2 records split Special; national_dex's Gen 1 records carry the
  -- split beside the collapsed Special; the ROM's 151 only have Special
  if tonumber(stats.specialAttack) and tonumber(stats.specialDefense) then
    total = total + stats.specialAttack + stats.specialDefense
  elseif tonumber(record.spAttack) and tonumber(record.spDefense) then
    total = total + record.spAttack + record.spDefense
  else
    total = total + 2 * (tonumber(stats.special) or 0)
  end
  return total
end

-- `set` uses plain type names for every rule in this mod ("PSYCHIC");
-- `list` keeps the engine's own ids for callers. The cart and national_dex
-- both spell Psychic "PSYCHIC_TYPE", which no plain-name rule would match.
local function typeSet(record)
  local set, list = {}, {}
  for _, t in ipairs(type(record.types) == "table" and record.types or {}) do
    if type(t) == "string" then
      local plain = t:gsub("_TYPE$", "")
      if not set[plain] then
        set[plain] = true
        list[#list + 1] = t
      end
    end
  end
  return set, list
end

local function toSet(list)
  local set = {}
  for _, v in ipairs(list or {}) do set[v] = true end
  return set
end

-- ----------------------------------------------------------- estimates

-- Habitat hints a type suggests, in the profiles' own vocabulary.
local TYPE_HABITATS = {
  GRASS = { "forest", "grassland" }, BUG = { "forest", "grassland" },
  WATER = { "water", "coast" }, ICE = { "snow", "cave" },
  ROCK = { "cave", "mountain" }, GROUND = { "cave", "desert", "mountain" },
  STEEL = { "cave", "urban" }, GHOST = { "ruins" }, DARK = { "urban", "forest" },
  ELECTRIC = { "urban", "grassland" }, FIRE = { "mountain", "desert" },
  NORMAL = { "route", "grassland" }, FLYING = { "route", "mountain" },
  POISON = { "cave", "urban" }, FIGHTING = { "mountain", "route" },
  PSYCHIC = { "ruins", "forest" }, FAIRY = { "forest", "grassland" },
  DRAGON = { "mountain", "water" },
}

-- Types that live on cave floors as well as in the grass.
local CAVE_TYPES = { ROCK = true, GROUND = true, STEEL = true, GHOST = true,
                     DARK = true, POISON = true, ICE = true, DRAGON = true }

local function estimateTerrains(types)
  local t = {}
  if types.WATER then
    t.water, t.fish = true, true
  end
  -- a pure Water type stays in the water; anything else also walks
  local landBound = false
  for name in pairs(types) do
    if name ~= "WATER" then landBound = true end
  end
  if landBound or not types.WATER then
    t.grass = true
    for name in pairs(types) do
      if CAVE_TYPES[name] then t.cave = true end
    end
  end
  return t
end

-- `types` is the plain-name set (typeSet's first result)
local function estimateHabitats(types)
  local set = {}
  for name in pairs(types) do
    for _, h in ipairs(TYPE_HABITATS[name] or {}) do set[h] = true end
  end
  if next(set) == nil then set.route = true end
  return set
end

local function estimateRarity(total)
  if total <= 330 then return "c" end
  if total <= 430 then return "u" end
  if total <= 500 then return "r" end
  return "v"
end

-- Level window from where the species sits in its evolution line.
local function estimateLevels(c)
  local lo, hi
  if c.evolveLevel then
    lo = c.evolveLevel
    hi = c.evolveLevel + 20
  elseif c.stage >= 2 then
    -- evolved by stone, trade or friendship: mid-game onward
    lo = 20 + (c.stage - 2) * 10
    hi = lo + 25
  elseif c.evolves then
    lo = math.max(2, math.floor(2 + (c.bst - 250) / 15))
    hi = lo + 15
  else
    lo = math.min(45, math.max(5, math.floor((c.bst - 300) / 6)))
    hi = lo + 20
  end
  hi = math.min(100, hi)
  return lo, hi, math.floor((lo + hi) / 2)
end

-- --------------------------------------------------------- evolution index

-- Union-find over species ids; the family id of a species is its root.
local function newFamilies()
  local parent = {}
  local function find(x)
    parent[x] = parent[x] or x
    while parent[x] ~= x do
      parent[x] = parent[parent[x]]
      x = parent[x]
    end
    return x
  end
  local function union(a, b)
    local ra, rb = find(a), find(b)
    if ra ~= rb then
      -- deterministic root: the lexically smaller id
      if ra < rb then parent[rb] = ra else parent[ra] = rb end
    end
  end
  return find, union
end

-- evolvesFrom[child] = { parent = id, level = n|nil }, plus evolvesInto set.
local function buildEvolutionIndex(records, byId, evolutionOf)
  local from, into = {}, {}
  local find, union = newFamilies()

  local function link(parentId, childId, level)
    if not (byId[parentId] and byId[childId]) then return end
    into[parentId] = true
    local existing = from[childId]
    if not existing then
      from[childId] = { parent = parentId, level = level }
    elseif level and (not existing.level or level < existing.level) then
      existing.level = level
    end
    union(parentId, childId)
  end

  -- runtime first: the records' own evolution lists (the cart's species).
  -- Gen 1 spells a step { method = "LEVEL", species }, Gen 2
  -- { method = "EVOLVE_LEVEL", into }, Gen 3 { method = "EVO_LEVEL", species }.
  for _, record in ipairs(records) do
    for _, evo in ipairs(type(record.evolutions) == "table" and record.evolutions or {}) do
      local target = type(evo) == "table" and (evo.species or evo.into) or nil
      if type(target) == "string" then
        local byLevel = evo.method == "LEVEL" or evo.method == "EVOLVE_LEVEL"
          or evo.method == "EVO_LEVEL"
        link(record.id, target, byLevel and tonumber(evo.level) or nil)
      end
    end
  end

  -- national_dex's evolution data for everything the runtime left empty
  if evolutionOf then
    for _, record in ipairs(records) do
      local ok, evo = pcall(evolutionOf, record.id)
      if ok and type(evo) == "table" then
        local parent = type(evo.evolvesFrom) == "table" and evo.evolvesFrom or nil
        if parent and type(parent.id) == "string" and not from[record.id] then
          local level
          for _, method in ipairs(type(parent.methods) == "table" and parent.methods or {}) do
            local l = tonumber(method.level)
            if l and (not level or l < level) then level = l end
          end
          link(parent.id, record.id, level)
        end
        for _, child in ipairs(type(evo.evolvesInto) == "table" and evo.evolvesInto or {}) do
          if type(child) == "table" and type(child.id) == "string" and byId[child.id] then
            into[record.id] = true
            union(record.id, child.id)
          end
        end
      end
    end
  end

  local function stage(id)
    local depth, seen = 1, {}
    local cur = from[id]
    while cur and not seen[cur.parent] do
      seen[cur.parent] = true
      depth = depth + 1
      cur = from[cur.parent]
    end
    return depth
  end

  return { from = from, into = into, family = find, stage = stage, union = union }
end

-- ------------------------------------------------------------------ build

-- world.species()      -> list of runtime pokemon records
-- world.evolutionOf    -> optional function(id) -> national_dex evolution record
-- profiles             -> the loaded spawn_profiles.lua table, or nil
-- generationOfDex      -> function(dex) -> 1..9
function SpeciesPool.build(world, profiles, generationOfDex)
  local records, byId, looks = {}, {}, {}
  -- only Gen 3 has the forms this file knows (national_dex on Gen 1/2 registers forms
  -- under some of the same ids; those stay out as before)
  local gen3 = world.generation == 3
  for _, record in ipairs(world.species() or {}) do
    if type(record) == "table" and type(record.id) == "string"
      and type(record.dex) == "number" and record.dex >= 1
      and not byId[record.id] then
      if record.form == nil and record.baseSpecies == nil then
        records[#records + 1] = record
        byId[record.id] = record
      elseif gen3 then
        local kind = formKind(record)
        if kind == "regional" then
          records[#records + 1] = record
          byId[record.id] = record
        elseif kind == "look" then
          looks[#looks + 1] = record
        end
      end
    end
  end
  table.sort(records, function(a, b)
    if a.dex ~= b.dex then return a.dex < b.dex end
    return a.id < b.id
  end)

  local evo = buildEvolutionIndex(records, byId, world.evolutionOf)
  -- a regional form belongs to its base species' family
  for _, record in ipairs(records) do
    if record.baseSpecies and byId[record.baseSpecies] then
      evo.union(record.id, record.baseSpecies)
    end
  end
  local profileSpecies = profiles and profiles.species or {}
  local profileGen = profiles and profiles.generation or {}
  local profileSpecial = profiles and profiles.special or {}

  local list, byIdOut = {}, {}
  for _, record in ipairs(records) do
    local types, typeList = typeSet(record)
    local parent = evo.from[record.id]
    local c = {
      id = record.id,
      dex = record.dex,
      gen = profileGen[record.dex] or generationOfDex(record.dex) or 9,
      types = types,
      typeList = typeList,
      bst = bst(record),
      family = evo.family(record.id),
      stage = evo.stage(record.id),
      evolveLevel = parent and parent.level or nil,
      evolves = evo.into[record.id] == true,
      special = profileSpecial[record.dex],
    }
    -- A first-stage species: nothing evolves INTO it, so it needs no minimum
    -- level to exist. The generator may count a low-BST one as plausible on an
    -- early slot even when its observed wild levels only start later (most
    -- modern species are met at higher levels by game design, not because
    -- they are strong); see SpawnConfig.plausible_basic.
    c.basic = c.stage == 1 and not c.special and not (record.form or record.baseSpecies)
    local p = profileSpecies[record.dex]
    -- a form shares its base's dex number, and so its profile: the base's wild
    -- data does not describe a Galarian Darumaka, the runtime estimate does
    if record.form or record.baseSpecies then
      p = nil
      c.form, c.baseSpecies = record.form, record.baseSpecies
    end
    -- A legendary's PokéAPI "wild" rows are one-offs (Let's Go's wandering
    -- birds read as common L3-56 route Pokemon), so special species always
    -- take the runtime estimate: high levels, habitats from their types.
    if c.special then p = nil end
    if type(p) == "table" then
      c.lo, c.hi, c.typ = p.lo, p.hi, p.typ
      c.rarity = p.r or "u"
      c.habitats = toSet(p.h)
      c.terrains = toSet(p.t)
      -- PokéAPI filed most cave walkers under "walk"; a cave-dwelling
      -- species' grass entries count for cave floors too
      if c.habitats.cave and c.terrains.grass then c.terrains.cave = true end
      c.source = "profile"
    else
      c.lo, c.hi, c.typ = estimateLevels(c)
      c.rarity = estimateRarity(c.bst)
      c.habitats = estimateHabitats(types)
      c.terrains = estimateTerrains(types)
      c.source = "estimate"
    end
    list[#list + 1] = c
    byIdOut[c.id] = c
  end
  -- A generation with almost no observed wild data (Gen 9: PokéAPI has no
  -- Scarlet/Violet encounters) has every species on an estimated profile, so
  -- the penalty that makes observed data win a close call would only tax that
  -- whole generation out of the draw. Flag its candidates so the generator
  -- skips the penalty there: there is nothing observed to prefer instead.
  local perGen = {}
  for _, c in ipairs(list) do
    local g = perGen[c.gen] or { total = 0, observed = 0 }
    perGen[c.gen] = g
    g.total = g.total + 1
    if c.source == "profile" then g.observed = g.observed + 1 end
  end
  for _, c in ipairs(list) do
    local g = perGen[c.gen]
    c.estimateOnlyGen = g.total > 0 and g.observed / g.total < 0.2 or false
  end
  -- looks hang off their base species' candidate, in a fixed order
  table.sort(looks, function(a, b) return a.id < b.id end)
  for _, record in ipairs(looks) do
    local base = byIdOut[record.baseSpecies]
    if base then
      base.variants = base.variants or {}
      base.variants[#base.variants + 1] = record.id
    end
  end
  return { list = list, byId = byIdOut }
end

-- exposed for tests
SpeciesPool._estimateLevels = estimateLevels
SpeciesPool._estimateTerrains = estimateTerrains

return SpeciesPool
