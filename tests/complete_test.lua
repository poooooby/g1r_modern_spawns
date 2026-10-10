-- Standalone: luajit mods/modern_spawns/tests/complete_test.lua (from the
-- gen1recomp root; needs Emerald imported under emerald/ and
-- mods/national_dex_gen3).
--
-- COMPLETE DEX: every species the GENERATIONS cap allows is catchable
-- somewhere. Each role keeps its primary species (the SEEDED pick) and also
-- holds a pool; the engine rolls the slot with the game's own odds and the
-- species is drawn from that slot's pool afterwards. With LEGENDARIES ON
-- every legendary/mythical under the cap has a home.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")

local data = H.gen3Data("emerald")
local P = data.gen3Pokemon
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "COMPLETE" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local set, game = H.manager(loader)
game.data = data
local ms = loader.exports.modern_spawns
set("spawn_mode", "complete")
T.eq(ms.spawnMode(), "complete", "COMPLETE DEX is a SPAWN MODE")

-- live sync rewrites data's species, so compare against an untouched copy
local live = H.gen3Data("emerald").gen3Encounters
-- the maps the mod generates for (every alias the game may roll under)
local maps = {}
for id in pairs(data.gen3Encounters) do
  if type(id) == "string" and (ms.tableFor(id, "land") or ms.tableFor(id, "water")) then
    maps[#maps + 1] = id
  end
end
table.sort(maps)
T.check(#maps > 80, "Emerald's wild maps (" .. #maps .. ")")

-- looks (PUMPKABOO_SMALL, ...) are not candidates: fold them onto their base
local lookOf = {}
for _, c in ipairs(ms.candidates({ maxGeneration = 9 })) do
  for _, v in ipairs(c.variants or {}) do lookOf[v] = c.id end
end

-- the species every pool holds, looks folded onto their base
local function covered()
  local seen = {}
  for _, mapId in ipairs(maps) do
    for _, terrain in ipairs({ "land", "water" }) do
      for _, list in pairs(ms.poolFor(mapId, terrain) or {}) do
        for _, id in ipairs(list) do
          seen[id] = true
          if lookOf[id] then seen[lookOf[id]] = true end
          local p = ms.profileOf(id)
          if p and p.baseSpecies then seen[p.baseSpecies] = true end
        end
      end
    end
  end
  return seen
end

-- ------- every species under the cap is in some pool

for _, cap in ipairs({ "3", "5", "9" }) do
  set("max_generation", cap)
  local t0 = os.clock()
  ms.tableFor(maps[1], "land")
  local took = os.clock() - t0
  T.check(took < 3, "GEN 1-" .. cap .. " atlas builds in under 3 s (" .. string.format("%.2f", took) .. " s)")
  local seen, absent = covered(), {}
  local expected = ms.candidates({ maxGeneration = tonumber(cap) })
  for _, c in ipairs(expected) do
    if not seen[c.id] and not (c.baseSpecies and seen[c.baseSpecies]) then absent[#absent + 1] = c.id end
  end
  T.eq(#absent, 0, "GEN 1-" .. cap .. ": all " .. #expected .. " species are catchable ("
    .. table.concat(absent, ", ", 1, math.min(#absent, 8)) .. ")")
  local special, over = 0, 0
  for id in pairs(seen) do
    local p = ms.profileOf(id)
    if p and p.special then special = special + 1 end
    if p and p.generation > tonumber(cap) then over = over + 1 end
  end
  T.eq(special, 0, "GEN 1-" .. cap .. ": no legendary or mythical in any pool")
  T.eq(over, 0, "GEN 1-" .. cap .. ": nothing past the cap")
end

-- ------- structure: levels, rate and slot count are the cart's own

local kept = true
for _, mapId in ipairs(maps) do
  for _, terrain in ipairs({ "land", "water" }) do
    local vanilla = live[mapId][terrain]
    local t = ms.tableFor(mapId, terrain)
    if vanilla and t then
      if #t.slots ~= #vanilla.slots then kept = false end
      for i, slot in ipairs(t.slots) do
        if slot.minLevel ~= vanilla.slots[i].minLevel or slot.maxLevel ~= vanilla.slots[i].maxLevel then
          kept = false
        end
      end
      local pools = ms.poolFor(mapId, terrain)
      if not pools then kept = false end
      for i = 1, #t.slots do
        if not (pools and pools[i] and pools[i][1] == t.slots[i].species) then kept = false end
      end
    end
  end
end
T.check(kept, "slot count and levels kept; every slot's pool starts with its own species")

-- ------- the seed moves species around; the same seed does not

local function homesOf()
  local home = {}
  for _, mapId in ipairs(maps) do
    for _, terrain in ipairs({ "land", "water" }) do
      for i, list in pairs(ms.poolFor(mapId, terrain) or {}) do
        for _, id in ipairs(list) do home[id] = home[id] or (mapId .. terrain) end
      end
    end
  end
  return home
end
local a = homesOf()
ms.invalidate()
local again = homesOf()
local same = true
for id, h in pairs(a) do if again[id] ~= h then same = false end end
T.check(same, "the same seed gives the same atlas")
ms.setSeed("OTHERSEED")
local b = homesOf()
local moved = 0
for id, h in pairs(a) do if b[id] ~= h then moved = moved + 1 end end
T.check(moved > 50, "a different seed moves species (" .. moved .. " moved)")

-- ------- encounters: the rolled slot becomes one of its pool's species

local MAP = "EM_ROUTE101"
local pools = ms.poolFor(MAP, "land")
local vanilla = live[MAP].land.slots
-- the encounter hands the engine a numeric species slot: map it back
local byIndex = {}
for _, list in pairs(pools) do
  for _, sid in ipairs(list) do
    local ids = { sid }
    local p = ms.profileOf(sid)
    for _, v in ipairs(p and p.variants or {}) do ids[#ids + 1] = v end
    for _, one in ipairs(ids) do
      local rec = loader.content.pokemon:get(one)
      if rec and rec.index then byIndex[tonumber(rec.index)] = one end
    end
  end
end
local drawn, outside = {}, 0
for n = 1, 300 do
  local i = (n % #vanilla) + 1
  local slot = vanilla[i]
  local out = Runtime.call("encounter.species", function(e) return e end,
    { species = P.keyName(slot.species), speciesId = slot.species, level = slot.minLevel },
    { mapId = MAP, terrain = "land", rng = function() return 4321 end })
  local id = out and (byIndex[tonumber(out.speciesId or out.species)] or tostring(out.species))
  drawn[id] = true
  local inPool = false
  for _, sid in ipairs(pools[i]) do
    local p = ms.profileOf(sid)
    if sid == id or (p and p.variants and (function()
      for _, v in ipairs(p.variants) do if v == id then return true end end
    end)()) then inPool = true end
  end
  if not inPool then outside = outside + 1 end
end
local distinct = 0
for _ in pairs(drawn) do distinct = distinct + 1 end
T.eq(outside, 0, "every encounter on Route 101 comes from its slot's pool")
local primaries, poolSpecies = {}, {}
for i, list in pairs(pools) do
  primaries[list[1]] = true
  for _, sid in ipairs(list) do poolSpecies[sid] = true end
end
local nPrimary, nPool = 0, 0
for _ in pairs(primaries) do nPrimary = nPrimary + 1 end
for _ in pairs(poolSpecies) do nPool = nPool + 1 end
T.check(nPool > nPrimary and distinct > nPrimary, "Route 101 shows more than its primaries ("
  .. nPrimary .. " primaries, " .. nPool .. " in pools, " .. distinct .. " drawn)")

-- pools stay small: the extras spread across the game
local largest, total, roles = 0, 0, 0
for _, mapId in ipairs(maps) do
  for _, terrain in ipairs({ "land", "water" }) do
    local seenList = {}
    for _, list in pairs(ms.poolFor(mapId, terrain) or {}) do
      if not seenList[list] then
        seenList[list] = true
        roles, total = roles + 1, total + #list
        if #list > largest then largest = #list end
      end
    end
  end
end
print(string.format("pools: %d roles (aliases counted), avg %.2f, largest %d", roles, total / roles, largest))
T.check(largest <= 6, "no role's pool holds more than 6 species (" .. largest .. ")")

-- ------- LEGENDARIES ON: every legendary and mythical has a home

set("legendaries", "on")
local homed = {}
for _, byKind in pairs(ms.legendaryHomes() or {}) do
  for _, list in pairs(byKind) do
    for _, host in ipairs(list) do homed[host.id] = true end
  end
end
local unhomed = {}
for _, c in ipairs(ms.candidates({ maxGeneration = 9, includeSpecial = true })) do
  if c.special and not homed[c.id] then unhomed[#unhomed + 1] = c.id end
end
T.eq(#unhomed, 0, "every legendary and mythical has a home ("
  .. table.concat(unhomed, ", ", 1, math.min(#unhomed, 8)) .. ")")

-- ------- the Pokedex AREA page (src/dex_area.lua) reads the generated tables

local Area = require("src.ui.game3.rse.pokedex_area")
local Dex = require("src.core.game3.dex")
local function slotOf(id) return tonumber(loader.content.pokemon:get(id).index) end
-- a page context with every map in one "towns" group, so each found map is
-- a highlight (the real one comes from the cache's map sections)
local function areaMaps(id)
  local rec = data.gen3Encounters[MAP]
  local found = Area.findMapsWithMon(slotOf(id), {
    encounters = {}, mapsecOf = function() return 1 end, correct = function(x) return x end,
    NONE = 999, flag = function() return true end,
    groups = { towns = tonumber(rec.mapGroup), dungeons = -1, special = -2 },
  })
  local out = {}
  for _, o in ipairs(found.overworld) do out[o.group .. ":" .. o.num] = true end
  return out
end
local route = data.gen3Encounters[MAP]
local routeKey = route.mapGroup .. ":" .. route.mapNum
local extra = pools[#pools][#pools[#pools]]
T.check(areaMaps(extra)[routeKey], "COMPLETE: AREA shows Route 101 for a species in its pool (" .. extra .. ")")
-- a place the page hides until discovered (Sky Pillar, Artisan Cave, ...) still
-- shows: a sixth of the species placed live only in one
local hidden = Area.findMapsWithMon(slotOf(extra), {
  encounters = {}, mapsecOf = function() return 5 end, correct = function(x) return x end,
  NONE = 999, flag = function() return false end, landmarks = { { 5, 123 }, { 999, 0 } },
  groups = { towns = -1, dungeons = tonumber(route.mapGroup), special = -2 },
})
T.eq(#hidden.special, 1, "an undiscovered landmark place still shows on AREA")
set("spawn_mode", "random")
T.check(next(areaMaps(extra)) == nil, "RANDOM: AREA shows nothing")

-- LEGENDARIES ON, any mode but RANDOM: every hosted special is marked seen
game.session = { dex = {} }
set("spawn_mode", "complete")
local unseen = {}
for _, byKind in pairs(ms.legendaryHomes() or {}) do
  for _, list in pairs(byKind) do
    for _, host in ipairs(list) do
      if not Dex.isSeen(game.session.dex, slotOf(host.id)) then unseen[#unseen + 1] = host.id end
    end
  end
end
T.eq(#unseen, 0, "LEGENDARIES ON: every hosted legendary/mythical is seen in the Pokedex")
game.session = { dex = {} }
set("spawn_mode", "random")
local anySeen = false
for _, byKind in pairs(ms.legendaryHomes() or {}) do
  for _, list in pairs(byKind) do
    for _, host in ipairs(list) do
      if Dex.isSeen(game.session.dex, slotOf(host.id)) then anySeen = true end
    end
  end
end
T.check(not anySeen, "RANDOM: legendaries are not marked seen")
set("spawn_mode", "complete")

-- ------- undiscovered entries: what may open in the Pokedex's limited view
-- (national_dex_gen3 asks per species slot; this mod answers from locate)

T.check(next(ms.locate(extra) or {}) ~= nil, "COMPLETE: a pooled species can be located (" .. extra .. ")")
set("spawn_mode", "random")
T.eq(next(ms.locate(extra) or { x = 1 }), nil, "RANDOM: nothing can be located")
set("spawn_mode", "complete")
local gen9
for _, c in ipairs(ms.candidates({ maxGeneration = 9 })) do
  if c.generation == 9 then gen9 = c.id break end
end
T.check(next(ms.locate(gen9) or {}) ~= nil, "GEN 1-9: a Gen 9 species can be located (" .. gen9 .. ")")
set("max_generation", "3")
T.eq(next(ms.locate(gen9) or {}), nil, "GEN 1-3: a Gen 9 species cannot")
set("max_generation", "9")
set("enabled", "off")
T.eq(ms.locate(extra), nil, "MODERN SPAWNS OFF: locate answers nil (the page is the cart's own)")
set("enabled", "on")

-- ------- live sync on Gen 3: the game's own tables keep the cart's numeric species
-- (the engine rolls them with tonumber(entry.species); a name there broke every roll), and
-- a roll from the synced table is still recognised, so RANDOM redraws per encounter

set("spawn_mode", "random")
loader.events:emit("map.entered", { mapId = MAP })
local synced = data.gen3Encounters[MAP].land.slots
local numeric = true
for _, s in ipairs(synced) do if type(s.species) ~= "number" then numeric = false end end
T.check(numeric, "live sync writes numeric species slots on Gen 3")
local drawnLive = {}
for n = 1, 120 do
  local s = synced[(n % #synced) + 1]
  local out = Runtime.call("encounter.species", function(e) return e end,
    { species = P.keyName(s.species), speciesId = s.species, level = s.minLevel },
    { mapId = MAP, terrain = "land", rng = function() return 4321 end })
  drawnLive[tostring(out and (out.speciesId or out.species))] = true
end
local nLive = 0
for _ in pairs(drawnLive) do nLive = nLive + 1 end
T.check(nLive > 20, "RANDOM: rolls from the synced table still redraw (" .. nLive .. " species)")
set("spawn_mode", "complete")

-- ------- a surfing roll the engine reports with no terrain, or as land (Emerald's rules read
-- the tile themselves), is still a water roll: Sootopolis's all-Magikarp surf table gets its
-- pool's species, not the cart's Magikarp

local SOOT = "EM_SOOTOPOLIS_CITY"
local slotToId = {}
for _, c in ipairs(ms.candidates({ maxGeneration = 9, includeSpecial = true })) do
  for _, id in ipairs({ c.id, unpack(c.variants or {}) }) do
    local r = loader.content.pokemon:get(id)
    if r and r.index then slotToId[tonumber(r.index)] = id end
  end
end
local sootPools = ms.poolFor(SOOT, "water")
local sootSlots = live[SOOT].water.slots
for _, terrain in ipairs({ "nil", "land" }) do
  local magikarp, outside = 0, 0
  for n = 1, 40 do
    local i = (n % #sootSlots) + 1
    local s = sootSlots[i]
    local out = Runtime.call("encounter.species", function(e) return e end,
      { species = P.keyName(s.species), speciesId = s.species, level = s.minLevel },
      { mapId = SOOT, terrain = terrain ~= "nil" and terrain or nil, rng = function() return 4321 end })
    local id = out and slotToId[tonumber(out.speciesId or out.species)]
    if id == "MAGIKARP" then magikarp = magikarp + 1 end
    -- the roll could have come from any slot its level fits (all five are Magikarp)
    local inPool = false
    for j, js in ipairs(sootSlots) do
      if s.minLevel >= js.minLevel and s.minLevel <= js.maxLevel then
        for _, sid in ipairs(sootPools[j]) do if sid == id then inPool = true end end
      end
    end
    if not inPool then outside = outside + 1 end
  end
  T.eq(outside, 0, "Sootopolis surfing (terrain " .. terrain .. "): every encounter comes from its slot's pool")
  T.check(magikarp < 40, "Sootopolis surfing (terrain " .. terrain .. "): not all Magikarp")
end
-- a table whose slots all held one species now has a species per slot
local sootSpecies = {}
for _, slot in ipairs(ms.tableFor(SOOT, "water").slots) do sootSpecies[slot.species] = true end
local nSoot = 0
for _ in pairs(sootSpecies) do nSoot = nSoot + 1 end
T.check(nSoot > 1, "Sootopolis's all-Magikarp surf table becomes several species (" .. nSoot .. ")")

-- ------- the other modes are untouched: SEEDED still has no pools

set("spawn_mode", "seeded")
T.eq(ms.poolFor(MAP, "land"), nil, "poolFor answers nil outside COMPLETE DEX")

run.release()
T.finish("modern_spawns complete dex (Emerald)")
