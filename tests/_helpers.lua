-- Shared test helpers (the "_" prefix keeps tests/tier_runner.lua from
-- running this file as a suite).
--
-- Suites run from the gen1recomp root as
--   luajit mods/modern_spawns/tests/<name>_test.lua
-- so the mod's own directory is derived from the suite's path.

local H = {}

function H.modRoot()
  local script = (arg and arg[0]) or ""
  script = script:gsub("\\", "/")
  return script:match("^(.*)/tests/[^/]+$") or "mods/modern_spawns"
end

-- Load one of the mod's own modules straight from disk, the same way
-- main.lua's loadSibling does (mod:read + load), minus the sandbox.
function H.module(name)
  local path = H.modRoot() .. "/" .. name
  local chunk, err = loadfile(path)
  assert(chunk, "cannot load " .. path .. ": " .. tostring(err))
  return chunk()
end

-- Deterministic serialisation for equality checks between generated tables.
function H.serialize(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = tostring(k) .. "=" .. H.serialize(value[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- The Mod Manager's own option writer (src/mods/ManagerState.lua setOption),
-- driven against a loader: it writes the buckets and emits
-- mod.options_changed exactly as MODS -> Modern Spawns does. Also injects a
-- stub game as the loader's live game, so mod.game resolves headlessly.
-- Returns set(key, value) and the stub game.
function H.manager(loader, save)
  local ManagerState = require("src.mods.ManagerState")
  local game = { mods = loader, save = save or { options = {} },
                 writeOptions = function() end }
  loader.game = game
  local state = setmetatable({ game = game }, { __index = ManagerState })
  return function(key, value)
    ManagerState.setOption(state, "modern_spawns", key, value)
  end, game
end

-- A Gen 2 dataset shaped the way Game2 builds it before mods load
-- (src/core/Game2.lua), read from an imported cart: "gold" or "crystal".
-- There is no headless Gen 2 Data loader, so the modules are read directly.
function H.gen2Data(version)
  local function load(name)
    return dofile(version .. "/data/generated/" .. name .. ".lua")
  end
  return {
    pokemon = load("pokemon"), items = load("items"), moves = load("moves"),
    type_chart = load("type_chart"),
    gen2Encounters = load("encounters"), gen2Maps = load("maps"),
    gen2Constants = load("constants"), gen2Landmarks = load("landmarks"),
  }
end

-- A FireRed dataset shaped the way Game3 exposes it to mods
-- (src/core/Game3.lua _exposeModData), from the imported cart under
-- firered/data/generated/gba. The species tables live on the real
-- src.core.game3.pokemon module, as in the game.
function H.gen3Data()
  local root = "firered/data/generated/gba/"
  local function load(path) return dofile(root .. path) end
  local Json = require("src.link.Json")
  local MapCatalog = require("src.import.gba.map_catalog")
  local maps = {}
  local pipe = io.popen('ls "' .. root .. 'map_tree/maps"')
  for dir in pipe:lines() do
    local f = io.open(root .. "map_tree/maps/" .. dir .. "/header.json")
    if f then
      local ok, h = pcall(Json.decode, f:read("*a"))
      f:close()
      local id = ok and type(h) == "table"
        and (MapCatalog.mapIdFor(h.group, h.num) or MapCatalog.pretToEngine(h.id))
      if id then
        maps[id] = { id = id, name = id, mapType = h.mapType,
                     regionMapSectionId = h.regionMapSectionId }
      end
    end
  end
  pipe:close()
  local P = require("src.core.game3.pokemon")
  for field, file in pairs({ _names = "names", _types = "types", _stats = "stats",
      _speciesMeta = "meta", _abilities = "abilities", _abilityNames = "ability_names",
      _learnsets = "learnsets", _eggMoves = "egg_moves", _evolutions = "evolutions",
      _dex = "dex", _moveNames = "move_names", _national = "national" }) do
    P[field] = load("pokemon/" .. file .. ".lua")
  end
  P._byName = {}
  return {
    maps = maps, tilesets = {}, gen3Pokemon = P,
    gen3Moves = { _rom = load("pokemon/battle_moves.lua").moves },
    gen3Items = { _byId = load("items/pack.lua").items },
    gen3Encounters = load("encounters.lua"),
  }
end

-- The mod's options.lua schema rows, by key.
function H.schema()
  local rows = H.module("options.lua")
  local byKey = {}
  for _, row in ipairs(rows) do byKey[row.key] = row end
  return rows, byKey
end

-- ------------------------------------------------------------ fake world

local function mon(id, dex, types, stats, evolutions, extra)
  local record = {
    id = id, name = id, dex = dex, types = types,
    baseStats = { hp = stats[1], attack = stats[2], defense = stats[3],
                  speed = stats[4], special = stats[5] },
    evolutions = evolutions or {},
  }
  for k, v in pairs(extra or {}) do record[k] = v end
  return record
end
H.mon = mon

-- A small species roster spanning several generations, with a legendary
-- that would otherwise fit every table perfectly.
function H.species()
  return {
    mon("PIDGEY", 16, { "NORMAL", "FLYING" }, { 40, 45, 40, 56, 35 },
        { { method = "LEVEL", level = 18, species = "PIDGEOTTO" } }),
    mon("PIDGEOTTO", 17, { "NORMAL", "FLYING" }, { 63, 60, 55, 71, 50 }),
    mon("RATTATA", 19, { "NORMAL" }, { 30, 56, 35, 72, 25 }),
    mon("ZUBAT", 41, { "POISON", "FLYING" }, { 40, 45, 35, 55, 40 }),
    mon("GEODUDE", 74, { "ROCK", "GROUND" }, { 40, 80, 100, 20, 30 }),
    mon("TENTACOOL", 72, { "WATER", "POISON" }, { 40, 40, 35, 70, 100 }),
    mon("MAGIKARP", 129, { "WATER" }, { 20, 10, 55, 80, 20 }),
    mon("SENTRET", 161, { "NORMAL" }, { 35, 46, 34, 20, 40 }),
    mon("HOOTHOOT", 163, { "NORMAL", "FLYING" }, { 60, 30, 30, 50, 46 }),
    mon("MARILL", 183, { "WATER" }, { 70, 20, 50, 40, 20 }),
    mon("RAIKOU", 243, { "ELECTRIC" }, { 90, 85, 75, 115, 115 }),
    mon("STARLY", 396, { "NORMAL", "FLYING" }, { 40, 55, 30, 60, 30 }),
    mon("ROGGENROLA", 524, { "ROCK" }, { 55, 75, 85, 15, 25 }),
    mon("LECHONK", 915, { "NORMAL" }, { 54, 45, 40, 35, 35 }),
    mon("WIGLETT", 960, { "WATER" }, { 10, 55, 25, 95, 35 }),
    -- an alternate form must never enter the pool
    mon("PIDGEY_FORM", 16, { "NORMAL" }, { 40, 45, 40, 56, 35 }, nil,
        { form = "test", baseSpecies = "PIDGEY" }),
  }
end

function H.profiles()
  return {
    version = 1,
    generation = { [243] = 2 },
    special = { [243] = "legendary" },
    species = {
      [16] = { lo = 3, hi = 16, typ = 10, r = "c", h = { "route", "forest" }, t = { "grass" } },
      [17] = { lo = 15, hi = 30, typ = 22, r = "u", h = { "route" }, t = { "grass" } },
      [19] = { lo = 2, hi = 15, typ = 8, r = "c", h = { "route" }, t = { "grass" } },
      [41] = { lo = 6, hi = 30, typ = 15, r = "c", h = { "cave" }, t = { "cave", "grass" } },
      [74] = { lo = 6, hi = 25, typ = 14, r = "c", h = { "cave", "mountain" }, t = { "cave" } },
      [72] = { lo = 5, hi = 40, typ = 20, r = "c", h = { "water", "coast" }, t = { "water", "fish" } },
      [129] = { lo = 5, hi = 20, typ = 10, r = "c", h = { "water" }, t = { "fish", "water" } },
      [161] = { lo = 2, hi = 12, typ = 5, r = "c", h = { "route" }, t = { "grass" } },
      [163] = { lo = 2, hi = 14, typ = 6, r = "u", h = { "forest", "route" }, t = { "grass" } },
      [183] = { lo = 5, hi = 20, typ = 12, r = "u", h = { "water" }, t = { "water", "grass" } },
      -- the legendary fits a low-level route perfectly: it must still lose
      [243] = { lo = 2, hi = 10, typ = 5, r = "c", h = { "route" }, t = { "grass" } },
      [396] = { lo = 2, hi = 14, typ = 6, r = "c", h = { "route" }, t = { "grass" } },
      [524] = { lo = 8, hi = 25, typ = 15, r = "u", h = { "cave" }, t = { "cave" } },
      -- LECHONK / WIGLETT (Gen 9) have no profile: estimated at runtime
    },
  }
end

local LADDER = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }
H.LADDER = LADDER

local function slots(pairs_)
  local out = {}
  for i, p in ipairs(pairs_) do out[i] = { level = p[1], species = p[2] } end
  return out
end
H.slots = slots

function H.encounters()
  return {
    ROUTE_A = { grass = { rate = 25, slots = slots({
      { 3, "PIDGEY" }, { 3, "RATTATA" }, { 4, "PIDGEY" }, { 4, "RATTATA" },
      { 2, "PIDGEY" }, { 3, "RATTATA" }, { 3, "PIDGEY" }, { 4, "RATTATA" },
      { 5, "PIDGEY" }, { 5, "RATTATA" } }) } },
    ROUTE_B = { grass = { rate = 15, buckets = { 128, 200, 256 }, slots = slots({
      { 6, "PIDGEY" }, { 7, "RATTATA" }, { 8, "PIDGEOTTO" } }) } },
    CAVE_1F = { grass = { rate = 10, slots = slots({
      { 8, "ZUBAT" }, { 9, "ZUBAT" }, { 9, "GEODUDE" }, { 10, "GEODUDE" },
      { 10, "ZUBAT" }, { 11, "GEODUDE" }, { 11, "ZUBAT" }, { 12, "GEODUDE" },
      { 12, "ZUBAT" }, { 13, "GEODUDE" } }) } },
    SEA_ROUTE = { water = { rate = 5, slots = slots({
      { 5, "TENTACOOL" }, { 10, "TENTACOOL" }, { 15, "TENTACOOL" }, { 5, "TENTACOOL" },
      { 10, "TENTACOOL" }, { 15, "TENTACOOL" }, { 20, "TENTACOOL" }, { 30, "TENTACOOL" },
      { 35, "TENTACOOL" }, { 40, "TENTACOOL" } }) } },
  }
end

function H.world(opts)
  opts = opts or {}
  local encounters = opts.encounters or H.encounters()
  local superRod = opts.superRod or {
    TOWN = { { level = 15, species = "MAGIKARP" }, { level = 20, species = "TENTACOOL" } },
  }
  local maps = opts.maps or {
    ROUTE_A = { tileset = "OVERWORLD" }, ROUTE_B = { tileset = "OVERWORLD" },
    CAVE_1F = { tileset = "CAVERN" }, SEA_ROUTE = { tileset = "OVERWORLD" },
    TOWN = { tileset = "OVERWORLD" },
  }
  local order = opts.order or { "ROUTE_A", "ROUTE_B", "CAVE_1F", "SEA_ROUTE", "TOWN" }
  local species = opts.species or H.species()
  -- a fake mod.content in front of the real Gen 1 adapter, so these suites
  -- exercise the adapter exactly as the game drives it
  local registries = {
    encounters = encounters, maps = maps,
    field = { superRod = superRod },
    constants = { mapOrder = order, encounterBuckets = LADDER },
  }
  local reg = {
    get = function(name, id) return (registries[name] or {})[id] end,
    ids = function(name)
      local ids = {}
      for id in pairs(registries[name] or {}) do ids[#ids + 1] = id end
      table.sort(ids)
      return ids
    end,
  }
  local world = H.module("src/adapters/gen1.lua")(reg, H.module("src/map_context.lua"))
  world.species = function() return species end
  world.evolutionOf = opts.evolutionOf
  return world
end

return H
