-- Standalone: luajit mods/modern_spawns/tests/time_of_day_gen2_test.lua (from
-- the gen1recomp root; needs Crystal imported). TIME OF DAY SPAWNS on Gold/
-- Silver/Crystal, whose grass already holds MORN, DAY and NITE slots and whose
-- encounters carry their own time of day (ctx.daytime):
--   * STRICT: a species that only comes out at night stays out of morning and
--     day slots, one that only comes out by day out of night slots;
--   * COMPLETE draws by day never yield an only-at-night species;
--   * surfing has a night roster, chosen by the encounter's own time of day.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")

local data = H.gen2Data("crystal")
local run = T.sdk.loadMods({ "mods/modern_spawns" }, { data = data, generation = 2 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "JOHTO" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", spawn_mode = "seeded",
                                    time_of_day = "strict" }
local set = H.manager(loader)
local api = loader.exports.modern_spawns
local live = data.gen2Encounters
local profile = {}
for _, c in ipairs(api.candidates({ maxGeneration = 9 })) do profile[c.id] = c end

local function roll(mapId, terrain, daytime)
  return Runtime.call("encounter.roll", function(tables) return tables end, live,
    { mapId = mapId, terrain = terrain, daytime = daytime, kind = "wild",
      rng = function() return 0 end })
end

-- ------- STRICT keeps each slot's time

local wrong, own = {}, 0
for _, mode in ipairs({ "seeded", "complete" }) do
  set("spawn_mode", mode)
  api.invalidate()
  for mapId in pairs(live.grass) do
    local tab = api.tableFor(mapId, "grass")
    for _, time in ipairs({ "MORN", "DAY", "NITE" }) do
      for _, slot in ipairs(tab and tab.slots[time] or {}) do
        local c = profile[slot.species]
        local period = time == "NITE" and "night" or "day"
        if c and c.timeOfDayOnly and c.timeOfDay ~= period then
          wrong[#wrong + 1] = mode .. " " .. mapId .. " " .. time .. " " .. slot.species
        elseif c and c.timeOfDayOnly then
          own = own + 1
        end
      end
    end
  end
end
T.eq(table.concat(wrong, ", ", 1, math.min(#wrong, 5)), "",
     "STRICT: grass slots never hold a species out only at the other time")
T.check(own > 20, "only-by-day and only-at-night species still fill their own slots (" .. own .. ")")

-- ------- COMPLETE: a daytime draw is never an only-at-night species

set("spawn_mode", "complete")
api.invalidate()
local nightOnlyByDay, draws = {}, 0
for mapId in pairs(live.grass) do
  local tab = api.tableFor(mapId, "grass")
  for i, slot in ipairs(tab and tab.slots.DAY or {}) do
    draws = draws + 1
    local out = Runtime.call("encounter.species", function(e) return e end,
      { species = slot.species, level = slot.level, slot = i },
      { mapId = mapId, terrain = "grass", daytime = "DAY", kind = "wild",
        rng = function(lo) return lo end })
    local c = out and profile[out.species]
    if c and c.timeOfDayOnly and c.timeOfDay == "night" then
      nightOnlyByDay[#nightOnlyByDay + 1] = mapId .. " " .. out.species
    end
  end
end
T.check(draws > 300, "COMPLETE daytime draws (" .. draws .. ")")
T.eq(table.concat(nightOnlyByDay, ", ", 1, math.min(#nightOnlyByDay, 5)), "",
     "COMPLETE STRICT: a daytime draw is never an only-at-night species")

-- ------- surfing follows the encounter's own time of day

set("spawn_mode", "seeded")
api.invalidate()
local twins, follows = 0, true
for mapId in pairs(live.water) do
  local day, night = api.tableFor(mapId, "water", "day"), api.tableFor(mapId, "water", "night")
  if day and night then
    if H.serialize(day.slots) ~= H.serialize(night.slots) then twins = twins + 1 end
    local atDay = roll(mapId, "water", "DAY").water[mapId]
    local atNight = roll(mapId, "water", "NITE").water[mapId]
    if H.serialize(atDay.slots) ~= H.serialize(day.slots)
      or H.serialize(atNight.slots) ~= H.serialize(night.slots) then
      follows = false
    end
  end
end
T.check(twins > 0, "surfing has a night roster (" .. twins .. " maps differ)")
T.check(follows, "a surfing roll gets the roster for its own time of day")

-- the grass keeps one table (its slots carry the time), whatever the period
local same = true
for mapId in pairs(live.grass) do
  if H.serialize(api.tableFor(mapId, "grass", "day")) ~= H.serialize(api.tableFor(mapId, "grass", "night")) then
    same = false
  end
end
T.check(same, "grass is one table for every time of day")

run.release()
T.finish("modern_spawns time of day (Crystal)")
