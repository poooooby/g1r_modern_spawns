-- WoobNav: where its screen shows and where touches go, while it is open.
--
-- Kanto Gear stands down while the WoobNav is open (its module API: shown() true), so the
-- WoobNav shows itself the way the Gear would have, following the Gear's own DISPLAY MODE:
--   separate   the second display (SECOND SCREEN), or with the Gear's output on the main
--              screen ("handheld") the WoobNav on the window and the game on the second display
--   combined   the window split as the Gear's COMBINED SCREEN lays it out (its layout, size,
--              corner, safe area and primary view)
--   fullscreen the WoobNav alone on the window
--   phone      as combined (the Gear's phone stream has no hook for another mod's frames)
-- No buttons are taken: the D-pad and A/B stay with the game, so the player walks with the
-- WoobNav open. The view is touched and clicked only.
--
-- Condensed from NaviPlay's main.lua display glue (MIT, (c) 2026 poooooby).
--
--   Display = makeDisplay({ mod, Layout, Surface, Gate, Host, app })
--   app = { isOpen() -> bool, draw(G, w, h), pointer(phase, x, y) ("down"|"move"|"up"|"cancel"),
--           animating() -> bool }
--   Display.install()        the hooks (once per load)
--   Display.dirty = true     redraw on the next frame

return function(deps)
  local mod, Layout, Surface, Gate, Host, app = deps.mod, deps.Layout, deps.Surface, deps.Gate, deps.Host, deps.app
  local GB = tonumber(mod.generation) ~= 3

  local D = { dirty = true }
  local state = { mode = "off", rect = nil, pushAt = 0, pushK = 1 }
  D.state = state

  local function now()
    local ok, t = pcall(function() return love.timer.getTime() end)
    return ok and t or os.clock()
  end

  -- ------- the second display bridge (lazily required)

  local secondScreen, gate
  local function second()
    if secondScreen == nil then
      local ok, SS = pcall(require, "src.render.SecondScreen")
      secondScreen = ok and type(SS) == "table" and SS or false
    end
    return secondScreen or nil
  end
  local function secondGate()
    if gate == nil then
      local SS = second()
      gate = SS and Gate.new(SS) or false
    end
    return gate or nil
  end

  -- the bridge's checks cross into Android (JNI); share one answer for 50 ms
  local checks = {}
  local function bridgeCheck(SS, name)
    local fn = SS and SS[name]
    if not fn then return false end
    local t = now()
    local c = checks[name]
    if not c or c.fn ~= fn or t < c.at or t >= c.at + 0.05 then
      local ok, v = pcall(fn)
      c = { fn = fn, at = t, value = ok and v == true }
      checks[name] = c
    end
    return c.value
  end

  -- one of Kanto Gear's options, as the engine's options:get reads it (stored, else its default)
  local function gearOption(key)
    if state.gearOptions then return state.gearOptions[key] end -- a test's stand-in
    local loader = state.game and state.game.mods
    local rec = loader and loader.mods and loader.mods.kanto_gear
    if not rec or rec.state == "disabled" or rec.state == "failed" then return nil end
    local stored = loader.modOptions and loader.modOptions.kanto_gear
    local v = stored and stored[key]
    if v == nil then
      for _, row in ipairs(loader.optionSchemas and loader.optionSchemas.kanto_gear or {}) do
        if row.key == key then v = row.default end
      end
    end
    return v
  end
  D.gearOption = gearOption

  local GEAR_MODE = { fullscreen = "fullscreen", combined = "combined", separate = "separate", phone = "combined" }

  -- Galar Rising's battle pad holds the second display: the WoobNav keeps off it
  local function secondTaken()
    local gr = mod.find and mod:find("max_raids")
    local ex = gr and gr.exports
    if not (type(ex) == "table" and type(ex.secondScreenShown) == "function") then return false end
    local ok, v = pcall(ex.secondScreenShown)
    return ok and v == true
  end

  local function isOpen()
    local ok, v = pcall(app.isOpen)
    return ok and v == true
  end

  -- "off" | "split" | "second_screen" | "handheld"; state.style the split's
  function D.wantedMode()
    if not isOpen() then return "off" end
    local choice = GEAR_MODE[gearOption("display_mode") or ""] or "detect"
    local SS = second()
    local usable = false
    if SS and SS.usable then
      local ok, u = pcall(SS.usable)
      usable = ok and u == true
    end
    if secondTaken() then usable = false end
    if choice == "detect" then
      choice = (usable and bridgeCheck(SS, "detected")) and "separate" or "combined"
    end
    if choice == "separate" then
      if usable then
        state.style = "separate"
        return gearOption("display_target") == "handheld" and "handheld" or "second_screen"
      end
      choice = "combined"
    end
    state.style = choice
    return "split"
  end

  local pointer = nil -- { id, x0, y0 } of the press being followed

  local function cancelPointer()
    if pointer then
      pointer = nil
      pcall(app.pointer, "cancel", 0, 0)
    end
  end

  local HOLDS = { second_screen = true, handheld = true }
  local function setMode(mode)
    if mode == state.mode then return end
    mod.log:info("WoobNav: display %s -> %s", state.mode, mode)
    cancelPointer()
    if HOLDS[state.mode] and not HOLDS[mode] then
      local g = secondGate()
      if g then g:release() end
    end
    state.ssEnabled, state.ssShown = false, false
    if HOLDS[mode] and not HOLDS[state.mode] then
      local g = secondGate()
      if g then g:claim() end
    end
    if state.mode == "handheld" then state.gameRead, state.gameCanvas = nil, nil end
    if mode ~= "split" then Host.setCutout(nil) end
    if mode == "off" then Host.hidePad(false, state.game) end
    state.mode = mode
    state.rect, state.gbGame = nil, nil
    state.pushAt = 0
    D.dirty = true
  end
  D.setMode = setMode

  -- one frame to the second display, its pixels freed at once (outside Lua's heap, a stream of
  -- them left to the collector piles up native memory)
  local function pushFrame(SS, data, w, h, bg, pref)
    local ok, shown = pcall(SS.push, data, w, h, bg, pref)
    if data and data.release then pcall(data.release, data) end
    return ok and shown ~= false
  end

  -- ------- pointer feeds (logical coordinates to the view)

  local function feedWindow(phase, id, x, y, source)
    if phase == "pressed" then
      local lx, ly, inside = Layout.toLogical(state.rect, x, y)
      if not inside then return false end
      if source == "mouse" and pointer and pointer.id == id then return true end
      pointer = { id = id }
      D.dirty = true
      pcall(app.pointer, "down", lx, ly)
      return true
    end
    if not (pointer and pointer.id == id) then return false end
    local lx, ly = Layout.toLogical(state.rect or { x = 0, y = 0, scale = 1 }, x, y)
    D.dirty = true
    if phase == "moved" then
      pcall(app.pointer, "move", lx, ly)
    elseif phase == "released" then
      pointer = nil
      pcall(app.pointer, "up", lx, ly)
    else
      cancelPointer()
    end
    return true
  end
  D.feedWindow = feedWindow

  local function feedSecond(action, x, y)
    local k = state.pushK or 1
    local lx, ly = x / k, y / k
    D.dirty = true
    if action == "down" then
      pointer = { id = "screen2" }
      pcall(app.pointer, "down", lx, ly)
    elseif action == "tap" then
      pcall(app.pointer, "down", lx, ly)
      pcall(app.pointer, "up", lx, ly)
    elseif pointer and pointer.id == "screen2" then
      if action == "move" then
        pcall(app.pointer, "move", lx, ly)
      elseif action == "up" then
        pointer = nil
        pcall(app.pointer, "up", lx, ly)
      else
        cancelPointer()
      end
    end
  end
  D.feedSecond = feedSecond

  local gen3Wrapped = false
  local function ensureGen3Touch()
    if gen3Wrapped or GB then return end
    gen3Wrapped = true
    Host.wrapTouch(function(phase, id, x, y)
      if state.mode ~= "split" then return false end
      return feedWindow(phase, id, x, y, id == "mouse" and "mouse" or "touch")
    end)
    Host.wrapMouse(function(phase, x, y)
      if state.mode ~= "split" then return false end
      return feedWindow(phase, "mouse", x, y, "mouse")
    end)
  end

  -- a desktop mouse held on the WoobNav is followed every frame (event routing for a held mouse
  -- differs per generation); Gen 3 on a desktop delivers no mouse events at all, so the poll
  -- starts the press too. Phones have no mouse, and a press with a finger down is the finger.
  local MOBILE = { iOS = true, Android = true }
  local function osName()
    local ok, name = pcall(function() return love.system.getOS() end)
    return ok and name or "?"
  end
  local function fingerDown()
    if not (love.touch and love.touch.getTouches) then return false end
    local ok, touches = pcall(love.touch.getTouches)
    return ok and type(touches) == "table" and #touches > 0
  end
  local function pollMouse()
    if not (love and love.mouse and love.mouse.getPosition) then return end
    if state.mode ~= "split" or MOBILE[osName()] then
      state.mouseWasDown = nil
      return
    end
    local mx, my = love.mouse.getPosition()
    local down = love.mouse.isDown ~= nil and love.mouse.isDown(1) or false
    if not (pointer and pointer.id == "mouse") then
      if down and not state.mouseWasDown and not fingerDown() then
        feedWindow("pressed", "mouse", mx, my, "mouse")
      end
      state.mouseWasDown = down
      return
    end
    state.mouseWasDown = down
    if not down then feedWindow("released", "mouse", mx, my, "mouse") end
  end

  -- ------- layout

  local function windowDpi()
    if not (love and love.graphics and love.graphics.getDPIScale) then return 1 end
    local ok, d = pcall(love.graphics.getDPIScale)
    d = ok and tonumber(d) or 1
    return d > 0 and d or 1
  end

  local function gearLayout(ww, wh, gameW, gameH)
    local style = state.style or "combined"
    local layout = style == "fullscreen" and "fullscreen" or gearOption("combined_layout")
    local size = gearOption("secondary_size")
    local primary = gearOption("combined_primary")
    return Layout.gear(ww, wh, { dpi = windowDpi(), layout = layout, corner = gearOption("overlay_corner"),
      size = size ~= "auto" and size or nil, safe = tonumber(gearOption("bottom_safe_area")) or 0,
      swapped = primary ~= nil and primary ~= "game", gameW = gameW, gameH = gameH }), style
  end

  -- the WoobNav's rect in a layout; FULLSCREEN covers the window black under it
  local function surfaceOf(lay, style)
    state.coverWindow = style == "fullscreen"
    if style == "fullscreen" then
      return Layout.fitRect({ x = 0, y = 0, w = lay.game.w, h = lay.game.h }, Layout.W, Layout.H)
    end
    return lay.surface
  end

  local function gen3Rect(vp)
    local ww, wh = vp.width or 0, vp.height or 0
    if ww < 1 or wh < 1 then return nil end
    local lay, style = gearLayout(ww, wh, 240, 160)
    if not lay then return nil end
    if style ~= "fullscreen" and Host.canCut then Host.setCutout(lay.game) end
    return surfaceOf(lay, style)
  end

  local function drawAll(G, w, h) app.draw(G, w, h) end

  local function cover(w, h)
    local G = love.graphics
    G.push("all")
    G.origin()
    G.setScissor()
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, w or 0, h or 0)
    G.pop()
  end

  -- ------- the per-frame tick

  local function tick(game, viewport)
    state.game = game or state.game
    setMode(D.wantedMode())
    local mode = state.mode
    if mode == "off" then
      state.rect = nil
      return
    end
    pollMouse()
    Host.hidePad(mode == "split", state.game)
    if app.prepare then
      local okP, errP = pcall(app.prepare)
      if not okP and not state.prepareWarned then
        state.prepareWarned = true
        mod.log:warn("WoobNav: preparing the page failed (%s)", tostring(errP))
      end
    end
    local vw, vh = viewport and viewport.width, viewport and viewport.height
    if vw ~= state.lastW or vh ~= state.lastH then
      state.lastW, state.lastH = vw, vh
      D.dirty = true
    end
    local anim = false
    if app.animating then
      local ok, v = pcall(app.animating)
      anim = ok and v == true
    end
    local needsDraw = D.dirty or anim or pointer ~= nil

    if mode == "split" then
      if not GB then
        ensureGen3Touch()
        state.rect = gen3Rect(viewport or {})
      end
      local rect = state.rect
      if rect then
        if state.coverWindow then cover(vw, vh) end
        local k = Surface:densityFor(rect)
        if needsDraw or k ~= Surface.k then
          Surface:render(drawAll, k)
          D.dirty = false
        end
        Surface:blit(rect)
      end
      return
    end

    local SS = second()
    if not SS then return end
    local t = now()
    if not state.ssEnabled or (not state.ssShown and t >= (state.ssRetryAt or 0)) then
      pcall(SS.setEnabled, true)
      state.ssEnabled, state.ssRetryAt = true, t + 1
    end

    if mode == "handheld" then
      -- the game went to the second display in render.output; the WoobNav fills the window
      local ww, wh = vw or 0, vh or 0
      if ww < 1 or wh < 1 then state.rect = nil; return end
      local rect = Layout.fitRect({ x = 0, y = 0, w = ww, h = wh }, Layout.W, Layout.H)
      state.rect = rect
      cover(ww, wh)
      local k = Surface:densityFor(rect)
      if needsDraw or k ~= Surface.k then
        Surface:render(drawAll, k)
        D.dirty = false
      end
      Surface:blit(rect)
      return
    end

    -- second_screen
    state.rect = nil
    for _ = 1, 128 do
      local ok, event = pcall(SS.pollTouch)
      if not ok or not event then break end
      local action, x, y = Layout.parseTouch(event)
      if action and x and y then feedSecond(action, x, y) end
    end
    if bridgeCheck(SS, "available") then
      local ready, rw, rh = Surface:pollPush()
      if ready then state.ssShown = pushFrame(SS, ready, rw, rh, 0x000000, "secondary") end
      local due = t - state.pushAt
      if not Surface.pending and (((needsDraw or D.dirty) and due >= 1 / 30) or due >= 1.0) then
        state.pushK = Surface.MAX_K
        state.pushAt = t
        local data, w, h = Surface:requestPush(state.pushK, drawAll, t)
        D.dirty = false
        if data then state.ssShown = pushFrame(SS, data, w, h, 0x000000, "secondary") end
      else
        Surface:dropStale(t)
      end
    end
  end
  D.tick = tick

  -- handheld: the finished game frame to the second display, at most 960x540, read back
  -- without a stall, up to 60 times a second (Kanto Gear's handheld output)
  local function pushGame(ctx)
    local SS = second()
    local G = love and love.graphics
    if not (SS and G and ctx.canvas) then return end
    local t = now()
    local read = state.gameRead
    if read and read.pollImageData then
      local okP, image = pcall(read.pollImageData, read)
      if okP and image then
        state.ssShown = pushFrame(SS, image, image:getWidth(), image:getHeight(), 0x000000, "secondary:cover")
        state.gameRead = nil
      end
    end
    if state.gameRead or t < (state.gameNext or 0) then return end
    local ww = math.max(1, ctx.width or G.getWidth())
    local wh = math.max(1, ctx.height or G.getHeight())
    local k = math.min(960 / ww, 540 / wh)
    local cw, ch = math.max(1, math.floor(ww * k + 0.5)), math.max(1, math.floor(wh * k + 0.5))
    local c = state.gameCanvas
    if not c or c:getWidth() ~= cw or c:getHeight() ~= ch then
      c = G.newCanvas(cw, ch, { dpiscale = 1 })
      c:setFilter("linear", "linear")
      state.gameCanvas = c
    end
    G.push("all")
    G.setCanvas(c)
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    G.clear(0, 0, 0, 1)
    G.setColor(1, 1, 1, 1)
    G.draw(ctx.canvas, 0, 0, 0, cw / ww, ch / wh)
    G.pop()
    state.gameNext = t + 1 / 60
    if c.requestImageData and c.pollImageData and pcall(c.requestImageData, c) then
      state.gameRead = c
    elseif c.newImageData then
      local okI, image = pcall(c.newImageData, c)
      if okI and image then state.ssShown = pushFrame(SS, image, cw, ch, 0x000000, "secondary:cover") end
    end
  end

  -- ------- hooks

  local installed = false
  function D.install()
    if installed then return end
    installed = true
    local hooks = mod.hooks

    local okGV, GameViewport = pcall(require, "src.render.GameViewport")
    if not (okGV and type(GameViewport) == "table") then GameViewport = nil end
    local function captured()
      if not (GB and GameViewport and GameViewport.active) then return false end
      local ok, on = pcall(GameViewport.active)
      return ok and on == true
    end

    -- Gen 1 / 2 split: the game renders into its part of the window as if it were the window
    -- (capture), and render.window puts the WoobNav beside or over it
    hooks:wrap("render.viewport", function(next, ctx)
      local base = next(ctx)
      if not GB then return base end
      setMode(D.wantedMode())
      if state.mode ~= "split" then return base end
      local b = type(base) == "table" and base or { x = 0, y = 0, width = ctx.width, height = ctx.height }
      local lay, style = gearLayout(b.width, b.height, 160, 144)
      if not lay then state.rect = nil; return base end
      local s = surfaceOf(lay, style)
      state.rect = s and { x = s.x + (b.x or 0), y = s.y + (b.y or 0), w = s.w, h = s.h, scale = s.scale } or nil
      if style == "fullscreen" then return base end
      local g = lay.game
      state.gbGame = { x = g.x + (b.x or 0), y = g.y + (b.y or 0), w = g.w, h = g.h }
      return { x = state.gbGame.x, y = state.gbGame.y, width = g.w, height = g.h, capture = true }
    end)

    -- outside every other render.compose mod: the Gear inside gets the gate's proxy, which
    -- reports no display while the WoobNav shows there
    hooks:wrap("render.compose", function(next, renderer, ctx)
      if type(ctx) == "table" and ctx.secondScreen then
        setMode(D.wantedMode())
        local g = secondGate()
        if g then ctx.secondScreen = g.proxy end
      end
      return next()
    end, 900)

    hooks:wrap("render.output_enabled", function(next)
      if state.mode == "handheld" then return true end
      return next()
    end, -10000)

    hooks:wrap("render.output", function(next, ctx)
      if state.mode == "handheld" and type(ctx) == "table" and ctx.canvas then
        local ok, err = pcall(pushGame, ctx)
        if not ok and not state.pushGameWarned then
          state.pushGameWarned = true
          mod.log:warn("WoobNav: sending the game to the second display failed: %s", tostring(err))
        end
        local G = love.graphics
        G.push("all")
        G.setCanvas()
        G.origin()
        G.setScissor()
        G.clear(0, 0, 0, 1)
        G.pop()
        return true
      end
      return next(ctx)
    end, -10000)

    -- Gen 1 / 2 while captured: the WoobNav's frame waits for here, where the game has been put
    -- on the window and no canvas is set
    local gbHud = { game = nil, viewport = nil }
    hooks:wrap("render.window", function(next, game, ctx)
      local result = next(game, ctx)
      if not GB then return result end
      local vp = gbHud.viewport
      local wv = {}
      if type(vp) == "table" then for k, v in pairs(vp) do wv[k] = v end end
      wv.width = type(ctx) == "table" and ctx.windowWidth or wv.width
      wv.height = type(ctx) == "table" and ctx.windowHeight or wv.height
      gbHud.viewport = nil
      local ok, err = pcall(tick, game or gbHud.game, wv)
      if not ok and not state.tickWarned then
        state.tickWarned = true
        mod.log:warn("WoobNav: frame failed (%s)", tostring(err))
      end
      return result
    end)

    hooks:wrap("render.hud", function(next, game, viewport)
      if captured() then
        gbHud.game, gbHud.viewport = game, viewport
        state.game = game
        return next(game, viewport)
      end
      local ok, err = pcall(tick, game, viewport)
      if not ok and not state.tickWarned then
        state.tickWarned = true
        mod.log:warn("WoobNav: frame failed (%s)", tostring(err))
      end
      return next(game, viewport)
    end)

    hooks:wrap("input.pointer", function(next, game, ev)
      state.game = game or state.game
      if state.mode == "split" and type(ev) == "table" and (GB or ev.source == "mouse")
          and feedWindow(ev.phase, ev.id, ev.x, ev.y, ev.source) then
        return true
      end
      return next(game, ev)
    end)
  end

  return D
end
