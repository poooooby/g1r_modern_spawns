-- Modern Spawns: dynamic Gen 1-9 wild encounter tables for Pokemon Red,
-- Blue, Yellow, Gold, Silver, Crystal, FireRed and LeafGreen.
--
-- The game's own encounter tables are the skeleton (rate, slot levels, odds
-- ladder, Super Rod groups); only species are redistributed, from the
-- species the running game actually has registered (national_dex supplies
-- #152-1025). The one appended payload is data/spawn_profiles.lua
-- -- PokéAPI-derived wild levels, habitats and rarity -- built by
-- pokemon_spawn_generator/generate_spawn_data.py --lua.
--
-- Module map:
--   src/config.lua        options, SpawnConfig tuning, option-bucket writer
--   src/rng.lua           deterministic PRNG + hash
--   src/map_context.lua   runtime map -> habitat tags
--   src/species_pool.lua  runtime species + profiles -> candidates
--   src/generator.lua     full redistribution, scoring, explain records
--   src/adapters/gen1.lua Red/Blue/Yellow data + hook shapes
--   src/adapters/gen2.lua Gold/Silver/Crystal data + hook shapes
--   src/adapters/gen3.lua FireRed/LeafGreen data + hook shapes
--   src/compat/dex1025.lua  keeps 1025Dex's WILD GENS off our encounters
--   src/runtime.lua       seed, cache, encounter hooks, events, seed option sync
--   src/api.lua           mod.exports framework surface
--
-- Settings live only in the Mod Manager (OPTIONS -> MODS -> Modern Spawns),
-- rendered from options.lua; the top-level OPTION screen is left untouched.

-- A mod's own files load as chunks through mod:read; require() cannot see
-- them. A sibling that fails to read or compile returns nil and is reported
-- with the file that broke, so the load degrades instead of failing.
local function loadSibling(mod, name, optional)
  local source = mod:read(name)
  if not source then
    if not optional then
      mod.log:error("%s is missing -- reinstall the mod; modern spawns stay off", name)
    end
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

return function(mod)
  local schema = loadSibling(mod, "options.lua")
  if type(schema) == "table" then mod.options:define(schema) end

  local Config = loadSibling(mod, "src/config.lua")
  local Rng = loadSibling(mod, "src/rng.lua")
  local MapContext = loadSibling(mod, "src/map_context.lua")
  local SpeciesPool = loadSibling(mod, "src/species_pool.lua")
  local Generator = loadSibling(mod, "src/generator.lua")
  local makeRuntime = loadSibling(mod, "src/runtime.lua")
  local makeApi = loadSibling(mod, "src/api.lua")
  -- one adapter per engine: Red/Blue/Yellow, Gold/Silver/Crystal,
  -- FireRed/LeafGreen
  local adapters = {
    [1] = loadSibling(mod, "src/adapters/gen1.lua"),
    [2] = loadSibling(mod, "src/adapters/gen2.lua"),
    [3] = loadSibling(mod, "src/adapters/gen3.lua"),
  }
  local installDex1025 = loadSibling(mod, "src/compat/dex1025.lua")
  if not (Config and Rng and MapContext and SpeciesPool and Generator
          and makeRuntime and makeApi and adapters[1] and adapters[2]
          and adapters[3]) then
    return
  end

  -- The appended payload. Missing or wrong-shaped, every species falls back
  -- to a runtime-estimated profile; spawns still work, less faithfully.
  local profiles = loadSibling(mod, "data/spawn_profiles.lua", true)
  if type(profiles) ~= "table" or type(profiles.species) ~= "table" then
    mod.log:warn("data/spawn_profiles.lua is missing -- every "
      .. "species uses an estimated profile; reinstall the mod for the "
      .. "PokéAPI-derived levels and habitats")
    profiles = nil
  end

  local Runtime = makeRuntime({
    mod = mod, Config = Config, Generator = Generator, SpeciesPool = SpeciesPool,
    MapContext = MapContext, Rng = Rng, profiles = profiles, adapters = adapters,
  })
  Runtime.install()

  makeApi({ mod = mod, Runtime = Runtime, Config = Config })

  -- FireRed with 1025Dex installed: keep its WILD GENS off our encounters
  if installDex1025 then
    pcall(installDex1025, { mod = mod, Runtime = Runtime })
  end
end
