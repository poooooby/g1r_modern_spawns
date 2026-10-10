-- Standalone: luajit mods/modern_spawns/tests/rse_test.lua (from the
-- gen1recomp root; needs Emerald, Ruby and Sapphire imported under
-- emerald/, ruby/ and sapphire/, and mods/national_dex_gen3 installed).
--
-- Ruby, Sapphire and Emerald run the same game3 engine and schema as
-- FireRed (Schemas.GEN3, the encounters shape, G3.EVOLUTIONS are one shared
-- table, not per-ROM), so src/adapters/gen3.lua needs no game-specific
-- code for them -- gen3_test.lua already proves the mechanism (per-slot
-- roll -> species.species substitution, numeric slots, generation caps,
-- OFF, the preview, RANDOM/EVERY MAP) on FireRed in detail; this file
-- confirms the same mechanism holds on the other three carts, plus the
-- one thing that is genuinely per-game here: which species are available
-- to host a LEGENDARIES encounter (Hoenn's own Kyogre/Groudon/Rayquaza are
-- cart-native species, #382-384, not part of national_dex_gen3's payload).
--
-- Unlike FireRed's "FR_" alias convention, Hoenn map ids have no single
-- shared prefix (bare "ROUTE130", but "MT_"/"MOSSDEEP_" etc. elsewhere), so
-- this file finds real wild maps by asking the mod itself (tableFor),
-- rather than filtering ids by a prefix pattern the way gen3_test.lua does.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local HOENN_LEGENDARIES = { KYOGRE = true, GROUDON = true, RAYQUAZA = true }

for _, game in ipairs({ "emerald", "ruby", "sapphire" }) do
  local data = H.gen3Data(game)
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" },
                             { data = data, generation = 3 })
  T.eq(#run.errors, 0, game .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  T.check(run.mods.modern_spawns and run.mods.modern_spawns.state == "loaded",
          game .. ": modern_spawns targets this cart")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "HOENN" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", legendaries = "on" }
  local set, managerGame = H.manager(loader)
  managerGame.data = data -- live_sync writes through mod.game.data; the stub has none by default
  local api = loader.exports.modern_spawns
  T.eq(api.generation(), 3, game .. ": the Gen 3 adapter runs")
  T.check(api.isActive(), game .. ": active with national_dex_gen3's species")

  -- real wild maps: anything the mod itself generates a table for
  local grassMap, waterMap
  for mapId in pairs(data.gen3Encounters) do
    if not grassMap and api.tableFor(mapId, "grass") then grassMap = mapId end
    if not waterMap and api.tableFor(mapId, "water") then waterMap = mapId end
    if grassMap and waterMap then break end
  end
  T.check(grassMap ~= nil, game .. ": a map with a generated grass table")
  T.check(waterMap ~= nil, game .. ": a map with a generated water table")

  -- Across every map, not just grassMap: a single small cave room can
  -- legitimately roll zero modern species in its handful of slots by
  -- chance, which isn't a bug -- the claim this checks is "modern species
  -- appear somewhere", not "on this one map in particular".
  local modern, mapsChecked = 0, 0
  for mapId in pairs(data.gen3Encounters) do
    local grass = api.tableFor(mapId, "grass")
    if grass then
      mapsChecked = mapsChecked + 1
      for _, slot in ipairs(grass.slots) do
        local rec = loader.content.pokemon:get(slot.species)
        if rec and (tonumber(rec.dex) or 0) > 386 then modern = modern + 1 end
      end
    end
  end
  T.check(modern > 0, game .. ": modern species appear somewhere (" .. modern
    .. " slots across " .. mapsChecked .. " maps)")

  -- ------- live_sync: every alias of grassMap's live table carries the
  -- generated species, not just the one id tableFor was asked about. Gen 3
  -- is the one generation where this matters: its aliases are separate
  -- table objects (confirmed empirically), unlike Gen 1/2.
  do
    local rec = data.gen3Encounters[grassMap]
    local aliases = {}
    if rec and rec.mapGroup and rec.mapNum then
      local key = rec.mapGroup .. ":" .. rec.mapNum
      for id, other in pairs(data.gen3Encounters) do
        if type(id) == "string" and other.mapGroup and other.mapNum
          and (other.mapGroup .. ":" .. other.mapNum) == key then
          aliases[#aliases + 1] = id
        end
      end
    end
    local vanillaSpecies = {}
    for _, id in ipairs(aliases) do
      local area = data.gen3Encounters[id].land
      vanillaSpecies[id] = area and area.slots[1] and area.slots[1].species
    end

    loader.events:emit("save.loaded", {})
    local generated = api.tableFor(grassMap, "land") or api.tableFor(grassMap, "grass")
    T.check(#aliases > 0, game .. ": " .. grassMap .. " has alias ids to check")
    -- in the cart's own spelling: the numeric species slot (the engine's roll does
    -- tonumber(entry.species); a species id there broke every roll on the map)
    local allAliasesMatch = true
    for _, id in ipairs(aliases) do
      local area = data.gen3Encounters[id].land
      if area then
        for i, slot in ipairs(area.slots) do
          local rec = generated and loader.content.pokemon:get(generated.slots[i].species)
          if type(slot.species) ~= "number" or not rec or slot.species ~= tonumber(rec.index) then
            allAliasesMatch = false
          end
        end
      end
    end
    T.check(allAliasesMatch, game .. ": live_sync updated every alias of " .. grassMap
      .. " (" .. table.concat(aliases, ",") .. "), not just one")

    set("enabled", "off")
    local restored = true
    for _, id in ipairs(aliases) do
      local area = data.gen3Encounters[id].land
      if area and area.slots[1] and area.slots[1].species ~= vanillaSpecies[id] then
        restored = false
      end
    end
    T.check(restored, game .. ": OFF restores every alias to its original species")
    set("enabled", "on")
  end

  -- GEN 1-3 cap: every slot's species is #1-411 (the cart's own range)
  set("max_generation", "3")
  local capped = api.tableFor(grassMap, "grass")
  local overCap = false
  for _, slot in ipairs(capped.slots) do
    local rec = loader.content.pokemon:get(slot.species)
    if rec and (tonumber(rec.dex) or 0) > 411 then overCap = true end
  end
  T.check(not overCap, game .. ": GEN 1-3 keeps every species at or under #411")
  set("max_generation", "9")

  -- OFF: the game's own encounter table object, untouched
  set("enabled", "off")
  T.eq(api.tableFor(grassMap, "grass"), nil, game .. ": OFF answers nil")
  set("enabled", "on")

  -- LEGENDARIES: Hoenn's own legendaries are correctly recognized as hosts
  local homes = api.legendaryHomes()
  local found
  for mapId, byKind in pairs(homes or {}) do
    for kind, list in pairs(byKind) do
      for _, h in ipairs(list) do
        if HOENN_LEGENDARIES[h.id] then found = h.id .. "@" .. mapId .. "/" .. kind end
      end
    end
  end
  T.check(found ~= nil, game .. ": a Hoenn legendary has a home map (" .. tostring(found) .. ")")

  -- RANDOM and EVERY MAP: the mechanism still runs (gen3_test.lua covers
  -- the detailed per-slot behavior on FireRed)
  set("spawn_mode", "random")
  T.eq(api.tableFor(grassMap, "grass"), nil, game .. ": RANDOM has no fixed table")
  set("spawn_mode", "map")
  T.check(api.tableFor(grassMap, "grass") ~= nil, game .. ": EVERY MAP has a fixed table")
  set("spawn_mode", "seeded")

  run.release()
end

T.finish("modern_spawns Ruby/Sapphire/Emerald")
