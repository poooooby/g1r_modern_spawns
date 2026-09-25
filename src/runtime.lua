-- Runtime wiring: the per-save seed, the generated-table cache and the three
-- encounter hooks.
--
-- Everything is read from the running game through mod.content (the merged,
-- frozen registries): encounter tables, Super Rod groups, map order, map
-- tilesets and the species registry. Nothing is written back into game data;
-- the redistributed tables are handed to the engine per roll through the
-- hooks, so switching MODERN SPAWNS off (or picking GEN 1) is immediate and
-- leaves the original tables exactly as the game loaded them.
--
-- Hook priority: every wrapper sits INNERMOST (lowest priority), right next
-- to the engine's own roll. An outer mod can still suppress an encounter
-- (return nil) or post-process the result (encounter.species); the table the
-- engine finally rolls on is this mod's while it is active.
--
-- SPAWN MODE decides how often a map's roster is drawn, always from the one
-- per-save seed:
--   seeded  every map generated once, in map order, for the playthrough
--   map     the entered map is generated again on every entry (nonce =
--           its visit count this session), with a session-long history
--   random  the engine rolls the game's own table; encounter.species then
--           swaps the rolled slot's species for a fresh draw (nonce = the
--           session's encounter count)

return function(deps)
  local mod, Config, Generator, SpeciesPool, MapContext, Rng =
    deps.mod, deps.Config, deps.Generator, deps.SpeciesPool, deps.MapContext, deps.Rng
  local profiles = deps.profiles
  local log = mod.log

  local HOOK_PRIORITY = -100
  local SEED_KEY = "seed"
  local DATA_VERSION = profiles and profiles.version or 0

  local Runtime = {}
  local pool, poolMaxGen
  local cache = { key = nil, tables = nil }       -- seeded: every map
  local visits = {}                                -- map mode: entries per map
  local visitTables = {}                           -- map mode: [mapId] = { key, result }
  local memory = Generator.newMemory()             -- map/random: session history
  local encounterCount = 0                         -- random: draws this session
  local warned = {}

  local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    log:warn(fmt, ...)
  end

  -- ------------------------------------------------------------- world

  local function registryGet(name, id)
    local registry = mod.content and mod.content[name]
    if not registry then return nil end
    local ok, value = pcall(function() return registry:get(id) end)
    if ok then return value end
    return nil
  end

  local function registryIds(name)
    local registry = mod.content and mod.content[name]
    if not registry then return {} end
    local ok, result = pcall(function() return registry:each() end)
    if not ok then return {} end
    if type(result) == "function" then
      local ids = {}
      for id in result do ids[#ids + 1] = id end
      return ids
    end
    return type(result) == "table" and result or {}
  end

  -- The species mod for this game: national_dex (Red..Crystal),
  -- national_dex_gen3 or 1025Dex (FireRed). Read for evolutionsOf.
  local function nationalDexExports()
    for _, id in ipairs({ "national_dex", "national_dex_gen3", "1025dex" }) do
      local ok, found = pcall(function() return mod:find(id) end)
      if ok and type(found) == "table" and type(found.exports) == "table"
        and type(found.exports.evolutionsOf) == "function" then
        return found.exports
      end
    end
    return nil
  end

  -- The game's shapes (tables, hooks, save) live in an adapter per
  -- generation: src/adapters/gen1.lua (Red/Blue/Yellow) and gen2.lua
  -- (Gold/Silver/Crystal). Everything below them is shared.
  local generation = tonumber(mod.generation) or 1
  local makeAdapter = deps.adapters[generation] or deps.adapters[1]
  local world = makeAdapter({ get = registryGet, ids = registryIds }, MapContext)

  function world.species()
    local out = {}
    for _, id in ipairs(registryIds("pokemon")) do
      local record = registryGet("pokemon", id)
      if type(record) == "table" then
        if record.id == nil then
          -- registries key by id; a record may omit its own
          local copy = {}
          for k, v in pairs(record) do copy[k] = v end
          copy.id = id
          record = copy
        end
        out[#out + 1] = record
      end
    end
    return out
  end

  function world.hasSpecies(id)
    return type(id) == "string" and registryGet("pokemon", id) ~= nil
  end

  -- Whether the loaded save owns a species (the adapter knows where each
  -- generation records it). mod.game is re-read on every touch (the save is
  -- replaced on NEW GAME / CONTINUE). Unknown -- no game or no save -- reads
  -- as not owned.
  local ownedIn = world.owned -- the adapter's owned(game, id)
  function world.owned(id)
    local ok, owned = pcall(function() return ownedIn(mod.game, id) end)
    return ok and owned == true
  end

  Runtime.world = world

  -- -------------------------------------------------------------- pool

  function Runtime.pool()
    if pool then return pool end
    local dex = nationalDexExports()
    world.evolutionOf = dex and type(dex.evolutionsOf) == "function"
      and dex.evolutionsOf or nil
    local ok, result = pcall(SpeciesPool.build, world, profiles, Config.generationOfDex)
    if not ok then
      warnOnce("pool", "candidate pool failed to build (%s) -- wild tables "
        .. "stay as the game has them", tostring(result))
      return nil
    end
    pool = result
    poolMaxGen = 1
    for _, c in ipairs(pool.list) do
      if c.gen > poolMaxGen then poolMaxGen = c.gen end
    end
    return pool
  end

  -- ------------------------------------------------------------ seed

  local function randomInt(lo, hi)
    local ok, value = pcall(function() return love.math.random(lo, hi) end)
    if ok and tonumber(value) then return value end
    return lo + (os.time() + math.floor(os.clock() * 1e6)) % (hi - lo + 1)
  end

  -- Drops every generated table and the session history, so the next roll
  -- draws from the current seed/settings. The seed itself is untouched.
  local homesCache = { key = nil, homes = nil }   -- legendary homes

  function Runtime.invalidate()
    cache.key, cache.tables = nil, nil
    visitTables = {}
    memory = Generator.newMemory()
    homesCache.key, homesCache.homes = nil, nil
  end

  -- The Mod Manager's SEED row shows the `seed` OPTION, which is global,
  -- while the real seed lives in the save. Mirror the save's seed into the
  -- option whenever it is created or changes, so the row always reads the
  -- loaded save's seed. Config.write needs the live game (mod.game) and
  -- raises no event, so this never loops back into the change handler.
  local function syncSeedOption(seed)
    pcall(function() Config.write(mod, mod.game, "seed", seed) end)
  end

  -- The per-save seed as a string. A save that has none gets one; a numeric
  -- seed written by 0.1.0 reads back as its digits and hashes identically.
  function Runtime.seed()
    local seed = Config.normalizeSeed(mod.save:get(SEED_KEY))
    if seed then return seed end
    seed = Config.newSeed(randomInt)
    mod.save:set(SEED_KEY, seed)
    syncSeedOption(seed)
    return seed
  end

  -- Replace the save's seed (typed by the player, or from another mod).
  -- Returns the stored seed, or nil for an empty value.
  function Runtime.setSeed(value)
    local seed = Config.normalizeSeed(value)
    if not seed then return nil end
    seed = seed:sub(1, Config.SEED_MAX_LEN)
    mod.save:set(SEED_KEY, seed)
    Runtime.invalidate()
    syncSeedOption(seed)
    return seed
  end

  function Runtime.rerollSeed()
    local current, seed = Runtime.seed(), nil
    repeat seed = Config.newSeed(randomInt) until seed ~= current
    return Runtime.setSeed(seed)
  end

  -- --------------------------------------------------------- activity

  -- The generation cap actually in force: nil means "leave the runtime
  -- tables alone" (MODERN SPAWNS off, GEN 1, or nothing past #151 exists).
  function Runtime.effectiveGeneration()
    if not Config.enabled(mod) then return nil end
    local cap = Config.maxGeneration(mod)
    if cap <= 1 then return nil end
    local p = Runtime.pool()
    if not p then return nil end
    if poolMaxGen <= 1 then
      warnOnce("no_modern_species", "no species past #151 are registered -- "
        .. "turn national_dex's NATIONAL DEX option ON for modern spawns; "
        .. "wild tables stay as the game has them until then")
      return nil
    end
    return math.min(cap, poolMaxGen)
  end

  function Runtime.isActive()
    return Runtime.effectiveGeneration() ~= nil
  end

  function Runtime.spawnMode()
    return Config.spawnMode(mod)
  end

  local function context(gen, seed)
    return {
      world = world, pool = Runtime.pool(), seed = seed, maxGen = gen,
      config = Config.SpawnConfig, dataVersion = DATA_VERSION,
      MapContext = MapContext, Rng = Rng,
      selection = Config.SpawnConfig.selection[Config.spawnMode(mod)],
    }
  end

  local function announce(gen, seed)
    pcall(function()
      mod.events:emit("mod." .. mod.id .. ".tables_changed",
        { maxGeneration = gen, seed = seed, mode = Config.spawnMode(mod) })
    end)
  end

  -- SEEDED: every map, generated once per (seed, cap, data version).
  function Runtime.tables()
    local gen = Runtime.effectiveGeneration()
    if not gen then return nil end
    local seed = Runtime.seed()
    local key = table.concat({ seed, gen, DATA_VERSION }, ":")
    if cache.key == key then return cache.tables end
    local ok, result = pcall(Generator.buildAll, context(gen, seed))
    if not ok then
      warnOnce("generate", "table generation failed (%s) -- wild tables stay "
        .. "as the game has them", tostring(result))
      return nil
    end
    cache.key, cache.tables = key, result
    announce(gen, seed)
    return result
  end

  -- EVERY MAP: the map as generated for its current visit.
  local function visitEntry(mapId, gen, seed)
    local visit = visits[mapId] or 0
    local key = table.concat({ seed, gen, DATA_VERSION, visit }, ":")
    local held = visitTables[mapId]
    if held and held.key == key then return held.result end
    local ok, result = pcall(Generator.buildMap, context(gen, seed), mapId,
                             memory, "visit:" .. visit)
    if not ok then
      warnOnce("generate", "table generation failed (%s) -- wild tables stay "
        .. "as the game has them", tostring(result))
      return nil
    end
    visitTables[mapId] = { key = key, result = result }
    announce(gen, seed)
    return result
  end

  -- The fixed generated entry for a map under the current mode, or nil
  -- (inactive, no wild data, or RANDOM, which has no fixed table).
  local function entryFor(mapId)
    local gen = Runtime.effectiveGeneration()
    if not gen or type(mapId) ~= "string" then return nil end
    local mode = Config.spawnMode(mod)
    if mode == "random" then return nil end
    if mode == "map" then return visitEntry(mapId, gen, Runtime.seed()) end
    local tables = Runtime.tables()
    return tables and tables[mapId]
  end

  -- The generated table kind an API/preview terrain refers to. Fishing is
  -- "superRod" on Gen 1 and the Super Rod's "fish.super" on Gen 2.
  local function kindOf(terrain)
    if world.kindOfTerrain then
      local kind = world.kindOfTerrain(terrain)
      if kind then return kind end
    end
    if terrain == "water" then return "water" end
    if terrain == "superRod" or terrain == "fish" then
      return world.generation == 2 and "fish.super" or "superRod"
    end
    if terrain == "fish.good" or terrain == "fish.super" then return terrain end
    return "grass" -- grass and indoor (cave floors) share the grass table
  end

  -- A generated table (generator shape), only when every species in it is
  -- registered (the engine's wild-battle setup has no guard for an unknown id).
  local function checked(def)
    if type(def) ~= "table" or type(def.slots) ~= "table" then return nil end
    for _, slot in ipairs(def.slots) do
      if not world.hasSpecies(slot.species) then return nil end
    end
    return def
  end

  local function generated(mapId, kind)
    local entry = entryFor(mapId)
    return entry and checked(entry[kind]) or nil
  end

  -- The running game's own shape of a generated table (Gen 1 { rate, slots,
  -- buckets? } or a Super Rod list; Gen 2 grass { rates, slots = {MORN,
  -- DAY, NITE} }, water { rate, slots }, fish rows).
  function Runtime.tableFor(mapId, terrain)
    local kind = kindOf(terrain)
    local def = generated(mapId, kind)
    return def and world.assemble(mapId, kind, def) or nil
  end

  function Runtime.explain(mapId, terrain)
    local entry = entryFor(mapId)
    return entry and entry.explain[kindOf(terrain)] or nil
  end

  -- RANDOM: a one-off generation of the map for this draw only; it is not
  -- remembered as a visit, so it never shifts another map's history.
  local function randomDraw(mapId)
    local gen = Runtime.effectiveGeneration()
    if not gen or Config.spawnMode(mod) ~= "random" then return nil end
    encounterCount = encounterCount + 1
    local ok, result = pcall(Generator.buildMap, context(gen, Runtime.seed()),
                             mapId, memory, "encounter:" .. encounterCount, false)
    if ok then return result end
    warnOnce("generate", "table generation failed (%s) -- wild encounters stay "
      .. "as the game has them", tostring(result))
    return nil
  end

  -- RANDOM: the species a fresh draw puts in the slot the engine just rolled
  -- (the adapter maps the roll back to a slot of the game's own table), or nil.
  local function randomSpecies(mapId, kind, ctx, rolled)
    local index = world.slotIndex(mapId, kind, ctx, rolled)
    if not index then return nil end
    local draw = randomDraw(mapId)
    local fresh = draw and checked(draw[kind])
    return fresh and fresh.slots[index] and fresh.slots[index].species or nil
  end

  -- -------------------------------------------------------- legendaries

  -- Home maps for every legendary/mythical under the current cap, or nil
  -- when inactive. Independent of seed and SPAWN MODE.
  function Runtime.legendaryHomes()
    local gen = Runtime.effectiveGeneration()
    if not gen then return nil end
    local key = gen .. ":" .. DATA_VERSION
    if homesCache.key == key then return homesCache.homes end
    local ok, homes = pcall(Generator.legendaryHomes, context(gen, Runtime.seed()))
    if not ok then
      warnOnce("legendary", "legendary homes failed to build (%s) -- no "
        .. "legendary encounters this session", tostring(homes))
      return nil
    end
    homesCache.key, homesCache.homes = key, homes
    return homes
  end

  -- An integer source for the rare roll: the engine's own encounter RNG when
  -- the hook got one (love.math.random), else a seeded fallback.
  local fallbackRng
  local function rollInt(ctx, lo, hi)
    if world.useEngineRng ~= false and ctx and type(ctx.rng) == "function" then
      return ctx.rng(lo, hi)
    end
    fallbackRng = fallbackRng or Rng.new(Rng.hash(Runtime.seed(), "legendary"))
    return fallbackRng:int(lo, hi)
  end

  -- A hosted legendary (1 in `chance`) or mythical (1 in `mythical_chance`)
  -- for this encounter, or nil. Owned and unregistered species never appear.
  local function legendaryFor(ctx, kind)
    if not Config.legendaries(mod) then return nil end
    local homes = Runtime.legendaryHomes()
    local byKind = homes and ctx and homes[ctx.mapId]
    local hosts = byKind and byKind[kind]
    if not hosts then return nil end
    local rules = Config.SpawnConfig.legendary
    for _, category in ipairs({ "legendary", "mythical" }) do
      local pick = {}
      for _, host in ipairs(hosts) do
        if host.category == category and world.hasSpecies(host.id)
          and not world.owned(host.id) then
          pick[#pick + 1] = host
        end
      end
      local chance = category == "mythical" and rules.mythical_chance or rules.chance
      if #pick > 0 and rollInt(ctx, 1, chance) == 1 then
        return pick[rollInt(ctx, 1, #pick)].id
      end
    end
    return nil
  end

  -- ------------------------------------------------------------- hooks

  -- The encounter handed back with a new species, in the shape the running
  -- engine takes it (Gen 3: a numeric slot; see the adapter).
  local function withSpecies(out, species)
    if world.withSpecies then return world.withSpecies(out, species) end
    local copy = {}
    for k, v in pairs(out) do copy[k] = v end
    copy.species = species
    return copy
  end

  -- The last wild encounter this mod decided ({ mapId, species, level }),
  -- for compat layers that must tell our encounters from anyone else's.
  Runtime.lastEncounter = nil
  local function decided(ctx, out)
    if type(out) == "table" then
      Runtime.lastEncounter = { mapId = ctx and ctx.mapId, species = out.species,
                                speciesId = out.speciesId, level = out.level }
    end
    return out
  end

  function Runtime.install()
    -- The generated table replaces the game's for this roll; the adapter
    -- knows what the engine pipes here (Gen 1 a per-map def, Gen 2 the whole
    -- kind-first table) and which rolls are this mod's to change.
    mod.hooks:wrap("encounter.roll", function(nextFn, value, ctx)
      local ok, replaced = pcall(function()
        local kind = world.rollKind(ctx)
        local def = kind and generated(ctx.mapId, kind)
        return def and world.rollValue(value, ctx, kind,
                                       world.assemble(ctx.mapId, kind, def))
      end)
      if ok and replaced ~= nil then return nextFn(replaced, ctx) end
      return nextFn(value, ctx)
    end, HOOK_PRIORITY)

    -- After the engine's own roll picked the slot (so rate, slot odds and
    -- level stay the game's): first the rare LEGENDARIES roll, then RANDOM's
    -- fresh draw.
    mod.hooks:wrap("encounter.species", function(nextFn, enc, ctx)
      local out = nextFn(enc, ctx)
      if type(out) ~= "table" or not ctx then return out end
      local kind = world.rollKind(ctx)
      if not kind then return out end
      if not Runtime.isActive() then return out end
      local okL, legend = pcall(legendaryFor, ctx, kind)
      if okL and legend then
        local swapped = withSpecies(out, legend)
        if swapped then return decided(ctx, swapped) end
      end
      if Config.spawnMode(mod) == "random" then
        local ok, species = pcall(randomSpecies, ctx.mapId, kind, ctx, out)
        if ok and species then
          local swapped = withSpecies(out, species)
          if swapped then return decided(ctx, swapped) end
        end
        return decided(ctx, out)
      end
      -- Engines whose roll ignores the table handed to `next` (Gen 3): map
      -- the slot the engine rolled to its generated species now.
      if world.substituteAfterRoll then
        local ok, species = pcall(function()
          local index = world.slotIndex(ctx.mapId, kind, ctx, out)
          local def = index and generated(ctx.mapId, kind)
          return def and def.slots[index] and def.slots[index].species
        end)
        if ok and species then
          local swapped = withSpecies(out, species)
          if swapped then return decided(ctx, swapped) end
        end
      end
      return decided(ctx, out)
    end, HOOK_PRIORITY)

    -- Rods with per-map data (Gen 1: the Super Rod; Gen 2: Good and Super).
    -- A map with no group keeps "Not even a nibble!". Extra arguments (Gen
    -- 2's time-of-day ctx) are always forwarded.
    mod.hooks:wrap("encounter.fishing", function(nextFn, rod, mapId, candidates, ...)
      local extra = select(1, ...)
      local ok, replaced = pcall(function()
        local kind = world.fishingKind(rod, mapId, candidates, extra)
        if not kind then return nil end
        local def
        if Config.spawnMode(mod) == "random" then
          local draw = randomDraw(mapId)
          def = draw and checked(draw[kind])
        else
          def = generated(mapId, kind)
        end
        return def and world.fishingValue(candidates, kind,
                                          world.assemble(mapId, kind, def))
      end)
      if ok and replaced ~= nil then return nextFn(rod, mapId, replaced, ...) end
      return nextFn(rod, mapId, candidates, ...)
    end, HOOK_PRIORITY)

    -- Preview (mod.world:effectiveEncounters) reads what the roll will use.
    -- RANDOM has no fixed table, so its preview is the game's own odds.
    mod.hooks:wrap("encounter.table", function(nextFn, dist, ctx)
      local result = nextFn(dist, ctx)
      local ok, preview = pcall(function()
        local kind = kindOf(ctx and ctx.terrain)
        local def = ctx and generated(ctx.mapId, kind)
        return def and world.distribution(world.assemble(ctx.mapId, kind, def), kind)
      end)
      if ok and preview then return preview end
      return result
    end, HOOK_PRIORITY)

    -- EVERY MAP: each entry is a new visit, so the map is drawn again.
    mod.events:on("map.entered", function(ev)
      local mapId = type(ev) == "table" and ev.mapId or nil
      if type(mapId) == "string" then
        visits[mapId] = (visits[mapId] or 0) + 1
        visitTables[mapId] = nil
      end
    end)

    -- A seed typed or rerolled in the Mod Manager applies to the loaded save
    -- at once, and is also held for the next NEW GAME: typed at the title
    -- screen, it is the seed that game starts with. CONTINUE-ing an existing
    -- save keeps that save's own seed.
    local pendingSeed

    mod.events:on("save.created", function()
      Runtime.invalidate()
      if pendingSeed then Runtime.setSeed(pendingSeed) end
      pendingSeed = nil
      syncSeedOption(Runtime.seed())
    end)
    mod.events:on("save.loaded", function()
      Runtime.invalidate()
      pendingSeed = nil
      syncSeedOption(Runtime.seed())
    end)
    mod.events:on("checkpoint.restored", function()
      Runtime.invalidate()
      syncSeedOption(Runtime.seed())
    end)

    mod.events:on("mod.options_changed", function(ev)
      if type(ev) ~= "table" or ev.mod ~= mod.id then return end
      Runtime.invalidate()
      if ev.key == "seed" then
        local seed = Runtime.setSeed(ev.value)
        if seed then
          pendingSeed = seed
        else
          -- empty text or RESET DEFAULTS: keep the seed, restore the row
          syncSeedOption(Runtime.seed())
        end
      elseif ev.key == "reroll_seed" then
        if ev.value == "reroll" then pendingSeed = Runtime.rerollSeed() end
        -- an action, not a setting: the row always rests on "-"
        pcall(function() Config.write(mod, mod.game, "reroll_seed", "idle") end)
      end
    end)
  end

  return Runtime
end
