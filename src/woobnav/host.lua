-- WoobNav: the engine seams its split screen needs (engine_internals), each wrapped once per
-- engine module and re-pointed on every load (a mod reload keeps the engine's modules):
--
--   cutout   Gen 3 fits its 240x160 picture into the rectangle src.render.Playfield.cutout
--            reports; while the WoobNav splits the window it reports the game's part.
--   pad      the engine's virtual pad (src.core.TouchControls) is hidden while the WoobNav
--            shows (Kanto Gear owns the controls), and on Gen 3 a touch that begins on the
--            WoobNav is routed to it for its whole life instead of the pad.
--   mouse    Gen 3 on a desktop: a left click on the WoobNav (Game3.mousepressed).
--
-- Adapted from NaviPlay's src/cutout.lua and src/pad_hide.lua (MIT, (c) 2026 poooooby), with
-- keys of its own (__woobnav*) so both mods' wraps chain instead of replacing each other.

return function(mod)
  local Host = {}

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  -- ------- cutout

  local Playfield = engine("src.render.Playfield")
  local cut = { rect = nil }
  Host.cut = cut

  local function wrapCutout()
    if not Playfield or type(Playfield.cutout) ~= "function" then return false end
    local w = rawget(Playfield, "__woobnavCutout")
    if not w then
      w = { original = Playfield.cutout }
      rawset(Playfield, "__woobnavCutout", w)
      Playfield.cutout = function(sw, sh, ...)
        local o = w.owner
        local r = o and o.rect
        if r and type(sw) == "number" and type(sh) == "number" then
          -- the rect is in window units; the renderer asks in physical pixels (sw, sh = the
          -- framebuffer), Display.fit in units: answer in the caller's own measure
          local x, y, rw, rh = r.x, r.y, r.w, r.h
          local G = love and love.graphics
          if G and G.getDimensions then
            local okD, uw, uh = pcall(G.getDimensions)
            if okD and uw and uh and uw > 0 and uh > 0 then
              local fx, fy = sw / uw, sh / uh
              x, y, rw, rh = x * fx, y * fy, rw * fx, rh * fy
            end
          end
          if x + rw > sw then rw = sw - x end
          if y + rh > sh then rh = sh - y end
          if rw >= 1 and rh >= 1 then return x, y, rw, rh, false, false end
        end
        return w.original(sw, sh, ...)
      end
    end
    w.owner = cut
    return true
  end
  Host.canCut = Playfield ~= nil

  -- rect { x, y, w, h } in window space, or nil to hand placement back
  function Host.setCutout(rect)
    if rect and not wrapCutout() then return false end
    cut.rect = rect and { x = rect.x, y = rect.y, w = rect.w, h = rect.h } or nil
    return true
  end
  function Host.cutActive() return cut.rect ~= nil end

  -- ------- the virtual pad

  local TC = engine("src.core.TouchControls")
  local padHidden, padPrev = false, nil
  function Host.hidePad(active, game)
    if not TC then return end
    if active then
      if not padHidden then padPrev, padHidden = TC.enabled, true end
      if TC.enabled ~= false then
        TC.enabled = false
        if TC.reset then pcall(TC.reset, TC) end
      end
    elseif padHidden then
      padHidden = false
      local opts = game and (type(game.options) == "table" and game.options
        or (type(game.save) == "table" and type(game.save.options) == "table" and game.save.options)) or nil
      local restored = false
      if opts and TC.applyOptions then restored = pcall(TC.applyOptions, TC, opts) end
      if not restored then TC.enabled = padPrev end
    end
  end

  -- handler(phase, id, x, y, pressure) -> true when the WoobNav took it
  function Host.wrapTouch(handler)
    if not TC then return false end
    local w = rawget(TC, "__woobnavTouch")
    if not w then
      w = { press = TC.touchpressed, move = TC.touchmoved, release = TC.touchreleased, reset = TC.reset,
            owned = {} }
      if not (w.press and w.move and w.release) then return false end
      rawset(TC, "__woobnavTouch", w)
      TC.touchpressed = function(self_, id, x, y, ...)
        if id == "mouse" then w.sawMouse = true end
        local h = w.handler
        if h and h("pressed", id, x, y) then
          w.owned[id] = true
          return true
        end
        return w.press(self_, id, x, y, ...)
      end
      TC.touchmoved = function(self_, id, x, y, ...)
        if w.owned[id] then
          local h = w.handler
          if h then h("moved", id, x, y) end
          return true
        end
        return w.move(self_, id, x, y, ...)
      end
      TC.touchreleased = function(self_, id, x, y, ...)
        if w.owned[id] then
          w.owned[id] = nil
          local h = w.handler
          if h then h("released", id, x, y) end
          return true
        end
        return w.release(self_, id, x, y, ...)
      end
      if w.reset then
        TC.reset = function(self_, ...)
          if next(w.owned) then
            local h = w.handler
            for id in pairs(w.owned) do
              if h then h("cancelled", id, 0, 0) end
            end
            w.owned = {}
          end
          return w.reset(self_, ...)
        end
      end
    end
    w.handler = handler
    return true
  end

  -- Gen 3 on a desktop: Game3's mouse handlers, the original first (the game keeps its click)
  function Host.wrapMouse(handler)
    local Game3 = engine("src.core.Game3")
    if not (Game3 and Game3.mousepressed) then return false end
    local w = rawget(Game3, "__woobnavMouse")
    if not w then
      w = { press = Game3.mousepressed, move = Game3.mousemoved, release = Game3.mousereleased, down = false }
      rawset(Game3, "__woobnavMouse", w)
      local function touchHasMouse()
        local t = TC and rawget(TC, "__woobnavTouch")
        return t and t.sawMouse
      end
      Game3.mousepressed = function(self_, x, y, button, istouch, ...)
        local r = w.press(self_, x, y, button, istouch, ...)
        if not istouch and button == 1 and not touchHasMouse() and w.handler then
          w.down = w.handler("pressed", x, y) == true
        end
        return r
      end
      Game3.mousemoved = function(self_, x, y, dx, dy, istouch, ...)
        local r = w.move and w.move(self_, x, y, dx, dy, istouch, ...)
        if w.down and not istouch and w.handler then w.handler("moved", x, y) end
        return r
      end
      Game3.mousereleased = function(self_, x, y, button, istouch, ...)
        local r = w.release and w.release(self_, x, y, button, istouch, ...)
        if w.down and not istouch and button == 1 and w.handler then
          w.down = false
          w.handler("released", x, y)
        end
        return r
      end
    end
    w.handler = handler
    return true
  end

  return Host
end
