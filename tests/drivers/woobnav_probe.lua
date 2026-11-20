-- Driver: the WoobNav in the running game. Opened as Kanto Gear's Store press does (its own
-- modules.open through the registry), the area list and a summary shot in the Gear's COMBINED
-- and FULLSCREEN display modes (set in memory only, put back after; options.lua is never
-- written), a tap through the view, then back to the Gear.
--   SHOT_DIR=<dir> POKEPORT_GAME=crystal POKEPORT_VERSION=crystal WOOBNAV_MAP=ROUTE_29 \
--   POKEPORT_DRIVER=mods/modern_spawns/tests/drivers/woobnav_probe.lua love .

local function body(game, log, dir)
  local U = require("tests.drivers.util")
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  waitFor(function() return (game.phase == "boot" and game.boot) or game.phase == "play" end, 900)
  log("phase:", tostring(game.phase))
  if game.phase == "boot" and game._handleBootAction then
    game:_handleBootAction({ action = "new_game", name = "DEX", gender = 0 })
  end
  U.wait(120)
  local loader = game.mods
  local ex = loader and loader.exports
  local N = ex and ex.modern_spawns and ex.modern_spawns._woobnav
  if not N then log("FAIL no WoobNav"); return end
  local rec = loader.mods and loader.mods.kanto_gear
  log("kanto gear:", rec and rec.state, tostring(rec and rec.skipReason), tostring(rec and rec.error),
    "enabled", tostring(rec and rec.enabled), "woobnav registered:", tostring(N.registered))
  local SaveData = require("src.core.SaveData")
  local o = SaveData.loadOptions(loader.fs)
  log("cart", tostring(loader.cartReport and loader.cartReport.id), "scope", tostring(loader._enableScope and loader:_enableScope()),
    "opt mods.kanto_gear", tostring(o.mods and o.mods.kanto_gear), "identity", love.filesystem.getIdentity(),
    "savedir", love.filesystem.getSaveDirectory())
  local states = {}
  for id, m in pairs(loader.mods or {}) do states[#states + 1] = id .. "=" .. tostring(m.state) end
  table.sort(states)
  log("mods:", table.concat(states, " "))
  local M
  if not N.registered then
    -- the Gear is switched off on this machine: a stand-in for its Store hook (the app's own
    -- display path is what runs here; the Gear's registration has its own test)
    log("kanto gear not running: registering with a stand-in hook")
    N.register({ api = 1, register = function() return true end })
  else
    local hook = ex.kanto_gear.modules
    for i = 1, 40 do
      local name, v = debug.getupvalue(hook.register, i)
      if not name then break end
      if name == "M" then M = v end
    end
  end
  if not N.Display then log("FAIL no display"); return end
  local opts = { kanto_gear = {} }
  N.Display.state.gearOptions = opts.kanto_gear
  local display0 = nil
  local mapId = os.getenv("WOOBNAV_MAP") or "ROUTE_29"
  for _, mode in ipairs({ "combined", "fullscreen" }) do
    opts.kanto_gear.display_mode = mode
    U.wait(10)
    local opened
    if M and M.open then
      local ok, v = pcall(M.open, "woobnav")
      opened = ok and v
      log(mode, "gear open ->", tostring(ok), tostring(v))
    end
    if not opened then N.open() end
    loader.events:emit("map.entered", { mapId = mapId })
    U.wait(20)
    log(mode, "shown", tostring(N.isOpen()), "display", tostring(N.Display.state.mode), "rows", #N.state.rows,
      "title", tostring(N.state.model and N.state.model.title))
    U.shot(game, dir .. "/woobnav_" .. mode .. "_area.png")
    N.act("card:1")
    U.wait(10)
    log(mode, "summary of", tostring(N.state.selected), "here", #(N.state.here or {}))
    U.shot(game, dir .. "/woobnav_" .. mode .. "_summary.png")
    N.act("tab:stats")
    U.wait(5)
    U.shot(game, dir .. "/woobnav_" .. mode .. "_stats.png")
    N.act("back")
    N.act("back")
    U.wait(10)
    log(mode, "after back twice: open", tostring(N.isOpen()), "display", tostring(N.Display.state.mode),
      "gear shown", tostring(M and M.anyShown and M.anyShown()))
    U.shot(game, dir .. "/woobnav_" .. mode .. "_closed.png")
  end
  N.Display.state.gearOptions = nil
  log("DONE")
end

return function(game)
  local dir = os.getenv("SHOT_DIR") or "/tmp/woobnav"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local logFile = io.open(dir .. "/driver.log", "w")
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    print("[driver]", line)
    if logFile then logFile:write(line, "\n"); logFile:flush() end
  end
  local ok, err = xpcall(function() body(game, log, dir) end, debug.traceback)
  if not ok then log("DRIVER ERROR:", tostring(err)) end
  if logFile then logFile:close() end
  love.event.quit()
end
