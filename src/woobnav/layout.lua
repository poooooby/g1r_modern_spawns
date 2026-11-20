-- WoobNav: pure geometry for its screen. No love access, so it runs headless.
--
-- The screen is a logical 240x216 space: Kanto Gear's bottom screen (its 160x144 phone shape,
-- 10:9, at 1.5x). Where that space sits in the OS window follows Kanto Gear's own COMBINED
-- SCREEN layouts. Layout.gear / fitRect adapted from NaviPlay's src/layout.lua (MIT, (c) 2026
-- poooooby), which adapted THEME:windowLayout and THEME:fitRect from Kanto Gear (MIT, (c) 2026
-- AverageConsumer, github.com/AverageConsumer/kanto-gear).

local Layout = {}

Layout.W, Layout.H = 240, 216

function Layout.fitRect(rect, width, height)
  local scale = math.min(rect.w / width, rect.h / height)
  local w, h = width * scale, height * scale
  return { x = math.floor(rect.x + (rect.w - w) / 2), y = math.floor(rect.y + (rect.h - h) / 2),
    w = w, h = h, scale = scale }
end

-- Split screen as Kanto Gear lays out its COMBINED SCREEN: the window cut into the game's part
-- and the WoobNav's (stacked: the WoobNav 36% of the height under the game; side: 34% of the
-- width right of it; `size` 20..80 overrides), a gap of 1% of the shorter side (at least 2),
-- `safe` % taken off the foot first, `swapped` trading the two parts. OVERLAY: the game has the
-- whole window and the WoobNav floats in `corner`. FULLSCREEN: each the whole window.
-- opts = { layout = "auto" | "stacked" | "side" | "overlay" | "fullscreen", corner, size, safe,
--   swapped, dpi, reserveBottom, gameW, gameH, x, y }
-- -> { orientation, game, picture, surface = { x, y, w, h, scale }, mode, overlay }
function Layout.gear(ww, wh, opts)
  opts = opts or {}
  if ww < 1 or wh < 1 then return nil end
  local gw, gh = opts.gameW or 240, opts.gameH or 160
  local dpi = (opts.dpi and opts.dpi > 0) and opts.dpi or 1
  local ox, oy = opts.x or 0, opts.y or 0
  local mode = opts.layout
  if mode == "large" then mode = "overlay" end
  if mode ~= "stacked" and mode ~= "side" and mode ~= "overlay" and mode ~= "fullscreen" then
    mode = ww >= wh and "side" or "stacked"
  end
  local height = wh - math.max(0, opts.reserveBottom or 0)
  local safe = mode == "fullscreen" and 0 or math.max(0, math.min(50, tonumber(opts.safe) or 0))
  height = math.max(1, height - math.floor(height * safe / 100))
  local width = ww
  local gap = math.max(2, math.floor(math.min(width, height) * 0.01))
  local requested = tonumber(opts.size)
  local function share(fallback) return math.max(20, math.min(80, requested or fallback)) / 100 end
  local game, gear
  if mode == "fullscreen" then
    game = { x = 0, y = 0, w = width, h = height }
    gear = { x = 0, y = 0, w = width, h = height }
  elseif mode == "stacked" then
    local gearH = math.floor((height - gap) * share(36))
    game = { x = 0, y = 0, w = width, h = height - gearH - gap }
    gear = { x = 0, y = game.h + gap, w = width, h = gearH }
  elseif mode == "side" then
    local gearW = math.floor((width - gap) * share(34))
    game = { x = 0, y = 0, w = width - gearW - gap, h = height }
    gear = { x = game.w + gap, y = 0, w = gearW, h = height }
  else
    local gearH = math.floor(height * share(42))
    local gearW = math.min(math.floor(width * (requested and share(42) or 0.38)), math.floor(gearH * 160 / 144))
    local corner = opts.corner or "bottom_right"
    local left = corner == "top_left" or corner == "bottom_left"
    local top = corner == "top_left" or corner == "top_right"
    game = { x = 0, y = 0, w = width, h = height }
    gear = { x = left and gap or width - gearW - gap, y = top and gap or height - gearH - gap, w = gearW, h = gearH }
  end
  if opts.swapped and mode ~= "overlay" and mode ~= "fullscreen" then game, gear = gear, game end
  local function snap(v) return math.floor(v * dpi + 1e-6) / dpi end
  game = { x = snap(ox + game.x), y = snap(oy + game.y), w = snap(game.w), h = snap(game.h) }
  local fit = Layout.fitRect(gear, Layout.W, Layout.H)
  local surface = { x = snap(ox + fit.x), y = snap(oy + fit.y), w = fit.w, h = fit.h, scale = fit.scale }
  local kk = math.max(1, math.floor(math.min(game.w * dpi / gw, game.h * dpi / gh) + 1e-9))
  local fw, fh = gw * kk / dpi, gh * kk / dpi
  local picture = { x = snap(game.x + (game.w - fw) / 2), y = snap(game.y + (game.h - fh) / 2), w = fw, h = fh,
    scale = kk / dpi }
  game.scale = picture.scale
  return { orientation = (mode == "stacked" or (mode == "overlay" and wh >= ww)) and "portrait" or "landscape",
    game = game, picture = picture, surface = surface, mode = mode, overlay = mode == "overlay" }
end

-- Window (or pushed-frame) coordinates to logical screen coordinates -> lx, ly, inside.
function Layout.toLogical(rect, x, y)
  if not rect or not rect.scale or rect.scale <= 0 then return nil, nil, false end
  local lx = (x - (rect.x or 0)) / rect.scale
  local ly = (y - (rect.y or 0)) / rect.scale
  return lx, ly, lx >= 0 and ly >= 0 and lx < Layout.W and ly < Layout.H
end

-- "action,x,y" from the second display's touch queue (a bare "x,y" is a tap).
function Layout.parseTouch(event)
  if type(event) ~= "string" then return nil end
  local action, x, y = event:match("^%s*(%a+)%s*,%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)")
  if action then return action:lower(), tonumber(x), tonumber(y) end
  x, y = event:match("^%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)")
  if x then return "tap", tonumber(x), tonumber(y) end
  return nil
end

return Layout
