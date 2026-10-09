-- Full redistribution of the runtime's wild tables.
--
-- Every map keeps its original encounter STRUCTURE exactly -- rate, slot
-- count, per-slot level, odds ladder (`buckets`), Super Rod group size --
-- and only the species in each slot is re-picked from the allowed pool.
-- Slots that held the same species form one ROLE, so a table's shape (one
-- common species across four slots, a rare one in the last) survives the
-- redistribution rather than dissolving into ten unrelated picks.
--
-- Deterministic: the same seed, generation cap and data version produce the
-- same tables, and every map is generated in the game's own map order in one
-- pass, so the rolling history (recent species/families) never depends on
-- the order the player happens to visit maps in.
--
-- Legendary and mythical species are a hard eligibility rule -- never a
-- score, never relaxed when a pool is thin (contract section 9).

local Generator = {}

local RARITY_RANK = { c = 1, u = 2, r = 3, v = 4 }

-- Floors of one place ("MT_MOON_1F", "MT_MOON_B2F") are one area: they do
-- not penalize each other's species as "recently seen", and reusing a
-- species across them reads as one cave rather than as repetition.
local function areaOf(mapId)
  return (tostring(mapId):gsub("_B?%d+F$", ""))
end

local function copySlot(slot)
  -- maxLevel: Gen 3 slots roll a level range (level = its minimum)
  return { level = slot.level, species = slot.species, maxLevel = slot.maxLevel }
end

local function copyList(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

local function rarityForShare(share)
  if share >= 0.20 then return "c" end
  if share >= 0.10 then return "u" end
  if share >= 0.04 then return "r" end
  return "v"
end

-- Group slots by their vanilla species, heaviest role first.
-- `times[i]` (Gen 2 grass only) is the time of day slot i belongs to;
-- a role then knows whether it is a night-only or a day-only role.
local function buildRoles(slots, weights, times)
  local roles, bySpecies, total = {}, {}, 0
  for i, slot in ipairs(slots) do
    if type(slot) == "table" and type(slot.species) == "string" then
      local role = bySpecies[slot.species]
      if not role then
        role = { species = slot.species, slots = {}, first = i, weight = 0,
                 minLevel = slot.level, maxLevel = slot.level }
        bySpecies[slot.species] = role
        roles[#roles + 1] = role
      end
      if times and times[i] then
        role.times = role.times or {}
        role.times[times[i]] = true
      end
      role.slots[#role.slots + 1] = i
      role.weight = role.weight + (weights[i] or 0)
      role.minLevel = math.min(role.minLevel, slot.level)
      role.maxLevel = math.max(role.maxLevel, slot.maxLevel or slot.level)
      total = total + (weights[i] or 0)
    end
  end
  for _, role in ipairs(roles) do
    role.rarity = rarityForShare(total > 0 and role.weight / total or 0)
    if role.times then
      role.nightOnly = role.times.NITE and not (role.times.MORN or role.times.DAY)
      role.dayOnly = not role.times.NITE
    end
  end
  table.sort(roles, function(a, b)
    if a.weight ~= b.weight then return a.weight > b.weight end
    return a.first < b.first
  end)
  return roles
end

-- -------------------------------------------------------------- filtering

local function terrainOk(c, terrain, relaxed)
  local t = c.terrains
  if terrain == "water" or terrain == "fish" then
    return t.water or t.fish or c.types.WATER or false
  end
  if terrain == "cave" then
    return t.cave or t.grass or relaxed or false
  end
  -- grass: a species only ever found on/in water does not walk the grass
  return t.grass or t.cave or (relaxed and not (t.water or t.fish)) or false
end

local function levelDistance(c, role)
  if c.lo <= role.maxLevel and c.hi >= role.minLevel then return 0 end
  if c.lo > role.maxLevel then return c.lo - role.maxLevel end
  return role.minLevel - c.hi
end

local function underleveled(c, role, tolerance)
  return c.evolveLevel ~= nil and role.maxLevel < c.evolveLevel - tolerance
end

-- tier 1: terrain + plausible level; tier 2: terrain; tier 3: anything
-- non-special under the cap. Special species are never eligible at any tier.
local function eligible(c, env, role, tier)
  if c.special then return false end
  if c.gen > env.maxGen then return false end
  if tier >= 3 then return true end
  if not terrainOk(c, env.terrain, tier >= 2) then return false end
  if tier >= 2 then return true end
  return levelDistance(c, role) <= env.config.strict_level_distance
    and not underleveled(c, role, env.config.evolve_tolerance)
end

-- ---------------------------------------------------------------- scoring

-- `labelled` builds the reason/penalty lists; it is only asked for the
-- winning candidate, because scoring ~1000 candidates per role with a label
-- list each would be most of the generator's cost.
local function score(c, role, env, labelled)
  local W = env.config.scoring
  local total = 0
  local reasons, penalties
  if labelled then reasons, penalties = {}, {} end
  local function add(value, label)
    if value == 0 then return end
    total = total + value
    if not labelled then return end
    if value > 0 then reasons[#reasons + 1] = label
    else penalties[#penalties + 1] = label end
  end

  local dist = levelDistance(c, role)
  if dist == 0 then
    add(W.level_overlap, "level_overlap")
  else
    add(dist * W.level_distance, "level_distance")
  end
  local mid = (role.minLevel + role.maxLevel) / 2
  add(math.abs(c.typ - mid) * W.typical_distance, "typical_level_gap")
  if underleveled(c, role, env.config.evolve_tolerance) then
    add(W.underleveled, "below_evolve_level")
  elseif c.evolves and role.minLevel > c.hi + 15 then
    add(W.overleveled, "overleveled_base_form")
  end

  if c.terrains[env.terrain] then
    add(W.terrain_match, "terrain_match")
  elseif env.terrain == "cave" and c.terrains.grass then
    add(W.terrain_partial, "terrain_partial")
  end

  local shared = 0
  for h in pairs(c.habitats) do
    if env.habitats[h] then shared = shared + 1 end
  end
  if shared > 0 then
    add(W.habitat_match + (shared - 1) * W.habitat_extra, "habitat_match")
  end

  local vanilla = env.pool.byId[role.species]
  if vanilla then
    local same = 0
    for t in pairs(c.types) do
      if vanilla.types[t] then same = same + 1 end
    end
    if same > 0 then add(math.min(same, 2) * W.type_match, "type_match") end
  end
  for t in pairs(c.types) do
    if env.mapTypes[t] then
      add(W.map_type, "map_type")
      break
    end
  end

  -- Gen 2 day/night: the game's own tables say which species only come out
  -- at night (or never do); keep them on the matching side of the clock
  if (role.nightOnly or role.dayOnly) and env.timeOf then
    local habit = env.timeOf(c.id)
    if (role.nightOnly and habit == "day") or (role.dayOnly and habit == "night") then
      add(W.time_mismatch, "wrong_time_of_day")
    elseif role.nightOnly and (habit == "night" or c.types.GHOST or c.types.DARK) then
      add(W.time_match, "time_of_day_match")
    end
  end

  if c.source == "estimate" then add(W.estimated_profile, "estimated_profile") end

  local gap = math.abs((RARITY_RANK[c.rarity] or 2) - (RARITY_RANK[role.rarity] or 2))
  if gap == 0 then add(W.rarity_match, "rarity_match")
  elseif gap >= 2 then add(W.rarity_mismatch, "rarity_mismatch") end

  local state, history = env.state, env.history
  if state.species[c.id] then
    add(W.same_species_current, "same_species_current")
  elseif state.families[c.family] then
    add(W.same_family_current, "same_family_current")
  end
  if history.previous[c.id] then
    add(W.same_species_previous, "same_species_previous")
  elseif history.recent[c.id] then
    add(W.same_species_recent, "same_species_recent")
  elseif history.recentFamilies[c.family] then
    add(W.same_family_recent, "same_family_recent")
  else
    add(W.new_species, "not_seen_recently")
  end
  if env.areaSpecies[c.id] and not state.species[c.id] then
    add(W.same_area, "same_area")
  end
  local genCount = state.gens[c.gen] or 0
  if genCount == 0 then
    add(W.new_generation, "new_generation")
  elseif genCount >= 2 then
    add((genCount - 1) * W.generation_overrepresented, "generation_overrepresented")
  end

  return total, reasons, penalties
end

-- -------------------------------------------------------------- selection

local function choose(role, env, rng)
  for tier = 1, 3 do
    local scored = {}
    for _, c in ipairs(env.pool.list) do
      if eligible(c, env, role, tier) then
        scored[#scored + 1] = { c = c, score = score(c, role, env, false) }
      end
    end
    -- a thin strict tier is widened before it is drawn from (contract 17)
    if #scored > 0 and (tier == 3 or #scored >= env.config.top_candidates / 2) then
      table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.c.id < b.c.id
      end)
      local selection = env.selection or {}
      local top = math.min(#scored, selection.top or env.config.top_candidates)
      local power = selection.power or 2
      local floor = scored[top].score
      local weights = {}
      for i = 1, top do
        weights[i] = (scored[i].score - floor + 1) ^ power
      end
      local pick = scored[rng:weighted(weights) or 1]
      pick.tier = tier
      local _, reasons, penalties = score(pick.c, role, env, true)
      pick.reasons, pick.penalties = reasons, penalties
      return pick
    end
  end
  return nil
end

-- `weights[i]` is slot i's odds as the running game rolls them (the
-- adapter's business: Gen 1 ladders, Gen 2 percents, fish chances).
local function redistribute(def, env, rng, weights)
  local out = { rate = def.rate, slots = {} }
  if def.buckets then out.buckets = copyList(def.buckets) end
  for i, slot in ipairs(def.slots or {}) do out.slots[i] = copySlot(slot) end
  if not def.slots or #def.slots == 0 or def.rate == 0 then
    return out, {}
  end

  local explain = {}
  for _, role in ipairs(buildRoles(def.slots, weights, env.slotTimes)) do
    local pick = choose(role, env, rng)
    local species = pick and pick.c.id or role.species
    -- a species with looks (Rotom's appliances, Flabebe's colours, ...) is shown as itself
    -- or one of them, equally likely; a species without any draws nothing
    local shown = species
    if pick and pick.c.variants then
      local options = { species }
      for _, id in ipairs(pick.c.variants) do options[#options + 1] = id end
      shown = options[rng:int(1, #options)]
    end
    for _, i in ipairs(role.slots) do
      out.slots[i].species = shown
      explain[#explain + 1] = {
        slot = i,
        level = out.slots[i].level,
        species = shown,
        variantOf = shown ~= species and species or nil,
        replaced = role.species,
        score = pick and pick.score or nil,
        tier = pick and pick.tier or nil,
        source = pick and pick.c.source or "vanilla",
        reasons = pick and copyList(pick.reasons) or { "kept_vanilla" },
        penalties = pick and copyList(pick.penalties) or {},
      }
    end
    local c = pick and pick.c or env.pool.byId[species]
    env.state.species[species] = true
    if c then
      env.state.families[c.family] = true
      env.state.gens[c.gen] = (env.state.gens[c.gen] or 0) + 1
    end
  end
  table.sort(explain, function(a, b) return a.slot < b.slot end)
  return out, explain
end

-- ------------------------------------------------------------------ build

-- The rolling memory one generation pass carries from map to map: which
-- species/families recent maps used, and what each area already has.
-- SEEDED builds every map in one pass with a fresh memory; EVERY MAP and
-- RANDOM keep one memory for the session, fed in the order maps are visited.
local HISTORY_KEEP = 16

function Generator.newMemory()
  return { history = { maps = {} }, areaSpecies = {} }
end

local function historyView(history, area, window)
  local view = { previous = {}, recent = {}, recentFamilies = {} }
  local counted = 0
  for i = #history.maps, 1, -1 do
    local entry = history.maps[i]
    if entry.area ~= area then
      counted = counted + 1
      if counted > window then break end
      for id in pairs(entry.species) do
        if counted == 1 then view.previous[id] = true end
        view.recent[id] = true
      end
      for fam in pairs(entry.families) do view.recentFamilies[fam] = true end
    end
  end
  return view
end

-- ctx fields:
--   world     adapter (src/adapters/gen1.lua / gen2.lua): mapOrder(),
--             mapInfo(id), tables(id) -> { {kind, terrain, def, weights} }
--   pool      SpeciesPool.build(...) result
--   seed      per-save seed (any string or number; hashed)
--   maxGen    1..9
--   config    Config.SpawnConfig
--   dataVersion  profile data version (part of the determinism key)
--   MapContext, Rng  modules
--
-- One map's generated tables, keyed by the adapter's entry kinds, each
-- { rate, slots, buckets? } in the generator's flat shape (the adapter's
-- assemble() turns them back into the game's own), plus explain[kind]; nil
-- for a map with no wild data. `nonce` distinguishes repeated generations
-- of the same map under one seed (EVERY MAP visits, RANDOM encounters);
-- `remember` false leaves `memory` untouched (a throwaway RANDOM draw).
function Generator.buildMap(ctx, mapId, memory, nonce, remember)
  local world, config = ctx.world, ctx.config
  local entries = world.tables(mapId)
  if not entries or #entries == 0 then return nil end

  local info = world.mapInfo(mapId)
  local area = areaOf(mapId)
  local history, areaSpecies = memory.history, memory.areaSpecies
  areaSpecies[area] = areaSpecies[area] or {}
  local state = { species = {}, families = {}, gens = {} }
  local result = { explain = {} }

  for _, entry in ipairs(entries) do
    local kind, terrain = entry.kind, entry.terrain
    local place = ctx.MapContext.describe(mapId, info, terrain)
    local env = {
      terrain = terrain, habitats = place.habitats, mapTypes = place.types,
      maxGen = ctx.maxGen, config = config, pool = ctx.pool, state = state,
      history = historyView(history, area, config.history_window_maps),
      areaSpecies = areaSpecies[area],
      selection = ctx.selection,
      slotTimes = entry.times, timeOf = world.timeOf,
    }
    -- SEEDED passes no nonce and must hash exactly as 0.1.0 did, so a save's
    -- rosters survive upgrades; an extra field would reshuffle every draw
    local key = nonce == nil
      and ctx.Rng.hash(ctx.seed, mapId, kind, ctx.maxGen, ctx.dataVersion)
      or ctx.Rng.hash(ctx.seed, mapId, kind, ctx.maxGen, ctx.dataVersion, nonce)
    local rng = ctx.Rng.new(key)
    local table_, explain = redistribute(entry.def, env, rng, entry.weights)
    result[kind] = table_
    result.explain[kind] = explain
  end

  if remember ~= false then
    for id in pairs(state.species) do areaSpecies[area][id] = true end
    history.maps[#history.maps + 1] = {
      area = area, species = state.species, families = state.families,
    }
    while #history.maps > HISTORY_KEEP do table.remove(history.maps, 1) end
  end
  return result
end

-- Every map in the game's own order, in one pass (SEEDED).
-- Returns { [mapId] = buildMap result }.
function Generator.buildAll(ctx)
  local memory = Generator.newMemory()
  local out = {}
  for _, mapId in ipairs(ctx.world.mapOrder()) do
    out[mapId] = Generator.buildMap(ctx, mapId, memory)
  end
  return out
end

-- ------------------------------------------------------------ legendaries

-- Where each legendary/mythical may appear when LEGENDARIES is ON. They are
-- never put in a table (eligible() refuses them at every tier); instead each
-- one gets a few HOME maps, and the runtime lets a tiny share of encounters
-- there become that species. A home must fit on level (the table's levels
-- within `level_tolerance` of the species' window), terrain, and place (a
-- habitat or map theme it matches), so Articuno ends up in an icy cave and
-- nothing legendary ever lives on Route 1. Seed-independent on purpose:
-- homes read as "where it lives" and stay put across saves and modes.
--
-- Returns { [mapId] = { grass = { {id, score, category}, ... }, water = {...} } }
function Generator.legendaryHomes(ctx)
  local world, config = ctx.world, ctx.config
  local rules = config.legendary
  local specials = {}
  for _, c in ipairs(ctx.pool.list) do
    if c.special and c.gen <= ctx.maxGen then specials[#specials + 1] = c end
  end
  if #specials == 0 then return {} end

  -- every (map, table) a legendary could host in, with its scoring env
  local slots, order = {}, 0
  local emptyHistory = { previous = {}, recent = {}, recentFamilies = {} }
  for _, mapId in ipairs(world.mapOrder()) do
    local info = world.mapInfo(mapId)
    for _, entry in ipairs(world.tables(mapId) or {}) do
      local kind, terrain, def = entry.kind, entry.terrain, entry.def
      -- walking and surfing tables only; nothing legendary on a fishing line
      if terrain ~= "fish" then
        if type(def.slots) == "table"
          and #def.slots > 0 and (def.rate or 0) > 0 then
          local lo, hi
          for _, slot in ipairs(def.slots) do
            lo = math.min(lo or slot.level, slot.level)
            hi = math.max(hi or slot.level, slot.level)
          end
          local place = ctx.MapContext.describe(mapId, info, terrain)
          order = order + 1
          if hi >= rules.min_level then slots[#slots + 1] = {
            mapId = mapId, kind = kind, order = order,
            role = { minLevel = lo, maxLevel = hi, rarity = "v" },
            env = {
              terrain = terrain, habitats = place.habitats, mapTypes = place.types,
              maxGen = ctx.maxGen, config = config, pool = ctx.pool,
              state = { species = {}, families = {}, gens = {} },
              history = emptyHistory, areaSpecies = {},
            },
          } end
        end
      end
    end
  end

  -- every acceptable (species, map table) pair, scored
  local fits = {}
  for _, c in ipairs(specials) do
    for _, slot in ipairs(slots) do
      if terrainOk(c, slot.env.terrain, false)
        and levelDistance(c, slot.role) <= rules.level_tolerance then
        local value, reasons = score(c, slot.role, slot.env, true)
        local placed = false
        for _, reason in ipairs(reasons) do
          if reason == "map_type" then value = value + rules.theme_bonus end
          if reason == "habitat_match" or reason == "map_type" then placed = true end
        end
        if placed then fits[#fits + 1] = { c = c, slot = slot, score = value } end
      end
    end
  end

  -- best fits claim homes first; a species stops at homes_per_species and a
  -- map table at max_per_map, so the next-best fit moves elsewhere
  table.sort(fits, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.c.id ~= b.c.id then return a.c.id < b.c.id end
    return a.slot.order < b.slot.order
  end)
  local homes, perSpecies, perSlot = {}, {}, {}
  for _, fit in ipairs(fits) do
    local slot = fit.slot
    if (perSpecies[fit.c.id] or 0) < rules.homes_per_species
      and (perSlot[slot] or 0) < rules.max_per_map then
      perSpecies[fit.c.id] = (perSpecies[fit.c.id] or 0) + 1
      perSlot[slot] = (perSlot[slot] or 0) + 1
      homes[slot.mapId] = homes[slot.mapId] or {}
      local list = homes[slot.mapId][slot.kind] or {}
      homes[slot.mapId][slot.kind] = list
      list[#list + 1] = { id = fit.c.id, score = fit.score, category = fit.c.special }
    end
  end
  for _, byKind in pairs(homes) do
    for _, list in pairs(byKind) do
      table.sort(list, function(a, b) return a.id < b.id end)
    end
  end
  return homes
end

-- exposed for tests
Generator._areaOf = areaOf
Generator._buildRoles = buildRoles

return Generator
