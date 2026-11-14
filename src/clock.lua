-- The clock TIME OF DAY SPAWNS follows: "day" or "night" right now.
--
-- It is WoobleDex's clock (national_dex_gen3's CLOCK SOURCE option), so a
-- night species comes out exactly when WoobleDex's Day & Night look turns
-- dark and its night evolutions work:
--   Ruby/Sapphire/Emerald  the cart's own clock (CLOCK SOURCE In-game, the
--                          default), or the device's (Device)
--   FireRed/LeafGreen      the device clock: they have no clock of their own
--   Red/Blue/Yellow        the device clock (no clock either; WoobleDex's
--                          Red/Blue/Yellow path reads the device too)
--   Gold/Silver/Crystal    the cart's own clock, which the encounter already
--                          carries (ctx.daytime: MORN/DAY/NITE)
-- Night is 8 PM to 4 AM (WoobleDex src/clock.lua) everywhere but Gold/Silver/
-- Crystal, whose own clock turns NITE at 6 PM: there the game's night slots
-- and this clock must agree.
--
-- deps = { mod, generation, require?, os? }: require and os are injectable
-- for tests. Engine modules are reached with a guarded require (the mod
-- sandbox has no `package`); any failure falls back to the device clock.
return function(deps)
  local mod, generation = deps.mod, tonumber(deps.generation) or 1
  local requireFn = deps.require or require
  local osLib = deps.os or os

  local C = {}
  C.NIGHT_BEGIN, C.NIGHT_END = 20, 4

  local function engine(name)
    local ok, module = pcall(requireFn, name)
    if ok and type(module) == "table" then return module end
    return nil
  end

  local pinned
  -- Tests pin the period ("day"/"night"; nil follows the clock again).
  function C.pin(period)
    pinned = (period == "day" or period == "night") and period or nil
  end

  -- WoobleDex's CLOCK SOURCE: "game" or "device". Its export answers first
  -- (it knows its own option); an older WoobleDex is read from the loader's
  -- stored options; with no WoobleDex at all, the cart's clock.
  function C.clockSource()
    local okF, dex = pcall(function() return mod:find("national_dex_gen3") end)
    local fn = okF and type(dex) == "table" and type(dex.exports) == "table"
      and dex.exports.clockSource
    if type(fn) == "function" then
      local ok, value = pcall(fn)
      if ok and (value == "game" or value == "device") then return value end
    end
    local okS, stored = pcall(function()
      local options = mod.game.mods.modOptions
      return options and options.national_dex_gen3 and options.national_dex_gen3.clock_source
    end)
    if okS and (stored == "game" or stored == "device") then return stored end
    return "game"
  end

  local function deviceHour()
    local Rtc = engine("src.core.game3.rtc")
    if Rtc and type(Rtc.hostInfo) == "function" then
      -- honours POKEPORT_RTC and Rtc.setFixed, as WoobleDex's device clock does
      local ok, info = pcall(Rtc.hostInfo, nil)
      if ok and type(info) == "table" and tonumber(info.hour) then return tonumber(info.hour) end
    end
    local ok, t = pcall(osLib.date, "*t")
    return ok and type(t) == "table" and tonumber(t.hour) or 12
  end

  local function session()
    local ok, s = pcall(function() return mod.game and mod.game.session end)
    if ok and type(s) == "table" then return s end
    local Runtime = engine("src.core.game3.runtime")
    if Runtime and type(Runtime.getSession) == "function" then
      local okS, live = pcall(Runtime.getSession)
      if okS and type(live) == "table" then return live end
    end
    return nil
  end

  -- 0-23 on Gen 1 and Gen 3. The cart's clock is read without side effects
  -- (Rtc.calcLocalTime would also overwrite the engine's own Rtc.localTime).
  function C.hour()
    if generation == 3 and C.clockSource() ~= "device" then
      local Rtc = engine("src.core.game3.rtc")
      local s = session()
      if Rtc and s then
        local okE, on = pcall(Rtc.enabled, s)
        if okE and on then
          local ok, t = pcall(function()
            local offset = type(s.localTimeOffset) == "table" and s.localTimeOffset
              or Rtc.newTime(0, 0, 0, 0)
            return Rtc.calcTimeDifferenceRtc(Rtc.getInfo(s), offset)
          end)
          if ok and type(t) == "table" and tonumber(t.hours) then
            return math.floor(tonumber(t.hours)) % 24
          end
        end
      end
    end
    return math.floor(deviceHour()) % 24
  end

  function C.periodOfHour(hour)
    hour = math.floor(tonumber(hour) or 12) % 24
    if hour >= C.NIGHT_BEGIN or hour < C.NIGHT_END then return "night" end
    return "day"
  end

  -- Gold/Silver/Crystal's own words: NITE (and a DARK a world.tod hook may
  -- return) is night, MORN and DAY are day.
  local function gen2Period(word)
    if word == "NITE" or word == "DARK" then return "night" end
    if word == "MORN" or word == "DAY" then return "day" end
    return nil
  end

  local function gen2Now()
    local okW, world = pcall(function() return mod.game and mod.game.world end)
    world = okW and type(world) == "table" and world or nil
    local period = world and gen2Period(world.tod)
    if period then return period end
    local Palettes = engine("src.world.gen2.Palettes")
    if Palettes and type(Palettes.clockDaytime) == "function" then
      local hour
      if world and type(world.hour) == "function" then
        local ok, h = pcall(world.hour, world)
        if ok then hour = tonumber(h) end
      end
      if not hour then
        local Gen2Clock = engine("src.core.gen2.Clock")
        local okH, h = pcall(function() return Gen2Clock.hour(mod.game.save) end)
        if okH then hour = tonumber(h) end
      end
      local ok, word = pcall(Palettes.clockDaytime, hour)
      period = ok and gen2Period(word)
      if period then return period end
    end
    local hour = deviceHour()
    return (hour >= 18 or hour < 4) and "night" or "day"
  end

  -- "day" or "night" for an encounter's ctx (or nil: right now).
  function C.period(ctx)
    if pinned then return pinned end
    if generation == 2 then
      local word = type(ctx) == "table" and (ctx.daytime or ctx.tod) or nil
      return gen2Period(word) or gen2Now()
    end
    return C.periodOfHour(C.hour())
  end

  return C
end
