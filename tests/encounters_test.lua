-- Standalone: luajit mods/modern_spawns/tests/encounters_test.lua (from the gen1recomp
-- root; needs Crystal and Emerald imported, mods/national_dex_gen3, and the sibling
-- ../national_dex). exports.encounters, the odds the WoobNav shows:
--   * every section adds up to 100, and every species a COMPLETE pool can turn a slot into is
--     listed, at the share tableFor + poolFor work out to;
--   * LIMITED lists tableFor's species alone;
--   * Gen 2 grass: the time of day now, or every time with time = "all";
--   * TIME OF DAY SPAWNS STRICT: a night-only species is listed by night, not by day;
--   * the game's own Old Rod (and Gen 1's Good Rod) are listed as the cart has them;
--   * RANDOM: no fixed walking list; OFF: the game's own tables, `active` false;
--   * currentMap follows map.entered; areaName names the place;
--   * reading never moves a table (the wild rosters are the same before and after).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local function load(game, gen, options)
  local data, mods
  if gen == 3 then
    H.mountGen3(game)
    data = H.gen3Data(game)
    mods = { "mods/national_dex_gen3", "mods/modern_spawns" }
  elseif gen == 2 then
    data = H.gen2Data(game)
    mods = { "mods/modern_spawns" }
  else
    data = require("src.core.Data")
    data:load()
    mods = { "../national_dex", "mods/modern_spawns" }
  end
  local run = T.sdk.loadMods(mods, { data = data, generation = gen })
  T.eq(#run.errors, 0, game .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "ODDS" }
  local o = { enabled = "on", max_generation = "9" }
  for k, v in pairs(options or {}) do o[k] = v end
  loader.modOptions.modern_spawns = o
  if loader.modOptions.national_dex then loader.modOptions.national_dex.national_dex = "on" end
  local set, game_ = H.manager(loader)
  game_.data = data
  return run, loader.exports.modern_spawns, set, loader
end

local function sums(enc, label)
  local bad = {}
  for _, s in ipairs(enc.sections) do
    local total = 0
    for _, m in ipairs(s.mons) do total = total + m.chance end
    if math.abs(total - 100) > 1e-6 then bad[#bad + 1] = s.method .. ":" .. total end
  end
  T.eq(table.concat(bad, " "), "", label .. ": every section adds up to 100")
end

local function find(enc, method, id, time)
  for _, s in ipairs(enc.sections) do
    if s.method == method and (time == nil or s.time == time) then
      for _, m in ipairs(s.mons) do
        if m.id == id then return m end
      end
    end
  end
  return nil
end

-- the walking roster's species, as the hooks hand it the engine (a cheap fingerprint)
local function roster(ex, mapId)
  local t = ex.tableFor(mapId, "grass") or {}
  local out = {}
  local function add(slots) for _, s in ipairs(slots or {}) do out[#out + 1] = tostring(s.species) end end
  if t.slots and t.slots[1] then add(t.slots) else for _, k in ipairs({ "MORN", "DAY", "NITE" }) do add((t.slots or {})[k]) end end
  return table.concat(out, ",")
end

-- ======================================================== Red (Gen 1)
-- (first: a Gen 3 mount in the same process changes what Data:load reads)

do
  local run, ex = load("red", 1, { spawn_mode = "seeded" })
  local enc = ex.encounters("ROUTE_12")
  sums(enc, "Red Route 12")
  local methods = {}
  for _, s in ipairs(enc.sections) do methods[s.method] = s end
  T.check(methods.old and methods.old.mons[1].id == "MAGIKARP", "Red: the Old Rod is Magikarp")
  T.check(methods.good and #methods.good.mons == 2, "Red: the Good Rod is two species alike")
  T.check(methods.super ~= nil, "Red: the Super Rod's generated catches")
  T.eq(ex.areaName("ROUTE_12"), "ROUTE 12", "the Town Map's name")
  T.eq(#ex.encounters("REDS_HOUSE_1F").sections, 0, "a house lists nothing")
  T.eq(#ex.encounters("PALLET_TOWN").sections, 3, "Pallet Town: its water's three rods")
  run.release()
end

-- ======================================================== Emerald (Gen 3)

do
  local run, ex, set, loader = load("emerald", 3)
  local mapId = "EM_ROUTE101"
  local before = roster(ex, mapId)
  local enc = ex.encounters(mapId)
  T.check(enc ~= nil and enc.active == true and enc.random == false, "Emerald: active, COMPLETE")
  T.eq(enc.mapId, mapId, "the map asked about")
  sums(enc, "Emerald Route 101")
  -- every pool member listed, at its share: slot odds / pool size
  local t, pools = ex.tableFor(mapId, "land"), ex.poolFor(mapId, "land")
  local LAND = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
  local want = {}
  for i, slot in ipairs(t.slots) do
    local list = pools and pools[i]
    if list and #list > 0 then
      for _, id in ipairs(list) do want[id] = (want[id] or 0) + LAND[i] / #list end
    else
      want[slot.species] = (want[slot.species] or 0) + LAND[i]
    end
  end
  local wrong = {}
  for id, chance in pairs(want) do
    local m = find(enc, "grass", id)
    if not m or math.abs(m.chance - chance) > 1e-6 then wrong[#wrong + 1] = id end
  end
  T.eq(table.concat(wrong, " "), "", "every pool member at its share of the slot")
  T.check(#enc.sections[1].mons > #t.slots / 3, "more species than the table's own slots (the pools)")
  -- the Old Rod as the cart has it (Route 104 has water and fish)
  local fish = ex.encounters("EM_ROUTE104")
  local old
  for _, s in ipairs(fish and fish.sections or {}) do if s.method == "old" then old = s end end
  T.check(old ~= nil and #old.mons > 0, "Route 104: the Old Rod's catches are listed")
  sums(fish, "Emerald Route 104")
  T.eq(roster(ex, mapId), before, "reading the odds moves no table")
  -- the player's map and its name
  loader.events:emit("map.entered", { mapId = mapId })
  T.eq(ex.currentMap(), mapId, "currentMap follows map.entered")
  T.check(type(ex.areaName(mapId)) == "string" and ex.areaName(mapId) ~= "", "the place has a name")
  T.eq(ex.encounters().mapId, mapId, "encounters() reads the player's map")
  -- LIMITED: tableFor's species alone
  set("spawn_mode", "seeded")
  local lim = ex.encounters(mapId)
  local slotsOf = {}
  for _, s in ipairs(ex.tableFor(mapId, "land").slots) do slotsOf[s.species] = true end
  local extra = {}
  for _, m in ipairs(lim.sections[1].mons) do if not slotsOf[m.id] then extra[#extra + 1] = m.id end end
  T.eq(table.concat(extra, " "), "", "LIMITED: only the table's own species")
  sums(lim, "LIMITED")
  -- RANDOM: nothing fixed to walk into
  set("spawn_mode", "random")
  local rnd = ex.encounters(mapId)
  T.eq(rnd.random, true, "RANDOM is flagged")
  T.eq(find(rnd, "grass", (next(want))), nil, "RANDOM: no fixed walking list")
  -- OFF: the game's own tables
  set("spawn_mode", "complete")
  set("enabled", "off")
  local off = ex.encounters(mapId)
  T.check(off ~= nil and off.active == false, "OFF: still answered, `active` false")
  T.check(find(off, "grass", "POOCHYENA") ~= nil or find(off, "grass", "ZIGZAGOON") ~= nil
          or find(off, "grass", "WURMPLE") ~= nil, "OFF: the cart's Route 101 Pokemon")
  sums(off, "OFF")
  run.release()
end

-- ======================================================== Emerald, TIME OF DAY STRICT

do
  local run, ex = load("emerald", 3, { time_of_day = "strict" })
  -- a night-only species somewhere in the day's pools never shows by day
  local leaks, nights = {}, 0
  for _, mapId in ipairs({ "EM_ROUTE101", "EM_ROUTE102", "EM_ROUTE103", "EM_ROUTE110", "EM_ROUTE119", "EM_PETALBURG_WOODS" }) do
    local day, night = ex.encounters(mapId, { period = "day" }), ex.encounters(mapId, { period = "night" })
    if day and night then
      sums(day, mapId .. " by day")
      sums(night, mapId .. " by night")
      for _, s in ipairs(day.sections) do
        for _, m in ipairs(s.mons) do
          local p = ex.profileOf(m.id)
          if p and p.timeOfDayOnly and p.timeOfDay == "night" and m.pooled then leaks[#leaks + 1] = mapId .. ":" .. m.id end
        end
      end
      nights = nights + 1
      T.eq(night.period, "night", mapId .. ": the night's list says so")
    end
  end
  T.check(nights >= 4, "day and night lists read (" .. nights .. ")")
  T.eq(table.concat(leaks, " "), "", "STRICT: a night-only pool member never listed by day")
  run.release()
end

-- ======================================================== Crystal (Gen 2)

do
  local run, ex = load("crystal", 2)
  local all = ex.encounters("ROUTE_29", { time = "all" })
  local times = {}
  for _, s in ipairs(all.sections) do if s.method == "grass" then times[s.time] = true end end
  T.check(times.MORN and times.DAY and times.NITE, "Crystal: time = all lists MORN, DAY and NITE")
  sums(all, "Crystal Route 29")
  local nite = ex.encounters("ROUTE_29", { time = "NITE" })
  local n = 0
  for _, s in ipairs(nite.sections) do if s.method == "grass" then n = n + 1; T.eq(s.time, "NITE", "NITE asked: NITE listed") end end
  T.eq(n, 1, "one grass list for one time")
  local water = ex.encounters("ROUTE_32", { time = "DAY" })
  local methods = {}
  for _, s in ipairs(water.sections) do methods[s.method] = true end
  T.check(methods.surf and methods.old and methods.good and methods.super,
          "Route 32: surfing and all three rods")
  sums(water, "Crystal Route 32")
  local inland = ex.encounters("ROUTE_29", { time = "DAY" })
  local rods = false
  for _, s in ipairs(inland.sections) do if s.method == "good" or s.method == "super" or s.method == "old" then rods = true end end
  T.eq(rods, false, "Route 29 has no water: no rods listed")
  run.release()
end

T.finish("modern_spawns encounters (odds per map)")
