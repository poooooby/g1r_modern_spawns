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
  -- A table whose every slot held one species (Sootopolis' and Route 19's surf: all Magikarp
  -- or all Tentacool) would be one role, so one species however it is drawn. Each slot is a
  -- role of its own instead, keeping the cart's odds per slot, so these tables vary like any
  -- other.
  -- A Gen 2 grass table holds morning, day and night (`times`), and a role there spans all
  -- three: the nth slot of each time shares one role, so a species stays out all day as the
  -- cart's own do.
  if #roles == 1 and #roles[1].slots > 1 then
    local only = roles[1]
    roles = {}
    local byKey, nth = {}, {}
    for _, i in ipairs(only.slots) do
      local slot = slots[i]
      local key = i
      if times and times[i] then
        nth[times[i]] = (nth[times[i]] or 0) + 1
        key = "n" .. nth[times[i]]
      end
      local role = byKey[key]
      if not role then
        role = { species = only.species, slots = {}, first = i, weight = 0,
                 minLevel = slot.level, maxLevel = slot.maxLevel or slot.level }
        byKey[key] = role
        roles[#roles + 1] = role
      end
      role.slots[#role.slots + 1] = i
      role.weight = role.weight + (weights[i] or 0)
      role.minLevel = math.min(role.minLevel, slot.level)
      role.maxLevel = math.max(role.maxLevel, slot.maxLevel or slot.level)
      if times and times[i] then
        role.times = role.times or {}
        role.times[times[i]] = true
      end
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

-- Habitat tags that say nothing about a place: nearly every species has been
-- met on some route, so sharing one is a weak hint, not a fit.
local GENERIC_HABITATS = { route = true, general = true }
-- Tags that make a map a PLACE (a cave, a forest, a tower, a beach) rather
-- than an ordinary route: such a map, or one with a theme type (GHOST in a
-- tower, ELECTRIC in a power plant), draws its strict tier from species that
-- share one of these or a theme type.
local THEME_HABITATS = { cave = true, forest = true, ruins = true, snow = true,
                         desert = true, mountain = true, water = true, coast = true }

local function themed(env)
  if next(env.mapTypes or {}) then return true end
  for h in pairs(env.habitats or {}) do
    if THEME_HABITATS[h] then return true end
  end
  return false
end

local function fitsTheme(c, env)
  for t in pairs(c.types) do
    if env.mapTypes[t] then return true end
  end
  for h in pairs(c.habitats) do
    if THEME_HABITATS[h] and env.habitats[h] then return true end
  end
  return false
end

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

-- The lowest level a candidate counts as appearing at. A first-stage,
-- low-base-stat species ("plausible basic", SpawnConfig.plausible_basic) is
-- treated as available from `floor_level` even when its observed wild levels
-- start later: most modern species are only met at higher levels by game
-- design, so the observed data alone leaves an early slot with a couple of
-- dozen candidates. Only the LOWER bound moves; `hi` is never raised.
local function effectiveLo(c, rule)
  if rule and c.basic and c.bst <= rule.max_bst and c.lo > rule.floor_level then
    return rule.floor_level
  end
  return c.lo
end

local function levelDistance(c, role, rule)
  local lo = effectiveLo(c, rule)
  if lo <= role.maxLevel and c.hi >= role.minLevel then return 0 end
  if lo > role.maxLevel then return lo - role.maxLevel end
  return role.minLevel - c.hi
end

local function underleveled(c, role, tolerance)
  return c.evolveLevel ~= nil and role.maxLevel < c.evolveLevel - tolerance
end

-- TIME OF DAY SPAWNS: the periods a pick for this role is shown in. Gen 2
-- grass knows each slot's time; a day or night pass (env.period) shows its own;
-- a COMPLETE pool member (`pooled`) is drawn whenever its seat is rolled, by
-- day and at night.
local function periodsOf(env, role, pooled)
  if role.times then
    return (role.times.MORN or role.times.DAY) and true or false, role.times.NITE == true
  end
  if pooled or not env.period then return true, true end
  return env.period == "day", env.period == "night"
end

-- STRICT: a species that only comes out by day (or at night) is never shown at
-- the other time. A primary must suit every period it is shown in, a pool
-- member some period its seat is rolled in (the runtime skips it at the
-- other). Always true while the option is OFF (env.tod nil).
local function strictOk(c, env, role, pooled)
  if env.tod ~= "strict" or not c.todOnly then return true end
  local day, night = periodsOf(env, role, pooled)
  if pooled then return (c.tod == "day" and day) or (c.tod == "night" and night) or false end
  if c.tod == "day" then return not night end
  return not day
end

-- tier 1: terrain + plausible level (+ the place's theme on a themed map);
-- tier 2: terrain; tier 3: anything non-special under the cap. Special
-- species are never eligible at any tier, nor (STRICT) one out at the wrong
-- time.
local function eligible(c, env, role, tier, pooled)
  if c.special then return false end
  if c.gen > env.maxGen then return false end
  if not strictOk(c, env, role, pooled) then return false end
  if tier >= 3 then return true end
  if not terrainOk(c, env.terrain, tier >= 2) then return false end
  if tier >= 2 then return true end
  if env.themed and not fitsTheme(c, env) then return false end
  return levelDistance(c, role, env.config.plausible_basic) <= env.config.strict_level_distance
    and not underleveled(c, role, env.config.evolve_tolerance)
end

-- ---------------------------------------------------------------- scoring

-- `labelled` builds the reason/penalty lists; it is only asked for the
-- winning candidate, because scoring ~1000 candidates per role with a label
-- list each would be most of the generator's cost. `pooled` scores a COMPLETE
-- pool member, which is drawn by day and at night alike.
local function score(c, role, env, labelled, pooled)
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

  local rule = env.config.plausible_basic
  local dist = levelDistance(c, role, rule)
  if dist == 0 then
    add(W.level_overlap, "level_overlap")
  else
    add(dist * W.level_distance, "level_distance")
  end
  -- fitting only through the basic's lowered floor: observed data wins a
  -- close call, the same way an estimated profile does
  if rule and levelDistance(c, role) > dist then
    add(rule.penalty, "plausible_basic")
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

  local shared, generic = 0, false
  for h in pairs(c.habitats) do
    if env.habitats[h] then
      if GENERIC_HABITATS[h] then generic = true else shared = shared + 1 end
    end
  end
  if shared > 0 then
    add(W.habitat_match + (shared - 1) * W.habitat_extra, "habitat_match")
  elseif generic then
    add(W.habitat_generic, "habitat_generic")
  end

  local vanilla = env.pool.byId[role.species]
  if vanilla then
    local same = 0
    for t in pairs(c.types) do
      if vanilla.types[t] then same = same + 1 end
    end
    if same > 0 then add(math.min(same, 2) * W.type_match, "type_match") end
    -- LIMITED (SpawnConfig.selection.seeded.resemble): a replacement that
    -- shares the replaced species' types keeps the original table's character
    local resemble = env.selection and env.selection.resemble
    if resemble and same > 0 then add(math.min(same, 2) * resemble, "resembles_replaced") end
  end
  for t in pairs(c.types) do
    if env.mapTypes[t] then
      add(W.map_type, "map_type")
      break
    end
  end

  -- Gen 2 day/night: the game's own tables say which species only come out
  -- at night (or never do); keep them on the matching side of the clock.
  -- TIME OF DAY SPAWNS reads the day/night data instead (the cart's own habit
  -- where the data has no call; species_pool.lua).
  if (role.nightOnly or role.dayOnly) and (env.tod or env.timeOf) then
    local habit
    if env.tod then habit = c.tod else habit = env.timeOf(c.id) end
    if (role.nightOnly and habit == "day") or (role.dayOnly and habit == "night") then
      add(W.time_mismatch, "wrong_time_of_day")
    elseif role.nightOnly and (habit == "night" or c.types.GHOST or c.types.DARK) then
      add(W.time_match, "time_of_day_match")
    end
  end
  -- TIME OF DAY SPAWNS: a day or night roster favours what is out at its time,
  -- and the night roster keeps a role's day species when it is no day one
  if env.tod and env.period and not pooled then
    if c.tod == env.period then
      add(W.tod_match, "time_of_day_match")
    elseif c.tod then
      add(W.tod_mismatch, "wrong_time_of_day")
    end
    if env.keep and env.keep[role.first] == c.id then
      add(W.tod_keep, "out_day_and_night")
    end
  end

  if c.source == "estimate" and not c.estimateOnlyGen then
    add(W.estimated_profile, "estimated_profile")
  end

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
      local weights = {}
      if selection.temperature then
        -- Softmax over the scorers within `window` points of the best: a
        -- long, flat-enough shortlist so seeds and draws differ, but nothing
        -- more than `window` worse than the best fit is ever drawn.
        local best = scored[1].score
        local window = selection.window or math.huge
        for i = 1, top do
          if best - scored[i].score > window then break end
          weights[i] = math.exp((scored[i].score - best) / selection.temperature)
        end
      else
        -- the original rule (SpawnConfig.selection without a temperature):
        -- weighted by score above the worst of the top N, to a power
        local power = selection.power or 2
        local floor = scored[top].score
        for i = 1, top do
          weights[i] = (scored[i].score - floor + 1) ^ power
        end
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
    -- TIME OF DAY SPAWNS: the day pass remembers each role's pick (the night
    -- pass may keep it) and seat (the night pick joins its pool)
    if env.record then env.record.picks[role.first] = { id = species, c = c } end
    -- COMPLETE DEX (buildAtlas) collects every walking/surfing role as a seat
    -- whose pool the coverage pass extends; the primary is the role's pick.
    -- A fishing table joins only when its adapter marks it `pooled` (Gen 3's
    -- Good and Super Rods). A night pick is the same seat's second primary:
    -- one pool serves the role day and night.
    if env.seats and (env.terrain ~= "fish" or env.pooled) then
      local daySeat = env.daySeats and env.daySeats[role.first]
      if daySeat then
        daySeat.nightBase = species
        local present = false
        for _, id in ipairs(daySeat.pool) do
          if id == shown then present = true break end
        end
        if not present then daySeat.pool[#daySeat.pool + 1] = shown end
      else
        local seat = { mapId = env.mapId, kind = env.kind, role = role,
                       env = env, base = species, pool = { shown } }
        env.seats[#env.seats + 1] = seat
        if env.record then env.record.seats[role.first] = seat end
      end
    end
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
-- One pass over a map's tables into `result`. `period` is TIME OF DAY SPAWNS'
-- "day"/"night" (nil while OFF), `suffix` a field appended to every RNG key
-- (the night pass), `record` collects the day pass's picks and seats per kind,
-- `dayRecord` hands them to the night pass. A night pass skips the tables that
-- already know each slot's time (Gen 2 grass). Returns whether any table ran.
local function mapPass(ctx, mapId, entries, info, area, memory, nonce, remember,
                       result, period, suffix, record, dayRecord)
  local config = ctx.config
  local history, areaSpecies = memory.history, memory.areaSpecies
  areaSpecies[area] = areaSpecies[area] or {}
  local state = { species = {}, families = {}, gens = {} }
  local ran = false
  -- `isolated` tables (Gen 3's rods, added after 0.13.0) see what the map
  -- already holds but share their own picks only with each other: the map's
  -- memory and the rolling history never hear of them, so adding them did
  -- not move any walking or surfing roster
  local isolatedState

  for _, entry in ipairs(entries) do
    if not (suffix and entry.times) then
      ran = true
      local kind, terrain = entry.kind, entry.terrain
      local place = ctx.MapContext.describe(mapId, info, terrain)
      local entryState = state
      if entry.isolated then
        if not isolatedState then
          isolatedState = { species = {}, families = {}, gens = {} }
          for _, key in ipairs({ "species", "families", "gens" }) do
            for k, v in pairs(state[key]) do isolatedState[key][k] = v end
          end
        end
        entryState = isolatedState
      end
      local env = {
        terrain = terrain, habitats = place.habitats, mapTypes = place.types,
        maxGen = ctx.maxGen, config = config, pool = ctx.pool, state = entryState,
        pooled = entry.pooled,
        history = historyView(history, area, config.history_window_maps),
        areaSpecies = areaSpecies[area],
        selection = ctx.selection,
        slotTimes = entry.times, timeOf = ctx.world.timeOf,
        mapId = mapId, kind = kind, seats = ctx.seats,
      }
      env.themed = themed(env)
      if ctx.timeOfDay then
        env.tod = ctx.timeOfDay
        env.period = not entry.times and period or nil
        if record then
          record[kind] = { picks = {}, seats = {} }
          env.record = record[kind]
        end
        local day = dayRecord and dayRecord[kind]
        if day then
          env.daySeats = day.seats
          -- the night roster keeps a role's day species unless it is a day one
          env.keep = {}
          for first, pick in pairs(day.picks) do
            if not (pick.c and pick.c.tod == "day") then env.keep[first] = pick.id end
          end
        end
      end
      -- SEEDED passes no nonce and must hash exactly as 0.1.0 did, so a save's
      -- rosters survive upgrades; an extra field would reshuffle every draw
      local key
      if suffix == nil then
        key = nonce == nil
          and ctx.Rng.hash(ctx.seed, mapId, kind, ctx.maxGen, ctx.dataVersion)
          or ctx.Rng.hash(ctx.seed, mapId, kind, ctx.maxGen, ctx.dataVersion, nonce)
      else
        key = nonce == nil
          and ctx.Rng.hash(ctx.seed, mapId, kind, ctx.maxGen, ctx.dataVersion, suffix)
          or ctx.Rng.hash(ctx.seed, mapId, kind, ctx.maxGen, ctx.dataVersion, nonce, suffix)
      end
      local rng = ctx.Rng.new(key)
      local table_, explain = redistribute(entry.def, env, rng, entry.weights)
      result[kind] = table_
      result.explain[kind] = explain
    end
  end

  if remember ~= false and ran then
    for id in pairs(state.species) do areaSpecies[area][id] = true end
    history.maps[#history.maps + 1] = {
      area = area, species = state.species, families = state.families,
    }
    while #history.maps > HISTORY_KEEP do table.remove(history.maps, 1) end
  end
  return ran
end

function Generator.buildMap(ctx, mapId, memory, nonce, remember)
  local entries = ctx.world.tables(mapId)
  if not entries or #entries == 0 then return nil end
  local info = ctx.world.mapInfo(mapId)
  local area = areaOf(mapId)
  local result = { explain = {} }

  -- TIME OF DAY SPAWNS (ctx.timeOfDay "prefer"/"strict"; nil while OFF, which
  -- builds exactly one pass as before): the day roster on the usual keys and
  -- memory, then a night roster with "night" appended to every key and a
  -- memory of its own (memory.night), so night picks never move a day roster.
  -- `ctx.only` builds one period's roster alone (RANDOM's one-off draws).
  local tod = ctx.timeOfDay
  local dayRecord = tod and not ctx.only and {} or nil
  mapPass(ctx, mapId, entries, info, area, memory, nonce, remember, result,
          tod and (ctx.only or "day") or nil, nil, dayRecord, nil)
  if tod and not ctx.only then
    memory.night = memory.night or Generator.newMemory()
    local night = { explain = {} }
    if mapPass(ctx, mapId, entries, info, area, memory.night, nonce, remember, night,
               "night", "night", nil, dayRecord) then
      result.night = night
    end
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

-- ------------------------------------------------------------ complete dex

-- COMPLETE DEX: every species under the cap is catchable somewhere. There are
-- more species than slots on every game (Emerald: ~940 at GEN 1-9 against
-- 1319 walking/surfing slots in 454 roles), so a role carries a POOL: the
-- engine still rolls the slot with the game's own odds, and the species is
-- drawn from that slot's pool afterwards (src/runtime.lua).
--
-- Pass 1 is buildAll (same seed key per map, drawn with COMPLETE's own
-- `selection`, so the primaries differ from LIMITED's), which gives every role
-- its primary species. Pass 2 places every species still missing: hardest
-- first (fewest strict-tier roles), each scored against every role through
-- the usual tiers, minus `pool_penalty` per species a role already holds so
-- extras spread out, then a seeded softmax draw among the best. A role holds
-- at most `max_pool` species while any other role has room, so late-game
-- evolutions overflow to the next-best area instead of all landing in the
-- last high-level cave. Tier 3 takes any role, so coverage is total.
--
-- Returns buildAll's shape plus result.pools[kind][slot] = { species ids },
-- the primary first and the cart's own species for the role last; slots of
-- one role share one list.
local COVERAGE_PASSES = {
  { tier = 1, capped = true },
  { tier = 2, capped = true, onTheme = true },
  { tier = 2, capped = true },
  { tier = 3, capped = true, onTheme = true },
  { tier = 3, capped = true },
  { tier = 3, capped = false },
}

function Generator.buildAtlas(ctx)
  local seats = {}
  local actx = setmetatable({ seats = seats }, { __index = ctx })
  local memory = Generator.newMemory()
  local out = {}
  for _, mapId in ipairs(ctx.world.mapOrder()) do
    local result = Generator.buildMap(actx, mapId, memory)
    if result then
      result.pools = {}
      out[mapId] = result
    end
  end

  -- a seat's pool already holds its primary (and, with TIME OF DAY SPAWNS, its
  -- night primary); pools are drawn from by day and at night alike, so the
  -- coverage below is period-neutral (`pooled`) and STRICT only asks that a
  -- species can come out at some time its seat is rolled
  local placed = {}
  for _, seat in ipairs(seats) do
    for _, id in ipairs(seat.pool) do placed[id] = true end
    placed[seat.base] = true
    if seat.nightBase then placed[seat.nightBase] = true end
  end

  local missing = {}
  for _, c in ipairs(ctx.pool.list) do
    if not c.special and c.gen <= ctx.maxGen and not placed[c.id] then
      local strict = 0
      for _, seat in ipairs(seats) do
        if eligible(c, seat.env, seat.role, 1, true) then strict = strict + 1 end
      end
      missing[#missing + 1] = { c = c, strict = strict }
    end
  end
  table.sort(missing, function(a, b)
    if a.strict ~= b.strict then return a.strict < b.strict end
    return a.c.id < b.c.id
  end)

  local rules = ctx.config.complete
  for _, m in ipairs(missing) do
    local c, scored = m.c, {}
    -- a full role (`max_pool`) is skipped while any tier has room elsewhere,
    -- and a species that misses a themed map's theme tries the roles it fits
    -- and the unthemed ones first, so it lands on a plain route rather than in
    -- a tower; only when every role is full does the last pass ignore the cap
    for _, pass in ipairs(COVERAGE_PASSES) do
      for i, seat in ipairs(seats) do
        if eligible(c, seat.env, seat.role, pass.tier, true)
          and (not pass.capped or #seat.pool < rules.max_pool)
          and (not pass.onTheme or not seat.env.themed or fitsTheme(c, seat.env)) then
          scored[#scored + 1] = { seat = seat, order = i,
            score = score(c, seat.role, seat.env, false, true)
              + (#seat.pool - 1) * rules.pool_penalty }
        end
      end
      if #scored > 0 then break end
    end
    if #scored > 0 then
      table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
      end)
      local best, weights = scored[1].score, {}
      for i = 1, math.min(#scored, rules.top) do
        if best - scored[i].score > rules.window then break end
        weights[i] = math.exp((scored[i].score - best) / rules.temperature)
      end
      local rng = ctx.Rng.new(ctx.Rng.hash(ctx.seed, "atlas", c.id, ctx.maxGen,
                                           ctx.dataVersion))
      local seat = scored[rng:weighted(weights) or 1].seat
      seat.pool[#seat.pool + 1] = c.id
      seat.env.state.species[c.id] = true
    end
  end

  -- The cart's own species stay catchable where the cart put them: each
  -- seat's pool also holds the species its role replaced (Viridian Forest's
  -- Pikachu, Route 119's Feebas), when it is under the cap. Added last, so it
  -- never takes a `max_pool` place from coverage, and never as the primary.
  for _, seat in ipairs(seats) do
    local original = ctx.pool.byId[seat.role.species]
    if original and not original.special and original.gen <= ctx.maxGen then
      local present = false
      for _, id in ipairs(seat.pool) do
        if id == original.id then present = true break end
      end
      if not present then seat.pool[#seat.pool + 1] = original.id end
    end
  end

  for _, seat in ipairs(seats) do
    local result = out[seat.mapId]
    if result then
      result.pools[seat.kind] = result.pools[seat.kind] or {}
      for _, i in ipairs(seat.role.slots) do result.pools[seat.kind][i] = seat.pool end
    end
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
  local slots, all, order = {}, {}, 0
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
          local candidate = {
            mapId = mapId, kind = kind, order = order,
            role = { minLevel = lo, maxLevel = hi, rarity = "v" },
            env = {
              terrain = terrain, habitats = place.habitats, mapTypes = place.types,
              maxGen = ctx.maxGen, config = config, pool = ctx.pool,
              state = { species = {}, families = {}, gens = {} },
              history = emptyHistory, areaSpecies = {},
            },
          }
          candidate.env.themed = themed(candidate.env)
          all[#all + 1] = candidate
          if hi >= rules.min_level then slots[#slots + 1] = candidate end
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
  -- COMPLETE DEX: every special in the cap must be reachable, so one left
  -- without a home gets its best walking/surfing table, ignoring the level
  -- floor, the level tolerance and the per-table limit.
  if ctx.guaranteeHomes then
    for _, c in ipairs(specials) do
      if not perSpecies[c.id] then
        local best, bestScore
        for _, slot in ipairs(all) do
          local value = score(c, slot.role, slot.env, false)
          if not terrainOk(c, slot.env.terrain, false) then value = value - 100 end
          if not best or value > bestScore then best, bestScore = slot, value end
        end
        if best then
          perSpecies[c.id] = 1
          homes[best.mapId] = homes[best.mapId] or {}
          local list = homes[best.mapId][best.kind] or {}
          homes[best.mapId][best.kind] = list
          list[#list + 1] = { id = c.id, score = bestScore, category = c.special }
        end
      end
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
