-- Standalone: luajit mods/modern_spawns/tests/time_of_day_test.lua (from the
-- gen1recomp root). TIME OF DAY SPAWNS against the hand-built world and the
-- clock against fake engine modules:
--   * OFF builds exactly what 0.13.x built (pinned digests of ten seeds);
--   * the night pass never moves a day roster (it has its own memory);
--   * STRICT never shows an "only" species at the other time; PREFER weights;
--   * COMPLETE still places every species;
--   * the clock follows WoobleDex's Clock Source and its boundaries.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local bit = require("bit")

local Config = H.module("src/config.lua")
local Rng = H.module("src/rng.lua")
local MapContext = H.module("src/map_context.lua")
local SpeciesPool = H.module("src/species_pool.lua")
local Generator = H.module("src/generator.lua")
local makeClock = H.module("src/clock.lua")

-- Pidgey and Sentret only by day, Hoothoot only at night, Zubat mostly at night
local TIME = { version = 1, species = { [16] = "D", [161] = "D", [163] = "N", [41] = "n", [17] = "d" },
               forms = {} }

local function digest(text)
  local h = 2166136261
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i))
    h = bit.tobit(h * 16777619)
  end
  return bit.tohex(h)
end

local function ctxFor(seed, mode, tod, timeData, only)
  local world = H.world()
  local pool = SpeciesPool.build(world, H.profiles(), Config.generationOfDex, timeData)
  return { world = world, pool = pool, seed = seed, maxGen = 9, config = Config.SpawnConfig,
           dataVersion = 1, MapContext = MapContext, Rng = Rng,
           selection = Config.SpawnConfig.selection[mode], timeOfDay = tod, only = only }
end

local function build(seed, mode, tod, timeData, only)
  local ctx = ctxFor(seed, mode, tod, timeData, only)
  return mode == "complete" and Generator.buildAtlas(ctx) or Generator.buildAll(ctx)
end

-- ------- OFF: exactly 0.13.x (digests recorded on 0.13.3 before this option existed)

for mode, want in pairs({ seeded = "4d2e4e40", complete = "4e12442f" }) do
  local plain, withData = {}, {}
  for seed = 1, 10 do
    plain[#plain + 1] = H.serialize(build(seed, mode, nil, nil))
    withData[#withData + 1] = H.serialize(build(seed, mode, nil, TIME))
  end
  -- the golden probe hashed the ten serialisations back to back
  T.eq(digest(table.concat(plain)), want, mode .. ": OFF builds what 0.13.x built")
  T.eq(digest(table.concat(withData)), want, mode .. ": OFF ignores the day/night data")
end

-- ------- the pool carries each species' time

local pool = SpeciesPool.build(H.world(), H.profiles(), Config.generationOfDex, TIME)
T.eq(pool.byId.HOOTHOOT.tod, "night", "Hoothoot comes out at night")
T.eq(pool.byId.HOOTHOOT.todOnly, true, "only at night")
T.eq(pool.byId.ZUBAT.tod, "night", "Zubat mostly at night")
T.eq(pool.byId.ZUBAT.todOnly, false, "but not only")
T.eq(pool.byId.RAIKOU.tod, nil, "a legendary keeps no time")
T.eq(pool.byId.RATTATA.tod, nil, "Rattata keeps no time")

-- ------- the night pass never moves a day roster

local isolated, nights = true, true
for seed = 1, 6 do
  local both = build(seed, "seeded", "strict", TIME)
  local dayOnly = build(seed, "seeded", "strict", TIME, "day")
  for mapId, result in pairs(dayOnly) do
    for kind, def in pairs(result) do
      if kind ~= "explain" and H.serialize(both[mapId][kind]) ~= H.serialize(def) then
        isolated = false
      end
    end
    if not both[mapId].night then nights = false end
  end
end
T.check(isolated, "the day rosters are the same with or without the night pass")
T.check(nights, "every map has a night roster")

-- ------- STRICT keeps "only" species to their time; PREFER weights

local function count(result, period, counts)
  for _, entry in pairs(result) do
    local view = period == "night" and entry.night or entry
    for kind, def in pairs(view or {}) do
      if kind ~= "explain" and kind ~= "pools" and kind ~= "night" and type(def) == "table" then
        for _, slot in ipairs(def.slots or def) do
          counts[slot.species] = (counts[slot.species] or 0) + 1
        end
      end
    end
  end
end

for _, mode in ipairs({ "seeded", "complete" }) do
  local day, night = {}, {}
  for seed = 1, 30 do
    local result = build(seed, mode, "strict", TIME)
    count(result, "day", day)
    count(result, "night", night)
  end
  T.eq(day.HOOTHOOT, nil, mode .. " STRICT: no Hoothoot by day")
  T.eq(night.PIDGEY, nil, mode .. " STRICT: no Pidgey at night")
  T.eq(night.SENTRET, nil, mode .. " STRICT: no Sentret at night")
  T.check((night.HOOTHOOT or 0) > 0, mode .. " STRICT: Hoothoot comes out at night")
  T.check((day.PIDGEY or 0) > 0, mode .. " STRICT: Pidgey by day")
end

local day, night = {}, {}
for seed = 1, 30 do
  local result = build(seed, "seeded", "prefer", TIME)
  count(result, "day", day)
  count(result, "night", night)
end
T.check((night.HOOTHOOT or 0) > (day.HOOTHOOT or 0),
        ("PREFER: Hoothoot more at night (%d) than by day (%d)"):format(night.HOOTHOOT or 0, day.HOOTHOOT or 0))
T.check((day.PIDGEY or 0) > (night.PIDGEY or 0),
        ("PREFER: Pidgey more by day (%d) than at night (%d)"):format(day.PIDGEY or 0, night.PIDGEY or 0))

-- ------- COMPLETE still places every species (at some time)

for _, tod in ipairs({ "prefer", "strict" }) do
  local placed = {}
  local result = build(7, "complete", tod, TIME)
  for _, entry in pairs(result) do
    for _, pools in pairs(entry.pools or {}) do
      for _, list in pairs(pools) do
        for _, id in ipairs(list) do placed[id] = true end
      end
    end
  end
  local missing = {}
  for _, c in ipairs(pool.list) do
    if not c.special and not placed[c.id] then missing[#missing + 1] = c.id end
  end
  T.eq(table.concat(missing, " "), "", "COMPLETE " .. tod .. ": every species has a pool")
end

-- ------- the clock

local function fakeClock(opts)
  local hostHour = opts.hostHour or 12
  local Rtc = {
    hostInfo = function() return { hour = hostHour } end,
    enabled = function(session) return session and session.version == "emerald" end,
    getInfo = function() return { hour = hostHour } end,
    newTime = function(_, h) return { hours = h or 0 } end,
    calcTimeDifferenceRtc = function(info, offset)
      return { hours = (info.hour - (offset and offset.hours or 0)) % 24 }
    end,
  }
  local modules = { ["src.core.game3.rtc"] = Rtc }
  for k, v in pairs(opts.modules or {}) do modules[k] = v end
  local mod = {
    find = function(_, id)
      if id == "national_dex_gen3" and opts.exportSource then
        return { exports = { clockSource = function() return opts.exportSource end } }
      end
      return nil
    end,
    game = opts.game,
  }
  return makeClock({ mod = mod, generation = opts.generation or 3,
                     require = function(name)
                       local m = modules[name]
                       if not m then error("no module " .. name) end
                       return m
                     end })
end

local red = fakeClock({ generation = 1, hostHour = 19 })
T.eq(red.period(), "day", "19:00 is day")
for hour, want in pairs({ [20] = "night", [23] = "night", [0] = "night", [3] = "night", [4] = "day", [12] = "day" }) do
  T.eq(fakeClock({ generation = 1, hostHour = hour }).period(), want, hour .. ":00 is " .. want)
end
T.eq(fakeClock({ generation = 1, hostHour = 22, exportSource = "game" }).period(), "night",
     "Red/Blue/Yellow use the device clock whatever the source says")

local session = { version = "emerald", localTimeOffset = { hours = 10 } }
T.eq(fakeClock({ hostHour = 22, game = { session = session } }).period(), "day",
     "Emerald, no WoobleDex: the cart's clock (22:00 device, 10 hours back = noon)")
T.eq(fakeClock({ hostHour = 22, exportSource = "game", game = { session = session } }).period(), "day",
     "WoobleDex In-game: the cart's clock")
T.eq(fakeClock({ hostHour = 22, exportSource = "device", game = { session = session } }).period(), "night",
     "WoobleDex Device: the device clock")
T.eq(fakeClock({ hostHour = 22, game = { session = session,
       mods = { modOptions = { national_dex_gen3 = { clock_source = "device" } } } } }).period(), "night",
     "an older WoobleDex: its stored Clock Source")
T.eq(fakeClock({ hostHour = 22, exportSource = "game",
       game = { session = { version = "firered", localTimeOffset = { hours = 10 } } } }).period(), "night",
     "FireRed has no clock: the device's")

local gen2 = fakeClock({ generation = 2, hostHour = 12, game = { world = { tod = "NITE" } } })
T.eq(gen2.period({ daytime = "NITE" }), "night", "Gen 2 NITE is night")
T.eq(gen2.period({ daytime = "DARK" }), "night", "Gen 2 DARK is night")
T.eq(gen2.period({ daytime = "MORN" }), "day", "Gen 2 MORN is day")
T.eq(gen2.period({ tod = "DAY" }), "day", "Gen 2 fishing's tod")
T.eq(gen2.period(), "night", "Gen 2 without a ctx: the world's time of day")

local pinned = fakeClock({ generation = 1, hostHour = 12 })
pinned.pin("night")
T.eq(pinned.period(), "night", "a pinned period wins")
pinned.pin(nil)
T.eq(pinned.period(), "day", "unpinned, the clock again")

T.finish("modern_spawns time of day")
