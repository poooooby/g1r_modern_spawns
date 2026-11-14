-- Standalone: luajit mods/modern_spawns/tests/time_of_day_gen3_test.lua (from
-- the gen1recomp root; needs Emerald and FireRed imported and
-- mods/national_dex_gen3 installed). TIME OF DAY SPAWNS on the Gen 3 games:
--   * OFF set explicitly is exactly OFF by default;
--   * STRICT never shows an "only" species at the other time, in any mode, in
--     tables, draws or encounters; COMPLETE still places every species;
--   * PREFER: day species are met more by day, night species at night;
--   * the clock follows WoobleDex's Clock Source (In-game: the cart's clock;
--     Device), and turning it re-writes live sync's tables;
--   * FireRed, with no clock of its own, reads the device's.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local ManagerState = require("src.mods.ManagerState")
local Rtc = require("src.core.game3.rtc")

local function load(game)
  require("src.core.GameVersion").set(game)
  local data = H.gen3Data(game)
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" },
                             { data = data, generation = 3 })
  T.eq(#run.errors, 0, game .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "NIGHTS" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  local set, stub = H.manager(loader)
  local api = loader.exports.modern_spawns
  local maps = {}
  for id, rec in pairs(data.gen3Encounters) do
    if type(id) == "string" and data.maps[id] and (rec.land or rec.water) and api.tableFor(id, "land")
      or type(id) == "string" and data.maps[id] and rec.water and api.tableFor(id, "water") then
      maps[#maps + 1] = id
    end
  end
  table.sort(maps)
  local profile = {}
  for _, c in ipairs(api.candidates({ maxGeneration = 9 })) do profile[c.id] = c end
  return { data = data, run = run, loader = loader, set = set, stub = stub, api = api,
           maps = maps, profile = profile }
end

local function snapshot(g)
  local parts = {}
  for _, m in ipairs(g.maps) do
    for _, t in ipairs({ "land", "water", "fish.good", "fish.super" }) do
      parts[#parts + 1] = H.serialize(g.api.tableFor(m, t)) .. H.serialize(g.api.poolFor(m, t))
    end
  end
  return table.concat(parts)
end

-- the engine's own encounter result for a cart slot (encounters.lua mod_encounter)
local function encounter(g, mapId, terrain, slot)
  local P = g.data.gen3Pokemon
  return Runtime.call("encounter.species", function(e) return e end,
    { species = P.keyName(slot.species), speciesId = slot.species, level = slot.minLevel },
    { mapId = mapId, terrain = terrain, rng = function() return 4321 end })
end

-- ======================================================== Emerald

local em = load("emerald")
local api = em.api

-- ------- OFF set explicitly is OFF by default

for _, mode in ipairs({ "seeded", "complete" }) do
  em.set("spawn_mode", mode)
  api.invalidate()
  local default = snapshot(em)
  em.set("time_of_day", "off")
  api.invalidate()
  T.eq(snapshot(em), default, mode .. ": TIME OF DAY SPAWNS OFF is the default's tables")
  T.eq(api.settings().timeOfDay, "off", "settings() reports it")
end

-- ------- STRICT: an "only" species never at the other time

local slotIds = {}
for _, id in ipairs((function()
  local ids = {}
  for id in pairs(em.profile) do ids[#ids + 1] = id end
  return ids
end)()) do
  local rec = em.loader.content.pokemon:get(id)
  if rec and rec.index then slotIds[rec.index] = id end
end
local function speciesId(species)
  return type(species) == "number" and slotIds[species] or species
end

em.set("time_of_day", "strict")
local wrongTables, wrongEncounters, encounters = {}, {}, 0
local ownTime = 0 -- "only" species shown at their own time: the check is not vacuous
for _, mode in ipairs({ "seeded", "map", "random", "complete" }) do
  em.set("spawn_mode", mode)
  api.invalidate()
  for _, period in ipairs({ "day", "night" }) do
    api._pinPeriod(period)
    for _, m in ipairs(em.maps) do
      for _, t in ipairs({ "land", "water" }) do
        for _, source in ipairs({ api.tableFor(m, t), api.drawFor(m, t) }) do
          for _, s in ipairs(source and source.slots or {}) do
            local c = em.profile[speciesId(s.species)]
            if c and c.timeOfDayOnly and c.timeOfDay ~= period then
              wrongTables[#wrongTables + 1] = mode .. "/" .. period .. " " .. m .. " " .. tostring(c.id)
            elseif c and c.timeOfDayOnly then
              ownTime = ownTime + 1
            end
          end
        end
        local rec = em.data.gen3Encounters[m][t]
        for i, slot in ipairs(rec and rec.slots or {}) do
          if i % 3 == 1 then
            encounters = encounters + 1
            local out = encounter(em, m, t, slot)
            local c = out and em.profile[speciesId(out.species)]
            if c and c.timeOfDayOnly and c.timeOfDay ~= period then
              wrongEncounters[#wrongEncounters + 1] = mode .. "/" .. period .. " " .. m .. " " .. c.id
            end
          end
        end
      end
    end
  end
end
api._pinPeriod(nil)
T.eq(table.concat(wrongTables, ", ", 1, math.min(#wrongTables, 5)), "",
     "STRICT: tables and draws never show an only-by-day/only-at-night species at the other time")
T.check(ownTime > 100, "STRICT still shows them at their own time (" .. ownTime .. " slots)")
T.check(encounters > 1000, "simulated encounters (" .. encounters .. ")")
T.eq(table.concat(wrongEncounters, ", ", 1, math.min(#wrongEncounters, 5)), "",
     "STRICT: encounters never meet one at the other time")

-- ------- COMPLETE STRICT: every species catchable at its own time

em.set("spawn_mode", "complete")
api.invalidate()
local seen = {}
for _, period in ipairs({ "day", "night" }) do
  for _, m in ipairs(em.maps) do
    for _, t in ipairs({ "land", "water", "fish.good", "fish.super" }) do
      for _, list in pairs(api.poolFor(m, t, period) or {}) do
        for _, id in ipairs(list) do
          local c = em.profile[id]
          if not (c and c.timeOfDayOnly and c.timeOfDay ~= period) then seen[id] = true end
          if c and c.baseSpecies then seen[c.baseSpecies] = true end
        end
      end
    end
  end
end
for id, c in pairs(em.profile) do
  for _, v in ipairs(c.variants or {}) do if seen[v] then seen[id] = true end end
end
local missing = {}
for id, c in pairs(em.profile) do
  if not seen[id] and not (c.baseSpecies and seen[c.baseSpecies]) then missing[#missing + 1] = id end
end
table.sort(missing)
T.eq(table.concat(missing, " ", 1, math.min(#missing, 8)), "",
     "COMPLETE STRICT: every species can be caught at some time (" .. #missing .. " missing)")

-- ------- PREFER: day species by day, night species at night

em.set("time_of_day", "prefer")
local function shares(mode)
  em.set("spawn_mode", mode)
  local out = { day = { day = 0, night = 0, n = 0 }, night = { day = 0, night = 0, n = 0 } }
  for _, seed in ipairs({ "A1", "B2", "C3", "D4" }) do
    em.loader.modSave.modern_spawns = { seed = seed }
    api.invalidate()
    for _, period in ipairs({ "day", "night" }) do
      for _, m in ipairs(em.maps) do
        for _, t in ipairs({ "land", "water" }) do
          local tab = api.tableFor(m, t, period)
          for _, s in ipairs(tab and tab.slots or {}) do
            local c = em.profile[speciesId(s.species)]
            out[period].n = out[period].n + 1
            if c and c.timeOfDay then out[period][c.timeOfDay] = out[period][c.timeOfDay] + 1 end
          end
        end
      end
    end
  end
  return out
end
local s = shares("seeded")
local dayRatio = (s.day.day / s.day.n) / math.max(s.night.day / s.night.n, 1e-9)
local nightRatio = (s.night.night / s.night.n) / math.max(s.day.night / s.day.n, 1e-9)
T.check(dayRatio >= 2, ("PREFER: day species %.1fx as common in the day roster"):format(dayRatio))
T.check(nightRatio >= 2, ("PREFER: night species %.1fx as common in the night roster"):format(nightRatio))

-- COMPLETE picks from a slot's pool: weighted toward the period, never filtered
em.set("spawn_mode", "complete")
em.loader.modSave.modern_spawns = { seed = "NIGHTS" }
api.invalidate()
local picks = { day = { night = 0, n = 0 }, night = { night = 0, n = 0 } }
for _, period in ipairs({ "day", "night" }) do
  api._pinPeriod(period)
  for round = 1, 3 do
    for _, m in ipairs(em.maps) do
      local draw = api.drawFor(m, "land")
      for _, slot in ipairs(draw and draw.slots or {}) do
        local c = em.profile[speciesId(slot.species)]
        picks[period].n = picks[period].n + 1
        if c and c.timeOfDay == "night" then picks[period].night = picks[period].night + 1 end
      end
    end
  end
end
api._pinPeriod(nil)
local pickRatio = (picks.night.night / picks.night.n) / math.max(picks.day.night / picks.day.n, 1e-9)
T.check(pickRatio >= 2 and pickRatio <= 8,
        ("COMPLETE PREFER: night species %.1fx as likely to be drawn at night"):format(pickRatio))
T.check(picks.day.night > 0, "PREFER rules nothing out: night species are still drawn by day")

-- ------- the clock follows WoobleDex's Clock Source; a turn re-writes live sync

em.stub.data = em.data   -- live sync writes through mod.game.data
em.set("spawn_mode", "seeded")
em.set("time_of_day", "strict")
api.invalidate()
local changes = {}
em.loader.events:on("mod.modern_spawns.period_changed", function(ev) changes[#changes + 1] = ev end)
-- the cart's clock is 10 hours behind the device's: 22:00 on the device is noon in the game
em.stub.session = { version = "emerald", localTimeOffset = Rtc.newTime(0, 10, 0, 0) }
Rtc.setFixed("2026-01-01T22:00")
em.loader.modOptions.national_dex_gen3 = { clock_source = "game" }
T.eq(api.period(), "day", "Clock Source In-game: the cart's clock (noon)")
em.loader.events:emit("map.entered", { mapId = em.maps[1] })

local probe -- a map whose day and night land rosters differ
for _, m in ipairs(em.maps) do
  local d, n = api.tableFor(m, "land", "day"), api.tableFor(m, "land", "night")
  if d and n and H.serialize(d) ~= H.serialize(n) then probe = m break end
end
T.check(probe ~= nil, "some map's night roster differs from its day roster")

local state = setmetatable({ game = em.stub }, { __index = ManagerState })
ManagerState.setOption(state, "national_dex_gen3", "clock_source", "device")
T.eq(api.period(), "night", "Clock Source Device: the device's clock (22:00)")
T.eq(#changes, 1, "the turn is announced once")
T.eq(changes[1] and changes[1].period, "night", "as night")
local live = em.data.gen3Encounters[probe] and em.data.gen3Encounters[probe].land
local night = api.tableFor(probe, "land", "night")
local P = em.data.gen3Pokemon
local liveIds, nightIds = {}, {}
for i, slot in ipairs(live and live.slots or {}) do liveIds[i] = tostring(slot.species) end
for i, slot in ipairs(night and night.slots or {}) do
  local rec = em.loader.content.pokemon:get(slot.species)
  nightIds[i] = tostring(rec and rec.index)
end
T.eq(table.concat(liveIds, ","), table.concat(nightIds, ","),
     "live sync now holds the night roster (" .. tostring(probe) .. ")")
ManagerState.setOption(state, "national_dex_gen3", "clock_source", "game")
T.eq(api.period(), "day", "back to In-game: day again")
Rtc.setFixed(nil)
em.run.release()

-- ======================================================== FireRed

local fr = load("firered")
fr.stub.session = { version = "firered", localTimeOffset = Rtc.newTime(0, 10, 0, 0) }
fr.loader.modOptions.national_dex_gen3 = { clock_source = "game" }
Rtc.setFixed("2026-01-01T22:00")
fr.set("time_of_day", "prefer")
T.eq(fr.api.period(), "night", "FireRed has no clock: the device's, whatever the source")
Rtc.setFixed("2026-01-01T09:00")
T.eq(fr.api.period(), "day", "FireRed 09:00 is day")
Rtc.setFixed(nil)
fr.run.release()

T.finish("modern_spawns time of day (Gen 3)")
