-- Writes the generated species directly into the running game's own
-- encounter tables (game.data.encounters / gen2Encounters / gen3Encounters,
-- plus Gen 1's Super Rod groups), restorable, so a mod that reads those
-- tables itself -- bypassing encounter.roll/encounter.table entirely, the
-- way a wild-encounter guide does -- sees the same species this mod would
-- hand the engine on a real roll.
--
-- Mechanics are never touched here: only each slot's `species` field is
-- overwritten, never `level`/`minLevel`/`maxLevel`/`rate`/`buckets`/slot
-- count, and only for the kinds this mod already redistributes on a real
-- roll (see each adapter's own "left as the game has them" list -- fishing
-- rods besides Gen 1's Super Rod, Rock Smash, swarms, the Bug Contest,
-- Headbutt and scripted encounters are never written here either).
--
-- `world.liveSlots(mapId, kind, time)` (each adapter) returns the list of
-- live slot arrays to write into for that map/kind -- a list, not one array,
-- because Gen 3's encounters registry duplicates one map's record under
-- several aliases as SEPARATE table objects (confirmed empirically: writing
-- through one alias does not update another), so every alias sharing the
-- map's mapGroup:mapNum must be written. Gen 1/2 always return a
-- single-element list. nil means this map/kind has no live table to write.
return function(deps)
  local world = deps.world
  local LiveSync = {}

  -- backup[mapId][kind..(time or "")] = { { arr = <live slots array>,
  --                                          snap = { [i] = originalSpecies } }, ... }
  -- Keeps the actual array references from the FIRST write, so restore
  -- never has to re-resolve `world.liveSlots` (which could, in principle,
  -- answer differently later) and always writes back into the exact arrays
  -- it touched.
  local backup = {}

  -- Writes `species[i]` into slot i of every live array for (mapId, kind,
  -- time), backing up each array's original species the first time it is
  -- touched. `species` is the slot list from Runtime.tableFor/drawFor (or
  -- any list of { species = ... } in the same slot order); extra or missing
  -- entries are ignored rather than erroring, since a generated table's
  -- slot count already always matches the live one by construction.
  -- Returns true if anything was written.
  function LiveSync.apply(mapId, kind, time, species)
    if type(species) ~= "table" then return false end
    local arrays = world.liveSlots(mapId, kind, time)
    if type(arrays) ~= "table" then return false end
    local key = kind .. (time or "")
    backup[mapId] = backup[mapId] or {}
    local list = backup[mapId][key]
    if not list then
      list = {}
      for i, arr in ipairs(arrays) do
        local snap = {}
        for j, slot in ipairs(arr) do snap[j] = slot.species end
        list[i] = { arr = arr, snap = snap }
      end
      backup[mapId][key] = list
    end
    local wrote = false
    for _, entry in ipairs(list) do
      for i, slot in ipairs(entry.arr) do
        local sp = species[i] and species[i].species
        -- in the game's own spelling: Gen 3 stores a numeric species slot, not an id
        if sp ~= nil and world.liveValue then sp = world.liveValue(sp) end
        if sp ~= nil then
          slot.species = sp
          wrote = true
        end
      end
    end
    return wrote
  end

  -- Writes every backed-up array's ORIGINAL species back, then clears that
  -- backup -- so a later apply starts a fresh, correct backup rather than
  -- stacking on top of a previous restore. mapId omitted: every map.
  function LiveSync.restore(mapId)
    local function restoreOne(id)
      local byKey = backup[id]
      if not byKey then return end
      for _, list in pairs(byKey) do
        for _, entry in ipairs(list) do
          for i, slot in ipairs(entry.arr) do
            if entry.snap[i] ~= nil then slot.species = entry.snap[i] end
          end
        end
      end
      backup[id] = nil
    end
    if mapId then
      restoreOne(mapId)
    else
      for id in pairs(backup) do restoreOne(id) end
    end
  end

  return LiveSync
end
