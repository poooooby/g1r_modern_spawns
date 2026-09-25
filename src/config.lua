-- Option access and generator tuning.
--
-- Two player-facing options (options.lua is the schema):
--   enabled         "on" | "off"       MODERN SPAWNS
--   max_generation  "1" .. "9"         GENERATIONS (Gen 1 only .. Gen 1-9)
-- "off" and Gen 1 both leave the runtime tables exactly as the game has them.
--
-- SpawnConfig holds every tuning number the generator uses, so balancing is
-- one table rather than magic numbers spread through generator.lua. These are
-- starting points, not constants the rest of the code relies on.

local Config = {}

Config.MOD_ID = "modern_spawns"
Config.DEFAULT_ENABLED = "on"
Config.DEFAULT_MAX_GENERATION = "9"
Config.MAX_GENERATION = 9

-- National dex number that closes each generation.
Config.GENERATION_DEX_END = { 151, 251, 386, 493, 649, 721, 809, 905, 1025 }

function Config.generationOfDex(dex)
  dex = tonumber(dex)
  if not dex then return nil end
  for gen, last in ipairs(Config.GENERATION_DEX_END) do
    if dex <= last then return gen end
  end
  return nil
end

Config.SpawnConfig = {
  -- how many preceding maps (in the game's own map order) count as "recent"
  history_window_maps = 3,
  -- a candidate this far outside a slot's level window drops out of the
  -- first (strict) candidate tier
  strict_level_distance = 10,
  -- only the best N scorers of a role are drawn from, weighted by score
  top_candidates = 8,
  -- how a role's winner is drawn, per SPAWN MODE: the best `top` scorers,
  -- weighted by (score above the worst of them + 1) ^ `power`. SEEDED favors
  -- the best fit; the modes that redraw spread wider so redraws differ.
  -- LEGENDARIES ON: a hosted legendary replaces 1 in `chance` encounters on
  -- its home maps (mythicals 1 in `mythical_chance`). Each species gets its
  -- best `homes_per_species` maps whose levels are within `level_tolerance`
  -- of its own and whose habitat or theme fits it. Once owned, it stops.
  legendary = {
    chance = 1024,
    mythical_chance = 2048,
    homes_per_species = 2,
    level_tolerance = 10,
    -- a host map's table must reach this level: no legendary on early routes
    min_level = 30,
    -- species per map table, so homes spread out instead of every
    -- legendary crowding into the last high-level cave
    max_per_map = 3,
    -- extra score for a map whose theme matches a type (Electric in the
    -- Power Plant, Ice in Seafoam): the strongest "belongs here" signal
    theme_bonus = 40,
  },
  selection = {
    seeded = { top = 8, power = 2 },
    map = { top = 12, power = 1 },
    random = { top = 16, power = 1 },
  },
  -- a slot this many levels below a species' evolve level is implausible
  evolve_tolerance = 3,

  scoring = {
    level_overlap = 30,
    level_distance = -2,      -- per level outside the window
    typical_distance = -0.5,  -- per level between typical level and slot mid
    underleveled = -60,       -- slot is below the species' evolve level
    overleveled = -10,        -- slot is far above a base form's evolve level
    terrain_match = 20,
    terrain_partial = 8,      -- cave table, grass-only species
    habitat_match = 20,
    habitat_extra = 4,        -- per additional shared habitat
    type_match = 12,          -- per type shared with the replaced species
    map_type = 10,            -- type the map favors (GHOST in a tower...)
    rarity_match = 5,
    rarity_mismatch = -15,    -- two or more rarity steps apart
    new_species = 10,
    new_generation = 8,
    same_area = 15,           -- species already on another floor of this place
    -- an estimated profile (no PokéAPI wild data) is a guess; observed data
    -- should win a close call
    estimated_profile = -12,
    -- Gen 2 only: a night-only role given a species the game only shows by
    -- day (or the reverse), and a night role given a night species
    time_mismatch = -30,
    time_match = 12,

    same_species_current = -80,
    same_family_current = -40,
    same_species_previous = -100,
    same_species_recent = -70,
    same_family_recent = -45,
    generation_overrepresented = -10,
  },
}

-- ------------------------------------------------------------- option reads

local function get(mod, key, default)
  local ok, value = pcall(function() return mod.options:get(key) end)
  if not ok or value == nil then return default end
  return value
end

function Config.enabled(mod)
  local value = get(mod, "enabled", Config.DEFAULT_ENABLED)
  -- tolerate a boolean left behind by a hand-edited options file
  return value == "on" or value == true
end

-- SPAWN MODE:
--   "seeded"  one roster per map for the whole playthrough
--   "map"     a new roster each time a map is entered (EVERY MAP)
--   "random"  a new species on every encounter
-- All three draw from the same per-save seed, so switching modes never
-- changes it; only REROLL SEED or typing a seed does.
Config.SPAWN_MODES = { "seeded", "map", "random" }
Config.SPAWN_MODE_LABELS = { seeded = "SEEDED", map = "EVERY MAP", random = "RANDOM" }
Config.DEFAULT_SPAWN_MODE = "seeded"

function Config.spawnMode(mod)
  local value = get(mod, "spawn_mode", Config.DEFAULT_SPAWN_MODE)
  if Config.SPAWN_MODE_LABELS[value] then return value end
  return Config.DEFAULT_SPAWN_MODE
end

-- Seeds are short letter codes: the Gen 1 naming screen has no digits, and a
-- word is easier to share than a number. Any string works (it is hashed);
-- a numeric seed from an older version still reads as its digits.
Config.SEED_MAX_LEN = 10
Config.SEED_LENGTH = 8
local SEED_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ" -- no I/O: they read as 1/0

function Config.normalizeSeed(value)
  if value == nil then return nil end
  local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  return text
end

-- A fresh random seed code. `random(lo, hi)` is an integer source.
function Config.newSeed(random)
  local out = {}
  for i = 1, Config.SEED_LENGTH do
    local k = random(1, #SEED_ALPHABET)
    out[i] = SEED_ALPHABET:sub(k, k)
  end
  return table.concat(out)
end

-- LEGENDARIES (default OFF): rare hosted legendary/mythical encounters.
function Config.legendaries(mod)
  local value = get(mod, "legendaries", "off")
  return value == "on" or value == true
end

function Config.maxGeneration(mod)
  local value = tonumber(get(mod, "max_generation", Config.DEFAULT_MAX_GENERATION))
  if not value then return tonumber(Config.DEFAULT_MAX_GENERATION) end
  value = math.floor(value)
  if value < 1 then return 1 end
  if value > Config.MAX_GENERATION then return Config.MAX_GENERATION end
  return value
end

-- ------------------------------------------------------------ option writes

-- The mod API has mod.options:define/get but no :set. The Mod Manager
-- (src/mods/ManagerState.lua setOption) writes save.options.modOptions and
-- the loader's modOptions (game.mods), then persists; an in-game row mirrors
-- those same buckets. mod.options_changed cannot be emitted by a mod, so the
-- caller runs its own change handler afterwards.
function Config.write(mod, game, key, value)
  local id = mod.id or Config.MOD_ID
  local wrote = false
  local function into(bucket)
    if type(bucket) ~= "table" then return end
    bucket[id] = bucket[id] or {}
    bucket[id][key] = value
    wrote = true
  end
  if game and game.save then
    game.save.options = game.save.options or {}
    game.save.options.modOptions = game.save.options.modOptions or {}
    into(game.save.options.modOptions)
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    into(loader.modOptions)
  end
  -- persist the way the running game does: Gen 1's Game:writeOptions,
  -- Gold's Game2:persistOptions
  if game and type(game.writeOptions) == "function" then
    pcall(game.writeOptions, game)
  elseif game and type(game.persistOptions) == "function" then
    pcall(game.persistOptions, game)
  end
  return wrote
end

return Config
