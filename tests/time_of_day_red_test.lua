-- Standalone: luajit mods/modern_spawns/tests/time_of_day_red_test.lua (from
-- the gen1recomp root; needs Red imported and mods/national_dex installed).
-- TIME OF DAY SPAWNS on Red/Blue/Yellow, which have no clock of their own
-- (the device's, as WoobleDex's Red/Blue/Yellow path reads):
--   * every roll hands the engine the day or the night table, per roll;
--   * the Super Rod has a night roster too;
--   * live sync turns to the night roster when the period turns;
--   * STRICT keeps only-by-day and only-at-night species to their time.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMods({ "mods/national_dex", "mods/modern_spawns" },
                           { data = Data, modOptions = { national_dex = { national_dex = "on" } } })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "REDNIGHT" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", spawn_mode = "seeded",
                                    time_of_day = "strict" }
local set, game = H.manager(loader)
local api = loader.exports.modern_spawns

local maps = {}
for id, def in pairs(Data.encounters) do
  if type(id) == "string" and type(def) == "table" and def.grass then maps[#maps + 1] = id end
end
table.sort(maps)
local profile = {}
for _, c in ipairs(api.candidates({ maxGeneration = 9 })) do profile[c.id] = c end

-- ------- each roll gets the table for the time it is rolled at

local function roll(mapId, period)
  api._pinPeriod(period)
  local value = Runtime.call("encounter.roll", function(def) return def end, Data.encounters[mapId],
                             { mapId = mapId, terrain = "grass", rng = function() return 0 end })
  return value and value.grass
end

local differs, perRoll = 0, true
for _, m in ipairs(maps) do
  local day, night = api.tableFor(m, "grass", "day"), api.tableFor(m, "grass", "night")
  if day and night then
    if H.serialize(day) ~= H.serialize(night) then differs = differs + 1 end
    if H.serialize(roll(m, "day")) ~= H.serialize(day) then perRoll = false end
    if H.serialize(roll(m, "night")) ~= H.serialize(night) then perRoll = false end
  end
end
api._pinPeriod(nil)
T.check(perRoll, "every roll hands the engine the table for its time")
T.check(differs > #maps / 2, ("most maps have a night roster of their own (%d of %d)"):format(differs, #maps))

-- ------- STRICT on Red

local wrong, own = {}, 0
for _, m in ipairs(maps) do
  for _, period in ipairs({ "day", "night" }) do
    for _, terrain in ipairs({ "grass", "water" }) do
      local tab = api.tableFor(m, terrain, period)
      for _, slot in ipairs(tab and tab.slots or {}) do
        local c = profile[slot.species]
        if c and c.timeOfDayOnly and c.timeOfDay ~= period then
          wrong[#wrong + 1] = m .. "/" .. period .. " " .. slot.species
        elseif c and c.timeOfDayOnly then
          own = own + 1
        end
      end
    end
  end
end
T.eq(table.concat(wrong, ", ", 1, math.min(#wrong, 5)), "", "STRICT: nothing out at the wrong time")
T.check(own > 10, "STRICT: only-by-day and only-at-night species still out at their time (" .. own .. ")")

-- ------- the Super Rod's night roster

local rods = 0
for id in pairs(Data.field and Data.field.superRod or {}) do
  local d = api.tableFor(id, "superRod", "day")
  local n = api.tableFor(id, "superRod", "night")
  if d and n and H.serialize(d) ~= H.serialize(n) then rods = rods + 1 end
end
T.check(rods > 0, "the Super Rod has a night roster (" .. rods .. " maps differ)")

-- ------- live sync turns with the period

game.data = Data -- live_sync writes through mod.game.data
local probe
for _, m in ipairs(maps) do
  local d, n = api.tableFor(m, "grass", "day"), api.tableFor(m, "grass", "night")
  if d and n and H.serialize(d) ~= H.serialize(n) then probe = m break end
end
local function live(mapId)
  local out = {}
  for i, slot in ipairs(Data.encounters[mapId].grass.slots) do out[i] = slot.species end
  return table.concat(out, ",")
end
local function generated(mapId, period)
  local out = {}
  for i, slot in ipairs(api.tableFor(mapId, "grass", period).slots) do out[i] = slot.species end
  return table.concat(out, ",")
end
-- (a Red/Blue/Yellow mod may not reach the Gen 3 RTC module, so the device
-- clock is os.date there, as in WoobleDex; the period is pinned instead)
local cart = live(probe)
api._pinPeriod("day")
loader.events:emit("save.loaded", {})
T.eq(api.period(), "day", "pinned day")
T.eq(live(probe), generated(probe, "day"), "live sync holds the day roster")
local turns = {}
loader.events:on("mod.modern_spawns.period_changed", function(ev) turns[#turns + 1] = ev.period end)
api._pinPeriod("night")
loader.events:emit("map.entered", { mapId = probe })
T.eq(api.period(), "night", "pinned night")
T.eq(table.concat(turns, ","), "night", "the turn is announced")
T.eq(live(probe), generated(probe, "night"), "live sync turns to the night roster")
set("enabled", "off")
T.eq(live(probe), cart, "MODERN SPAWNS OFF still restores the cart's own table")
api._pinPeriod(nil)

run.release()
T.finish("modern_spawns time of day (Red)")
