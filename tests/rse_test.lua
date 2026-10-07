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

  local grass = api.tableFor(grassMap, "grass")
  local modern = 0
  for _, slot in ipairs(grass.slots) do
    local rec = loader.content.pokemon:get(slot.species)
    if rec and (tonumber(rec.dex) or 0) > 386 then modern = modern + 1 end
  end
  T.check(modern > 0, game .. ": modern species appear in " .. grassMap .. " (" .. modern .. ")")

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
