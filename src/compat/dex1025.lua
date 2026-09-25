-- Living beside 1025Dex on FireRed.
--
-- 1025Dex's WILD GENS does not use the encounter hooks: it patches
-- src.core.game3.battle_bridge's Bridge.start and swaps every wild foe just
-- before the battle starts -- after any mod's encounter hooks ran. Its own
-- escape hatch is `opts.__completeDexExact`: a battle carrying it is left
-- alone.
--
-- While MODERN SPAWNS is active, this wraps Bridge.start outside 1025Dex's
-- wrapper (the manifest's optional dependency loads 1025Dex first) and sets
-- that flag on exactly the battles whose foe is the encounter this mod just
-- decided (Runtime.lastEncounter, written by the encounter.species hook).
-- Fishing and Rock Smash never pass the encounter hooks, so WILD GENS still
-- handles them; with MODERN SPAWNS off nothing is flagged and WILD GENS runs
-- as it always does. Needs engine_internals (a require of an engine module).

return function(deps)
  local mod, Runtime = deps.mod, deps.Runtime
  if tonumber(mod.generation) ~= 3 then return false end
  local ok, found = pcall(function() return mod:find("1025dex") end)
  if not (ok and found) then return false end

  local okB, Bridge = pcall(require, "src.core.game3.battle_bridge")
  if not (okB and type(Bridge) == "table" and type(Bridge.start) == "function") then
    mod.log:warn("1025Dex is installed but FireRed's battle bridge was not found -- "
      .. "its WILD GENS may replace Modern Spawns' encounters")
    return false
  end
  if Bridge.__modernSpawnsWrapped then return true end
  Bridge.__modernSpawnsWrapped = true

  local original = Bridge.start
  Bridge.start = function(owner, game, foe, opts)
    local last = Runtime.lastEncounter
    Runtime.lastEncounter = nil
    if type(opts) == "table" and opts.wild and last and type(foe) == "table"
      and Runtime.isActive() then
      local species = foe.speciesId or foe.species
      local sameSpecies = species ~= nil
        and (species == last.speciesId or species == last.species)
      if sameSpecies and tonumber(foe.level) == tonumber(last.level) then
        opts.__completeDexExact = true
      end
    end
    return original(owner, game, foe, opts)
  end
  mod.log:info("1025Dex detected: Modern Spawns decides FireRed's grass, cave "
    .. "and surf encounters while ON; WILD GENS keeps fishing and Rock Smash")
  return true
end
