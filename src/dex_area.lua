-- The Gen 3 Pokedex AREA page, answered from the generated tables.
--
-- The engine builds that page from the import cache's encounter file on disk:
-- it never reads game.data (what live_sync writes) and has no hook, so
-- without this it shows the cart's own locations whatever this mod rolls.
-- Two engine functions are wrapped (this mod declares engine_internals):
--
--   FireRed/LeafGreen  PokedexData.getWildAreasForSpecies(slot) -> DEX_AREA keys
--                      (src/core/game3/pokedex_data.lua)
--   Ruby/Sapphire/Emerald  Area.findMapsWithMon(slot, ctx) -> highlights/markers
--                      (src/ui/game3/rse/pokedex_area.lua)
--
-- Runtime.mapsWithSpecies says which maps; nil (inactive) hands the call to
-- the original untouched. Fishing and Rock Smash are not generated on Gen 3,
-- so the cart's own entries for those still count. Every wrapper falls back
-- to the original on any error, so an engine rename costs the feature, never
-- the Pokedex.

return function(deps)
  local mod, Runtime = deps.mod, deps.Runtime
  local world = Runtime.world

  local function speciesMaps(slot)
    local id = Runtime.speciesOfSlot(slot)
    if not id then return nil end
    return Runtime.mapsWithSpecies(id)
  end

  local function liveEncounters()
    local data = mod.game and mod.game.data
    return data and data.gen3Encounters or {}
  end

  -- ------------------------------------------------------- FireRed / LeafGreen

  local function installFireRed()
    local ok, PD = pcall(require, "src.core.game3.pokedex_data")
    if not (ok and type(PD) == "table" and type(PD.getWildAreasForSpecies) == "function") then
      return
    end
    -- engine modules outlive a mod reload: wrap once, and point the wrapper
    -- at the newest load's answer each time
    PD.__modernSpawnsMaps = speciesMaps
    if PD.__modernSpawns then return end
    PD.__modernSpawns = true

    -- A map's DEX_AREA key, resolved the way PokedexData._buildSpeciesWildAreas
    -- resolves one (map section first, then the normalized map name).
    local areaCache = {}
    local function dexAreaOf(g, n)
      local key = g .. ":" .. n
      if areaCache[key] ~= nil then return areaCache[key] or nil end
      local area
      local okF, Family = pcall(require, "src.import.gba.family")
      local family = okF and type(Family) == "table" and Family.active and Family.active()
      local mapGroups = family and family:groups()
      local gTable = mapGroups and mapGroups.groups
        and (mapGroups.groups[g] or mapGroups.groups[g + 1])
      local pretName = gTable and gTable.maps and (gTable.maps[n + 1] or gTable.maps[n])
      local data = PD._areaData or {}
      local mapsecToArea, markers = data.mapsecToArea or {}, data.markers or {}
      local secId
      local okM, MS = pcall(require, "src.import.gba.map_sections_extract")
      if family and family.aliases and okM and type(MS) == "table" and MS.getInfo then
        local okInfo, info = pcall(MS.getInfo, nil, pretName)
        secId = okInfo and type(info) == "table" and info.id or nil
      end
      area = secId and mapsecToArea[secId]
      if not area and pretName then
        local norm = "DEX_AREA_" .. tostring(pretName):gsub("^FR_", ""):gsub("^SEVII_", "")
          :gsub("([a-z])([A-Z])", "%1_%2"):upper()
        if markers[norm] then area = norm end
      end
      if area and not (markers[area] or mapsecToArea[secId]) then area = nil end
      areaCache[key] = area or false
      return area
    end

    local original = PD.getWildAreasForSpecies
    PD.getWildAreasForSpecies = function(speciesId, ...)
      local ok2, areas = pcall(function()
        local maps = PD.__modernSpawnsMaps(speciesId)
        if not maps then return nil end
        PD.init()
        local out, seen = {}, {}
        local function add(area)
          if area and not seen[area] then
            seen[area] = true
            out[#out + 1] = area
          end
        end
        -- a Sevii map with no marker of its own (Six Island's Green Path)
        -- borrows its island's
        local markers = (PD._areaData or {}).markers or {}
        local function islandArea(mapId)
          local island = tostring(mapId):match("(%u+)_ISLAND")
          local key = island and ("DEX_AREA_" .. island .. "_ISLAND")
          return key and markers[key] and key or nil
        end
        for mapId in pairs(maps) do
          local g, n = world.mapGroupNum(mapId)
          if g and n then add(dexAreaOf(g, n) or islandArea(mapId)) end
        end
        -- the cart's own fishing and Rock Smash catches are still there
        local sp = tonumber(speciesId)
        for _, rec in pairs(liveEncounters()) do
          if type(rec) == "table" and rec.mapGroup and rec.mapNum then
            for _, k in ipairs({ "fishing", "rockSmash" }) do
              for _, s in ipairs(rec[k] and rec[k].slots or {}) do
                if tonumber(s.species) == sp then
                  add(dexAreaOf(tonumber(rec.mapGroup), tonumber(rec.mapNum)))
                end
              end
            end
          end
        end
        table.sort(out)
        return out
      end)
      if ok2 and areas then return areas end
      return original(speciesId, ...)
    end
  end

  -- ------------------------------------------------- Ruby / Sapphire / Emerald

  local function installHoenn()
    local ok, Area = pcall(require, "src.ui.game3.rse.pokedex_area")
    if not (ok and type(Area) == "table" and type(Area.findMapsWithMon) == "function") then
      return
    end
    Area.__modernSpawnsMaps = speciesMaps
    if Area.__modernSpawns then return end
    Area.__modernSpawns = true

    -- The page scans ctx.encounters ("group:num" -> header) for the species.
    -- Hand it a copy whose land/water tables hold the species exactly where
    -- this mod puts it; fishing and Rock Smash stay the cart's own.
    local original = Area.findMapsWithMon
    Area.findMapsWithMon = function(species, ctx, ...)
      local ok2, view = pcall(function()
        if type(ctx) ~= "table" or type(ctx.encounters) ~= "table" then return nil end
        local maps = Area.__modernSpawnsMaps(species)
        if not maps then return nil end
        local marks = {}
        for mapId, kinds in pairs(maps) do
          local g, n = world.mapGroupNum(mapId)
          if g and n then
            local key = g .. ":" .. n
            marks[key] = marks[key] or { g = g, n = n }
            if kinds.land then marks[key].land = true end
            if kinds.water then marks[key].water = true end
          end
        end
        local only = { slots = { { species = species } } }
        local encounters = {}
        for key, header in pairs(ctx.encounters) do
          if type(header) == "table" then
            local copy = {}
            for k, v in pairs(header) do copy[k] = v end
            local mark = marks[key]
            copy.land = mark and mark.land and only or nil
            copy.water = mark and mark.water and only or nil
            -- Altering Cave's variant headers are its vanilla land tables
            copy.variants = nil
            encounters[key] = copy
          else
            encounters[key] = header
          end
        end
        for key, mark in pairs(marks) do
          if not encounters[key] then
            encounters[key] = { mapGroup = mark.g, mapNum = mark.n,
                                land = mark.land and only or nil,
                                water = mark.water and only or nil }
          end
        end
        -- The page hides "landmark" places (Sky Pillar, Artisan Cave, Seafloor
        -- Cavern, Altering Cave, Mirage Tower, Desert Underpass) until their
        -- flag is set. About a sixth of the species this mod places live only
        -- there, so their page would read AREA UNKNOWN: count them as found.
        return setmetatable({ encounters = encounters, flag = function() return true end },
                            { __index = ctx })
      end)
      if ok2 and view then
        local ok3, found = pcall(original, species, view, ...)
        if ok3 and found then return found end
      end
      return original(species, ctx, ...)
    end
  end

  -- An undiscovered species may open in the Pokedex's limited view (name,
  -- picture and cry hidden; its AREA page shows) when this mod puts it
  -- somewhere under the current settings. national_dex_gen3 patches the two
  -- screens (its src/dex_patch.lua) and asks this, per species slot.
  local function peek(slot)
    local id = Runtime.speciesOfSlot(slot)
    local maps = id and Runtime.mapsWithSpecies(id)
    return maps ~= nil and next(maps) ~= nil
  end
  Runtime.dexPeek = peek

  local function registerPeek()
    local ok, dex = pcall(function() return mod:find("national_dex_gen3") end)
    local exports = ok and type(dex) == "table" and dex.exports
    if type(exports) == "table" and type(exports.setDexPeek) == "function" then
      pcall(exports.setDexPeek, peek)
    end
  end

  return function()
    if world.generation ~= 3 or type(world.mapGroupNum) ~= "function" then return end
    installFireRed()
    installHoenn()
    registerPeek()
  end
end
