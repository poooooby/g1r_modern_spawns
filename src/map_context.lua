-- What kind of place a map is, read from the runtime alone.
--
-- No per-map data ships with this mod: a map's habitat tags come from its
-- tileset (data.maps[id].tileset), a handful of keyword rules on the map id,
-- and the terrain being rolled. The tags use the same vocabulary the
-- generated species profiles use (forest, cave, water, coast, mountain,
-- route, grassland, desert, snow, ruins, urban), so matching is a set test.
-- `types` are soft preferences for the map (GHOST in a tower, ELECTRIC in a
-- power plant) scored in the generator, never filters.

local MapContext = {}

local TILESET = {
  OVERWORLD = { "route", "grassland" },
  FOREST = { "forest", "grassland" },
  CAVERN = { "cave" },
  CEMETERY = { "ruins" },
  FACILITY = { "urban" },
  MANSION = { "urban", "ruins" },
  PLATEAU = { "mountain", "route" },
  SHIP = { "coast", "urban" },
  SHIP_PORT = { "coast", "urban" },
  UNDERGROUND = { "cave", "urban" },
  -- Gold / Silver / Crystal tilesets
  TILESET_JOHTO = { "route", "grassland" },
  TILESET_JOHTO_MODERN = { "route", "grassland" },
  TILESET_KANTO = { "route", "grassland" },
  TILESET_PARK = { "grassland", "forest" },
  TILESET_FOREST = { "forest", "grassland" },
  TILESET_CAVE = { "cave" },
  TILESET_DARK_CAVE = { "cave" },
  TILESET_ICE_PATH = { "cave", "snow" },
  TILESET_TOWER = { "ruins" },
  TILESET_RUINS_OF_ALPH = { "ruins" },
}

-- Gen 2 map headers also carry an environment; it fills in whatever the
-- tileset did not say.
local ENVIRONMENT = {
  ROUTE = { "route", "grassland" },
  TOWN = { "urban", "route" },
  CAVE = { "cave" },
  DUNGEON = { "ruins" },
}

-- Keyword rules on the map id: { pattern, habitats, types }. First the
-- specific places, then the broad ones; every matching rule applies.
local KEYWORDS = {
  { "SEAFOAM", { "cave", "water", "snow", "coast" }, { "ICE", "WATER" } },
  { "POWER_PLANT", { "urban" }, { "ELECTRIC", "STEEL" } },
  { "POKEMON_TOWER", { "ruins" }, { "GHOST" } },
  { "MANSION", { "urban", "ruins" }, { "FIRE", "POISON" } },
  { "SAFARI", { "grassland", "forest" }, nil },
  { "MT_MOON", { "cave", "mountain" }, { "ROCK", "FAIRY" } },
  { "ROCK_TUNNEL", { "cave", "mountain" }, { "ROCK", "GROUND" } },
  { "VICTORY_ROAD", { "cave", "mountain" }, { "ROCK", "FIGHTING" } },
  { "DIGLETT", { "cave" }, { "GROUND" } },
  { "CERULEAN_CAVE", { "cave" }, { "PSYCHIC" } },
  { "FOREST", { "forest" }, { "BUG", "GRASS" } },
  -- Johto (Gold / Silver / Crystal)
  { "SPROUT_TOWER", { "ruins" }, { "GHOST", "PSYCHIC" } },
  { "BURNED_TOWER", { "ruins" }, { "FIRE", "GHOST" } },
  { "TIN_TOWER", { "ruins" }, { "FIRE", "FLYING" } },
  { "RUINS_OF_ALPH", { "ruins" }, { "PSYCHIC", "ROCK" } },
  { "SLOWPOKE_WELL", { "cave", "water" }, { "WATER", "PSYCHIC" } },
  { "UNION_CAVE", { "cave", "water" }, { "ROCK", "WATER" } },
  { "DARK_CAVE", { "cave", "mountain" }, { "DARK", "ROCK" } },
  { "MOUNT_MORTAR", { "cave", "mountain" }, { "FIGHTING", "ROCK" } },
  { "ICE_PATH", { "cave", "snow" }, { "ICE" } },
  { "WHIRL_ISLAND", { "cave", "water", "coast" }, { "WATER", "ICE" } },
  { "LAKE_OF_RAGE", { "water", "grassland" }, { "WATER", "DRAGON" } },
  { "TOHJO_FALLS", { "cave", "water" }, { "WATER" } },
  { "MOUNT_SILVER", { "cave", "mountain", "snow" }, { "ICE", "STEEL", "DRAGON" } },
  { "SILVER_CAVE", { "cave", "mountain" }, { "ICE", "STEEL", "DRAGON" } },
  { "NATIONAL_PARK", { "grassland", "forest" }, { "BUG" } },
  { "DRAGONS_DEN", { "cave", "water" }, { "DRAGON" } },
}

-- Sea routes. A map id is the only runtime handle on "this route is open
-- water"; the engine's own tables agree (their water table carries the
-- encounters). Kanto's in both generations, Johto's 40/41 in Gen 2.
local SEA_ROUTES = { ROUTE_19 = true, ROUTE_20 = true, ROUTE_21 = true,
                     ROUTE_40 = true, ROUTE_41 = true }

local function addAll(set, list)
  for _, value in ipairs(list or {}) do set[value] = true end
end

-- terrain: "grass" | "cave" | "water" | "fish"
-- mapInfo: the runtime map record (only .tileset is read), may be nil
function MapContext.describe(mapId, mapInfo, terrain)
  local habitats, types = {}, {}
  local tileset = type(mapInfo) == "table" and mapInfo.tileset or nil
  addAll(habitats, TILESET[tileset])
  local environment = type(mapInfo) == "table" and mapInfo.environment or nil
  if next(habitats) == nil then addAll(habitats, ENVIRONMENT[environment]) end
  local id = tostring(mapId or "")
  for _, rule in ipairs(KEYWORDS) do
    if id:find(rule[1], 1, true) then
      addAll(habitats, rule[2])
      addAll(types, rule[3])
    end
  end
  if SEA_ROUTES[id] then addAll(habitats, { "coast", "water" }) end
  if terrain == "water" or terrain == "fish" then
    addAll(habitats, { "water", "coast" })
    types.WATER = true
  end
  if next(habitats) == nil then habitats.route = true end
  return { mapId = id, tileset = tileset, terrain = terrain,
           habitats = habitats, types = types }
end

-- The terrain a map's grass table really represents: cave floors roll the
-- same table the engine calls "grass" (Gen 1 OverworldController
-- onStepComplete; Gen 2 CAVE/DUNGEON environments encounter on every tile).
-- Ilex Forest is a CAVE-environment map with a forest floor.
function MapContext.landTerrain(mapInfo)
  local tileset = type(mapInfo) == "table" and mapInfo.tileset or nil
  local environment = type(mapInfo) == "table" and mapInfo.environment or nil
  if tileset == "CAVERN" or tileset == "UNDERGROUND" then return "cave" end
  if tileset == "TILESET_FOREST" then return "grass" end
  if environment == "CAVE" or environment == "DUNGEON" then return "cave" end
  return "grass"
end

return MapContext
