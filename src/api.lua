-- The framework surface other mods consume, published on mod.exports.
--
--   local spawns = mod:find("modern_spawns")
--   if spawns and (spawns.exports.apiVersion or 0) >= 1 then
--     local grass = spawns.exports.tableFor("ROUTE_1", "grass")
--   end
--
-- Everything returned is a COPY: a consumer can never mutate the tables the
-- encounter hooks hand the engine. Functions answer nil while modern spawns
-- are inactive (MODERN SPAWNS off, GEN 1, or no species past #151), which
-- a consumer should read as "use the game's own tables".
--
-- API VERSIONING: apiVersion only goes up, and only when an existing field
-- changes meaning or disappears; check `>=`, never `==`.
--
-- Event: mod.modern_spawns.tables_changed { maxGeneration, seed, mode } fires
-- each time tables are (re)generated (under EVERY MAP: once per map visit).

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
    minLevel = c.lo, maxLevel = c.hi, typicalLevel = c.typ,
    rarity = c.rarity, habitats = setToList(c.habitats),
    terrains = setToList(c.terrains), special = c.special,
    profileSource = c.source,
    form = c.form, baseSpecies = c.baseSpecies, variants = deepCopy(c.variants),
  }
end

return function(deps)
  local mod, Runtime, Config = deps.mod, deps.Runtime, deps.Config
  local exports = mod.exports

  -- Added fields don't bump it (0.7.0 added drawFor / legendaryFor): test
  -- for a newer function by presence, `type(exports.drawFor) == "function"`.
  exports.apiVersion = 1

  exports.isActive = function()
    return Runtime.isActive()
  end

  -- The generation cap in force (2..9), or nil when inactive.
  exports.maxGeneration = function()
    return Runtime.effectiveGeneration()
  end

  -- The player's settings, whatever is in force.
  exports.settings = function()
    return { enabled = Config.enabled(mod), maxGeneration = Config.maxGeneration(mod),
             spawnMode = Config.spawnMode(mod), legendaries = Config.legendaries(mod) }
  end

  -- Where legendaries/mythicals may appear when LEGENDARIES is ON:
  -- { [mapId] = { grass = { {id, score, category}, ... }, water = {...} } }.
  -- Answered whatever LEGENDARIES is set to (nil only while inactive), so a
  -- consumer can show where they would be. Rates: SpawnConfig.legendary.
  exports.legendaryHomes = function()
    return deepCopy(Runtime.legendaryHomes())
  end

  -- "seeded" | "map" | "random". Under "random" there is no fixed table:
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
  exports.tableFor = function(mapId, terrain)
    return deepCopy(Runtime.tableFor(mapId, terrain or "grass"))
  end

  -- For a mod that picks species itself, once per pick (visible overworld
  -- spawns): tableFor under SEEDED / EVERY MAP, a fresh one-off draw under
  -- RANDOM, so each pick sees what that mode would roll. Same shape as tableFor.
  exports.drawFor = function(mapId, terrain)
    return deepCopy(Runtime.drawFor(mapId, terrain or "grass"))
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
  exports.explain = function(mapId, terrain)
    return deepCopy(Runtime.explain(mapId, terrain))
  end

  -- Candidate pool entries. opts (all optional): maxGeneration, terrain
  -- ("grass"|"cave"|"water"|"fish"), minLevel/maxLevel (overlap), habitat,
  -- includeSpecial (legendary/mythical are left out unless true).
  exports.candidates = function(opts)
    opts = opts or {}
    local pool = Runtime.pool()
    if not pool then return {} end
    local out = {}
    for _, c in ipairs(pool.list) do
      local ok = (opts.includeSpecial or not c.special)
        and (not opts.maxGeneration or c.gen <= opts.maxGeneration)
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
end
