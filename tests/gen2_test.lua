-- Standalone: luajit mods/modern_spawns/tests/gen2_test.lua (from the
-- gen1recomp root; needs Gold and Crystal imported under gold/ and crystal/).
-- The Gen 2 adapter against the carts' real tables: kind-first encounter
-- tables, three time-of-day grass lists, water, fish groups, the engine's
-- own Gen 2 rolls (src/battle/gen2/Encounter.lua) run over what the hooks
-- hand them, and the paths that must stay vanilla. Silver shares Gold's
-- engine and layout and is not imported here.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Encounter = require("src.battle.gen2.Encounter")

local TIMES = { "MORN", "DAY", "NITE" }

local function load(version)
  local data = H.gen2Data(version)
  local run = T.sdk.loadMods({ H.modRoot() .. "/tests/fixtures/modern_gen2/national_dex",
                               "mods/modern_spawns" }, { data = data, generation = 2 })
  T.eq(#run.errors, 0, version .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  T.check(run.mods.modern_spawns and run.mods.modern_spawns.state == "loaded",
          version .. ": modern_spawns targets Gen 2")
  run.loader.modSave.modern_spawns = { seed = "JOHTO" }
  run.loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  return run, data
end

local function roll(live, mapId, terrain, daytime, kind)
  return Runtime.call("encounter.roll", function(tables) return tables end, live,
    { mapId = mapId, terrain = terrain, daytime = daytime, kind = kind or "wild",
      rng = function(n) return 0 end })
end

-- a fixed "random" for the engine's own slot pick: always the given value
local function fixed(value) return function() return value end end

-- the core table checks, run on each cart
local function checkTables(version, data, api)
  local live = data.gen2Encounters
  local registered = function(id) return data.pokemon[id] ~= nil end

  local grassMaps = 0
  for mapId, vanilla in pairs(live.grass) do
    grassMaps = grassMaps + 1
    local tables = roll(live, mapId, "grass", "DAY")
    local mine = tables.grass[mapId]
    T.check(mine ~= vanilla, version .. " " .. mapId .. " grass is generated")
    local other = next(live.grass) == mapId and select(1, next(live.grass, mapId)) or next(live.grass)
    T.eq(tables.grass[other], live.grass[other], version .. " other maps read the game's own")
    for _, time in ipairs(TIMES) do
      T.eq(mine.rates[time], vanilla.rates[time], version .. " " .. mapId .. " " .. time .. " rate")
      T.eq(#mine.slots[time], #vanilla.slots[time], version .. " " .. mapId .. " " .. time .. " slots")
      for i, slot in ipairs(vanilla.slots[time]) do
        T.eq(mine.slots[time][i].level, slot.level, version .. " " .. mapId .. " level")
        T.check(registered(mine.slots[time][i].species), version .. " " .. mapId .. " registered")
      end
      -- the engine's own Gen 2 roll over the handed table
      local enc = Encounter.grassSlot(tables, mapId, time, fixed(0))
      T.eq(enc and enc.species, mine.slots[time][1].species,
           version .. " " .. mapId .. " " .. time .. ": Encounter.grassSlot rolls it")
    end
    -- one vanilla species -> one new species, across all three times
    local mapped = {}
    for _, time in ipairs(TIMES) do
      for i, slot in ipairs(vanilla.slots[time]) do
        local new = mine.slots[time][i].species
        if mapped[slot.species] and mapped[slot.species] ~= new then
          T.check(false, version .. " " .. mapId .. ": " .. slot.species
                  .. " became two species across the day")
        end
        mapped[slot.species] = new
      end
    end
  end
  T.check(grassMaps > 50, version .. ": every grass map (" .. grassMaps .. ")")

  for mapId, vanilla in pairs(live.water) do
    local tables = roll(live, mapId, "water")
    local mine = tables.water[mapId]
    T.eq(mine.rate, vanilla.rate, version .. " " .. mapId .. " water rate")
    T.eq(#mine.slots, #vanilla.slots, version .. " " .. mapId .. " water slots")
    local enc = Encounter.waterSlot(tables, mapId, fixed(0))
    T.eq(enc and enc.species, mine.slots[1].species,
         version .. " " .. mapId .. ": Encounter.waterSlot rolls it")
  end
end

-- ============================================================== Gold

local run, data = load("gold")
local loader = run.loader
local api = loader.exports.modern_spawns
local set, game = H.manager(loader)
-- Game2 has persistOptions and no writeOptions
game.writeOptions = nil
game.persistOptions = function(g) g.persisted = (g.persisted or 0) + 1 end
game.data = data -- live_sync writes through mod.game.data; the stub has none by default
T.eq(api.generation(), 2, "the Gen 2 adapter runs")
T.check(api.isActive(), "active on Gold")

checkTables("gold", data, api)
local live = data.gen2Encounters

-- ------- live_sync: game.data.gen2Encounters itself carries the species a
-- raw reader (a wild-encounter guide, say) would see, not just tableFor

local vanillaRoute1Species, vanillaRoute1Rates = {}, {}
for _, time in ipairs(TIMES) do
  local list = (live.grass.ROUTE_1 or {}).slots and live.grass.ROUTE_1.slots[time]
  vanillaRoute1Species[time] = {}
  for i, slot in ipairs(list or {}) do vanillaRoute1Species[time][i] = slot.species end
  vanillaRoute1Rates[time] = (live.grass.ROUTE_1 or {}).rates
    and live.grass.ROUTE_1.rates[time]
end

loader.events:emit("save.loaded", {})
local liveRoute1 = live.grass.ROUTE_1
local generatedRoute1 = api.tableFor("ROUTE_1", "grass")
if liveRoute1 and generatedRoute1 then
  local matches = true
  for _, time in ipairs(TIMES) do
    for i, slot in ipairs(liveRoute1.slots[time] or {}) do
      if slot.species ~= (generatedRoute1.slots[time][i] or {}).species then matches = false end
    end
  end
  T.check(matches, "live_sync: ROUTE_1's live grass matches tableFor, every time of day")
  local ratesOk = true
  for time, rate in pairs(liveRoute1.rates or {}) do
    if rate ~= vanillaRoute1Rates[time] then ratesOk = false end
  end
  T.check(ratesOk, "and its rates are untouched")

  set("enabled", "off")
  local restoredOk = true
  for _, time in ipairs(TIMES) do
    for i, slot in ipairs(live.grass.ROUTE_1.slots[time] or {}) do
      if slot.species ~= vanillaRoute1Species[time][i] then restoredOk = false end
    end
  end
  T.check(restoredOk, "OFF restores ROUTE_1's original grass species, every time of day")
  set("enabled", "on")
end

-- ------- day/night: a night-only role stays nocturnal

local route29 = api.tableFor("ROUTE_29", "grass")
local nightOnly = route29.slots.NITE[1].species
local dayRoster = {}
for _, time in ipairs({ "MORN", "DAY" }) do
  for _, s in ipairs(route29.slots[time]) do dayRoster[s.species] = true end
end
T.check(not dayRoster[nightOnly] or live.grass.ROUTE_29.slots.NITE[1].species == nightOnly,
        "Route 29's night-only role is not a daytime species (" .. nightOnly .. ")")

-- ------- vanilla paths

local contest = roll(live, "NATIONAL_PARK", "grass", "DAY", "contest")
T.eq(contest, live, "the Bug Contest keeps the game's table")
local script = roll(live, "ROUTE_29", "grass", "DAY", "script")
T.eq(script, live, "randomwildmon scripts keep the game's table")
local swarmView = {}
for k, v in pairs(live) do swarmView[k] = v end
swarmView.grass = setmetatable({ ROUTE_35 = live.swarmGrass.ROUTE_35 }, { __index = live.grass })
T.eq(roll(swarmView, "ROUTE_35", "grass", "DAY"), swarmView, "a swarm is left alone")

-- ------- fishing

local groupId = data.gen2Maps.ROUTE_29.fishGroup
local group = live.fishGroups[groupId]
local seenCtx
local function fish(rod, mapId, candidates, ctx)
  return Runtime.call("encounter.fishing", function(_, _, c, x) seenCtx = x return c end,
                      rod, mapId, candidates, ctx)
end
local ctx = { fishGroup = groupId, swarm = 0, encounters = live, tod = "NITE", daytime = "NITE" }
local row = fish("SUPER_ROD", "ROUTE_29", group, ctx)
T.check(row ~= group, "the Super Rod gets a generated group row")
T.eq(seenCtx, ctx, "the time-of-day ctx is forwarded to the engine")
T.eq(row.chance, group.chance, "the bite gate is the game's")
T.eq(row.old, group.old, "the Old Rod rows are the game's")
T.eq(#row.super, #group.super, "the Super Rod keeps its row count")
for i, r in ipairs(row.super) do
  T.eq(r.chance, group.super[i].chance, "super row " .. i .. " keeps its odds")
  T.eq(r.day, nil, "super row " .. i .. " has no day/night variant left")
  T.check(data.pokemon[r.species] ~= nil, "super row " .. i .. " is registered")
end
local caught = Encounter.fish({ fishGroups = { hooked = row }, timeFishGroups = live.timeFishGroups },
  "hooked", "super", "NITE", fixed(0))
T.eq(caught and caught.species, row.super[1].species, "Encounter.fish lands the generated catch")
local good = fish("GOOD_ROD", "ROUTE_29", group, ctx)
T.eq(#good.good, #group.good, "the Good Rod is generated too")
T.eq(fish("OLD_ROD", "ROUTE_29", group, ctx), group, "the Old Rod is the game's")
T.eq(fish("SUPER_ROD", "ROUTE_29", group, { fishGroup = groupId, swarm = 1 }), group,
     "a fishing swarm keeps its own fish")

-- ------- preview

local dist = Runtime.call("encounter.table", function(d) return d end, {},
                          { mapId = "ROUTE_29", terrain = "grass", preview = true })
local total = 0
for id, w in pairs(dist) do
  total = total + w
  local found = false
  for _, s in ipairs(route29.slots.DAY) do if s.species == id then found = true end end
  T.check(found, id .. " in the preview is in the DAY list")
end
T.eq(total, 100, "the preview's weights are the DAY percentages")

-- ------- generation cap

set("max_generation", "2")
for mapId in pairs(live.grass) do
  for _, time in ipairs(TIMES) do
    for _, s in ipairs(api.tableFor(mapId, "grass").slots[time]) do
      T.check(data.pokemon[s.species].dex <= 251, s.species .. " respects GEN 1-2 on " .. mapId)
    end
  end
end
set("max_generation", "9")
local before = game.persisted or 0
set("reroll_seed", "reroll")
T.check((game.persisted or 0) > before, "the mod's own option writes persist through Game2:persistOptions")
T.eq(loader.modOptions.modern_spawns.seed, api.seed(), "and the SEED row follows the reroll on Gold")

-- ------- RANDOM keeps the engine's slot and level

set("spawn_mode", "random")
T.eq(api.tableFor("ROUTE_29", "grass"), nil, "RANDOM has no fixed table")
local vslot = live.grass.ROUTE_29.slots.NITE[1]
local seen = {}
for _ = 1, 20 do
  local out = Runtime.call("encounter.species", function(e) return e end,
    { species = vslot.species, level = vslot.level, slot = 1 },
    { mapId = "ROUTE_29", terrain = "grass", daytime = "NITE", kind = "wild",
      rng = function(lo) return lo + 1 end })
  T.eq(out.level, vslot.level, "RANDOM keeps the rolled level")
  T.check(data.pokemon[out.species] ~= nil, "RANDOM draws a registered species")
  seen[out.species] = true
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
T.check(distinct > 1, "RANDOM varies on Gold (" .. distinct .. " species)")
local contestOut = Runtime.call("encounter.species", function(e) return e end,
  { species = "CATERPIE", level = 10 },
  { mapId = "NATIONAL_PARK", terrain = "grass", kind = "contest", rng = function(lo) return lo end })
T.eq(contestOut.species, "CATERPIE", "the Bug Contest's catch is never swapped")

-- ------- EVERY MAP

set("spawn_mode", "map")
loader.events:emit("map.entered", { mapId = "ROUTE_30" })
local first = H.serialize(api.tableFor("ROUTE_30", "grass"))
local changed = false
for _ = 1, 8 do
  loader.events:emit("map.entered", { mapId = "ROUTE_31" })
  loader.events:emit("map.entered", { mapId = "ROUTE_30" })
  if H.serialize(api.tableFor("ROUTE_30", "grass")) ~= first then changed = true break end
end
T.check(changed, "EVERY MAP redraws on Gold")
set("spawn_mode", "seeded")

-- ------- legendaries

set("legendaries", "on")
local homes = api.legendaryHomes()
local hostMap, hostKind, hosts
for mapId, byKind in pairs(homes) do
  for kind, list in pairs(byKind) do
    if not hostMap then hostMap, hostKind, hosts = mapId, kind, list end
  end
end
T.check(hostMap ~= nil, "Gold has legendary homes")
for _, early in ipairs({ "ROUTE_29", "ROUTE_30", "ROUTE_31", "ROUTE_46" }) do
  T.eq(homes[early], nil, early .. " hosts no legendary")
end
local hostSet = {}
for _, h in ipairs(hosts) do hostSet[h.id] = h.category end
local terrain = hostKind == "water" and "water" or "grass"
local vanilla = hostKind == "water" and live.water[hostMap].slots[1] or live.grass[hostMap].slots.DAY[1]
local function encounter(rngValue)
  return Runtime.call("encounter.species", function(e) return e end,
    { species = vanilla.species, level = vanilla.level, slot = 1 },
    { mapId = hostMap, terrain = terrain, daytime = "DAY", kind = "wild",
      rng = function(lo) return rngValue or lo end })
end
local won = encounter(1)
T.check(hostSet[won.species] ~= nil, "a winning roll brings a hosted legendary on "
  .. hostMap .. " (" .. tostring(won.species) .. ")")
T.eq(won.level, vanilla.level, "at the rolled level")
local caughtAll = {}
for id in pairs(hostSet) do caughtAll[id] = true end
game.save.pokedex = { seen = {}, caught = caughtAll }
T.check(not hostSet[encounter(1).species], "Gold's pokedex.caught stops a legendary")
game.save.pokedex = nil

run.release()

-- ============================================================== Crystal

local crun, cdata = load("crystal")
local cset, cgame = H.manager(crun.loader)
cgame.data = cdata
local capi = crun.loader.exports.modern_spawns
T.check(capi.isActive(), "active on Crystal")
checkTables("crystal", cdata, capi)

-- live_sync smoke check: Gen 2 is one adapter for Gold and Crystal alike,
-- so this only needs to confirm it also runs here, not re-prove the Gold
-- block's detail.
local cliveGrass = cdata.gen2Encounters.grass
local cmapId
for id in pairs(cliveGrass) do cmapId = id break end
if cmapId then
  local vanillaSpecies = {}
  for _, time in ipairs(TIMES) do
    local list = cliveGrass[cmapId].slots and cliveGrass[cmapId].slots[time]
    if list and list[1] then vanillaSpecies[time] = list[1].species end
  end
  crun.loader.events:emit("save.loaded", {})
  local generated = capi.tableFor(cmapId, "grass")
  local liveMatches = true
  for _, time in ipairs(TIMES) do
    local list = cliveGrass[cmapId].slots[time]
    if list and list[1] and generated.slots[time][1]
      and list[1].species ~= generated.slots[time][1].species then
      liveMatches = false
    end
  end
  T.check(liveMatches, "Crystal: live_sync runs here too (" .. cmapId .. ")")
  cset("enabled", "off")
  local restored = true
  for _, time in ipairs(TIMES) do
    local list = cliveGrass[cmapId].slots[time]
    if list and list[1] and vanillaSpecies[time]
      and list[1].species ~= vanillaSpecies[time] then
      restored = false
    end
  end
  T.check(restored, "Crystal: OFF restores it")
end
crun.release()

T.finish("modern_spawns gen2")
