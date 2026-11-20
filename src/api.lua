-- The framework surface other mods consume, published on mod.exports.
--
--   local spawns = mod:find("modern_spawns")
--   if spawns and (spawns.exports.apiVersion or 0) >= 1 then
--     local grass = spawns.exports.tableFor("ROUTE_1", "grass")
--   end
--
-- Everything returned is a COPY: a consumer can never mutate the tables the
-- encounter hooks hand the engine. Functions answer nil while modern spawns
-- are inactive (MODERN SPAWNS off, or no species registered at all), which
-- a consumer should read as "use the game's own tables".
--
-- API VERSIONING: apiVersion only goes up, and only when an existing field
-- changes meaning or disappears; check `>=`, never `==`.
--
-- Event: mod.modern_spawns.tables_changed { maxGeneration, generations, seed, mode,
-- timeOfDay }
-- fires each time tables are (re)generated (under EVERY MAP: once per map visit).
-- Event: mod.modern_spawns.period_changed { period, previous } fires when TIME OF
-- DAY SPAWNS sees the clock turn ("day" <-> "night"); a consumer holding visible
-- spawns can redraw them.

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deepCopy(v) end
  return out
end

local function setToList(set)
  local list = {}
  for k in pairs(set or {}) do list[#list + 1] = k end
  table.sort(list)
  return list
end

-- A pool entry in plain data: sets flattened to sorted lists.
local function describe(c)
  return {
    id = c.id, dex = c.dex, generation = c.gen, types = deepCopy(c.typeList),
    bst = c.bst, family = c.family, stage = c.stage,
    evolveLevel = c.evolveLevel, evolves = c.evolves,
    -- the species it evolves from (nil for a first stage)
    evolvesFrom = c.parent,
    minLevel = c.lo, maxLevel = c.hi, typicalLevel = c.typ,
    rarity = c.rarity, habitats = setToList(c.habitats),
    terrains = setToList(c.terrains), special = c.special,
    profileSource = c.source,
    form = c.form, baseSpecies = c.baseSpecies, variants = deepCopy(c.variants),
    -- "day" | "night" | nil: when it comes out (data/time_of_day.lua); Only:
    -- only then (TIME OF DAY SPAWNS STRICT keeps it to that time)
    timeOfDay = c.tod, timeOfDayOnly = c.todOnly,
  }
end

return function(deps)
  local mod, Runtime, Config = deps.mod, deps.Runtime, deps.Config
  local exports = mod.exports

  -- Added fields don't bump it (0.7.0 added drawFor / legendaryFor): test
  -- for a newer function by presence, `type(exports.drawFor) == "function"`.
  -- 2: isActive is true on GEN 1 and with only the cart's species (it was false for both),
  -- and maxGeneration can answer 1.
  -- 3: GENERATIONS can be any set of generations (CUSTOM: Gen 1, 3, 6), so
  -- maxGeneration is the highest one in force, no longer "every generation up
  -- to it"; read generations() for the set.
  exports.apiVersion = 3

  exports.isActive = function()
    return Runtime.isActive()
  end

  local function listOf(gs)
    if not gs then return nil end
    local out = {}
    for i, g in ipairs(gs.list) do out[i] = g end
    return out
  end

  -- The highest generation in force (1..9), or nil when inactive.
  exports.maxGeneration = function()
    return Runtime.effectiveGeneration()
  end

  -- The generations in force, ascending ({ 1, 3, 6 }), or nil when inactive.
  exports.generations = function()
    return listOf(Runtime.effectiveGenerations())
  end

  -- The player's settings, whatever is in force: maxGeneration the highest
  -- generation picked, generations every one picked (may be empty).
  exports.settings = function()
    local picked = setToList(Config.generations(mod))
    return { enabled = Config.enabled(mod), maxGeneration = Config.maxGeneration(mod),
             generations = picked,
             spawnMode = Config.spawnMode(mod), legendaries = Config.legendaries(mod),
             shinyChain = Config.shinyChain(mod), timeOfDay = Runtime.timeOfDay(),
             trainerTeams = Config.trainerTeams(mod) }
  end

  -- TRAINER TEAMS (since 0.15.0): { mode = "off"|"on"|"items", maxGeneration,
  -- generations, active } -- active while ON with species to draw from
  -- (independent of MODERN SPAWNS).
  local Trainers = deps.Trainers
  exports.trainerTeams = function()
    local gs = Trainers and Trainers.generations and Trainers.generations() or nil
    return { mode = Config.trainerTeams(mod), maxGeneration = gs and gs.max or nil,
             generations = listOf(gs), active = gs ~= nil }
  end
  -- Test seam: the moves (with their physical / special category) TRAINER
  -- TEAMS' held items are chosen by for species `id` at `level`, or nil.
  exports._trainerMovesFor = function(id, level)
    if not (Trainers and Trainers.movesFor) then return nil end
    local ok, out = pcall(Trainers.movesFor, id, level)
    return ok and deepCopy(out) or nil
  end
  -- The team a battle would field: trainerTeamFor(class, id, party) with the
  -- trainer.party hook's own arguments for the running game; a copy of the
  -- new party, or nil when TRAINER TEAMS leaves it alone.
  exports.trainerTeamFor = function(class, id, party)
    if not Trainers then return nil end
    local ok, out = pcall(Trainers.party, class, id, party)
    return ok and deepCopy(out) or nil
  end
  -- Who a battle's trainer is, with the same arguments: rematches, the rival's
  -- fights and a gym leader's rounds share one identity (one family map), or
  -- nil for a battle TRAINER TEAMS leaves alone.
  exports.trainerIdentity = function(class, id, party)
    if not Trainers then return nil end
    local ok, out = pcall(Trainers.identity, class, id, party)
    return ok and out or nil
  end
  -- A battle facility's species map for this save, { [original id] = new id }
  -- (one-to-one), or nil while TRAINER TEAMS is OFF or the cart has no such
  -- facility. Names: "crystal_battle_tower" (Crystal), "emerald_frontier"
  -- (every Frontier facility, the Battle Tents and the Pyramid / Pike wild
  -- Pokemon), "trainer_hill" (Emerald), "rs_battle_tower" (Ruby/Sapphire),
  -- "frlg_trainer_tower" (FireRed/LeafGreen).
  exports.facilitySpecies = function(name)
    if not Trainers then return nil end
    local ok, out = pcall(Trainers.facilitySpecies, name)
    return ok and deepCopy(out) or nil
  end

  -- "day" | "night" on the clock TIME OF DAY SPAWNS follows (WoobleDex's Clock
  -- Source; the cart's own clock on Gold/Silver/Crystal), whatever the option
  -- is set to; nil without a clock. Since 0.14.0.
  exports.period = function()
    return Runtime.period()
  end
  -- Tests: pin the period ("day"/"night"; nil follows the clock again).
  exports._pinPeriod = function(period)
    Runtime.pinPeriod(period)
  end

  -- Where legendaries/mythicals may appear when LEGENDARIES is ON:
  -- { [mapId] = { grass = { {id, score, category}, ... }, water = {...} } }.
  -- Answered whatever LEGENDARIES is set to (nil only while inactive), so a
  -- consumer can show where they would be. Rates: SpawnConfig.legendary.
  exports.legendaryHomes = function()
    return deepCopy(Runtime.legendaryHomes())
  end

  -- "seeded" | "map" | "random" | "complete" (COMPLETE DEX: tableFor is each
  -- slot's primary species, poolFor what it can turn into). Under "random"
  -- there is no fixed table:
  -- tableFor/superRodFor/explain answer nil and each encounter is drawn fresh.
  exports.spawnMode = function()
    return Config.spawnMode(mod)
  end

  -- The loaded save's seed (a short text code), and ways to change it. The
  -- seed persists with the player's next SAVE; the mode never changes it.
  exports.seed = function()
    return Runtime.seed()
  end
  exports.setSeed = function(value)
    return Runtime.setSeed(value)
  end
  exports.rerollSeed = function()
    return Runtime.rerollSeed()
  end

  -- 1 (Red/Blue/Yellow) or 2 (Gold/Silver/Crystal): which shapes the
  -- table functions below answer in.
  exports.generation = function()
    return Runtime.world.generation
  end

  -- The generated table in the running game's own shape. terrain:
  -- "grass" | "indoor" | "water" (Gen 2 also "fish.good" / "fish.super").
  --   Gen 1: { rate, slots, buckets? }
  --   Gen 2 grass: { map, rates = {MORN,DAY,NITE}, slots = {MORN={7}, DAY={7}, NITE={7}} }
  --   Gen 2 water: { map, rate, slots = {3} }
  -- `period` ("day"/"night", optional, since 0.14.0): with TIME OF DAY SPAWNS
  -- on, that period's roster; by default the one in force now. While it is
  -- OFF there is one roster and `period` changes nothing.
  exports.tableFor = function(mapId, terrain, period)
    return deepCopy(Runtime.tableFor(mapId, terrain or "grass", period))
  end

  -- For a mod that picks species itself, once per pick (visible overworld
  -- spawns): tableFor under SEEDED / EVERY MAP, a fresh one-off draw under
  -- RANDOM, so each pick sees what that mode would roll. Same shape as tableFor.
  exports.drawFor = function(mapId, terrain, period)
    return deepCopy(Runtime.drawFor(mapId, terrain or "grass", period))
  end

  -- COMPLETE DEX only: the species each slot of tableFor's table can turn
  -- into, { [slot] = { species ids } } (the slot's own species first); nil
  -- in every other mode. Since 0.12.0. With TIME OF DAY SPAWNS on, what each
  -- slot can turn into at `period` (default: now).
  exports.poolFor = function(mapId, terrain, period)
    return deepCopy(Runtime.poolFor(mapId, terrain or "grass", period))
  end

  -- Every species on a map and how likely it is, method by method, under
  -- the current settings (since 0.18.0; the WoobNav reads it). mapId defaults
  -- to the player's map. Percentages are of that method's encounters (a
  -- walking encounter is 35% this species), the cart's own odds per slot,
  -- COMPLETE's pools split the way the encounter hook draws from them
  -- (TIME OF DAY SPAWNS weights included), looks folded into their base.
  -- Unlike every other function it also answers while inactive, from the
  -- game's own tables (`active` false). opts: period ("day"/"night"; default
  -- now), time (Gen 2 grass: "MORN"/"DAY"/"NITE"/"all"; default now).
  --   -> { mapId, name, active, random, mode, period, time,
  --        sections = { { method = "grass"|"cave"|"surf"|"old"|"good"|"super"|"rock",
  --                       kind, time?, rate,
  --                       mons = { { id, chance (0-100), minLevel, maxLevel, pooled } } } },
  --        rare = { { id, category = "legendary"|"mythical", method, odds (1 in odds) } } }
  -- RANDOM (`random` true) has no fixed walking/surfing/rod lists, so only
  -- the game's own sections (the Old Rod, Rock Smash) are listed.
  exports.encounters = function(mapId, opts)
    return deepCopy(Runtime.encountersAt(mapId, opts))
  end

  -- The map the player is on (the id every other function takes), or nil.
  exports.currentMap = function()
    return Runtime.currentMap()
  end

  -- A map's place name as the game shows it ("ROUTE 1"), or nil.
  exports.areaName = function(mapId)
    return Runtime.areaName(mapId)
  end

  -- Where a species can be met under the current settings:
  -- { [mapId] = { land|grass|water = true } } (a copy). Generated tables and
  -- COMPLETE pools, the maps drawn this session under EVERY MAP, and home
  -- maps with LEGENDARIES ON; empty under RANDOM; nil while inactive. The Gen 3
  -- Pokedex AREA page and its undiscovered-entry view answer from this. Since 0.11.0.
  exports.locate = function(speciesId)
    return deepCopy(Runtime.mapsWithSpecies(speciesId))
  end

  -- The LEGENDARIES roll for such a pick: a legendary (1/1024) or mythical
  -- (1/2048) species id hosted on this map and not yet owned, or nil. Call it
  -- once per pick and use the species in place of the table's.
  exports.legendaryFor = function(mapId, terrain)
    return Runtime.legendaryFor(mapId, terrain or "grass")
  end

  -- The Super Rod's generated catches for a map: Gen 1 { { species, level } },
  -- Gen 2 fish rows { { chance, species, level } }; nil when not generated.
  exports.superRodFor = function(mapId)
    return deepCopy(Runtime.tableFor(mapId, "superRod"))
  end

  -- Per-slot selection records: { slot, level, species, replaced, score,
  -- tier, source, reasons = {...}, penalties = {...} }.
  exports.explain = function(mapId, terrain, period)
    return deepCopy(Runtime.explain(mapId, terrain, period))
  end

  -- Candidate pool entries. opts (all optional): maxGeneration, generations
  -- (a list: only these), terrain
  -- ("grass"|"cave"|"water"|"fish"), minLevel/maxLevel (overlap), habitat,
  -- includeSpecial (legendary/mythical are left out unless true).
  exports.candidates = function(opts)
    opts = opts or {}
    local pool = Runtime.pool()
    if not pool then return {} end
    local only
    if type(opts.generations) == "table" then
      only = {}
      for _, g in ipairs(opts.generations) do only[g] = true end
    end
    local out = {}
    for _, c in ipairs(pool.list) do
      local ok = (opts.includeSpecial or not c.special)
        and (not opts.maxGeneration or c.gen <= opts.maxGeneration)
        and (not only or only[c.gen] == true)
        and (not opts.terrain or c.terrains[opts.terrain])
        and (not opts.habitat or c.habitats[opts.habitat])
        and (not opts.minLevel or c.hi >= opts.minLevel)
        and (not opts.maxLevel or c.lo <= opts.maxLevel)
      if ok then out[#out + 1] = describe(c) end
    end
    return out
  end

  -- One species' spawn profile, by engine id ("PIDGEY"), or nil.
  exports.profileOf = function(speciesId)
    local pool = Runtime.pool()
    local c = pool and pool.byId[speciesId]
    return c and describe(c) or nil
  end

  -- Drop cached tables (e.g. after a consumer changes something they read).
  exports.invalidate = function()
    Runtime.invalidate()
  end

  -- Shiny chains (src/chain.lua): one species beaten or caught in a row is met
  -- more, is more likely to be shiny and has better stats. This mod counts the
  -- chain and swaps the species of the encounters it rolls; a consumer that
  -- picks its own encounters (visible overworld spawns) asks here, and applies
  -- the shiny chance and perfect stats itself (they are engine-specific).
  --
  -- The current chain: { species = id, count = n }, or nil.
  exports.chain = function()
    local c = Runtime.chain
    return c and c.species and { species = c.species, count = c.count } or nil
  end
  -- For one pick on a map: the chained species when the chain makes this
  -- encounter it (rolled here; call once per pick), else nil.
  exports.chainSpeciesFor = function(mapId, terrain)
    return Runtime.chainSpeciesFor(mapId, terrain or "grass")
  end
  -- For an encounter of `species` (an id, or the engine's species number):
  -- { shiny = chance 0..1, perfectIvs = n }, or nil when it is not chained.
  exports.chainBonus = function(species)
    return Runtime.chainBonus(species)
  end
  -- A wild Pokemon fought outside a real battle counts too: result "win" /
  -- "catch" extends or starts the chain, "run" ends it.
  exports.chainRecord = function(species, result)
    Runtime.chainRecord(species, result)
  end
end
