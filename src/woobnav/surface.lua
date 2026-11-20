-- WoobNav: its screen as a drawing target. The view draws into the 240x216 logical space,
-- blitted into a window rect (split) or read back and pushed to a second display.
--
-- The canvas is W*k by H*k real pixels, k the output's pixels per logical unit, and the view
-- draws under a scale(k) transform, so the pixel fonts and sprites land on whole output pixels
-- wherever k is whole. Everything love-related is guarded so a headless load never touches the
-- GPU. From NaviPlay's src/surface.lua (MIT, (c) 2026 poooooby).

return function(mod, Layout)
  local G = love and love.graphics
  local MAX_K = 4

  local S = { W = Layout.W, H = Layout.H, canvas = nil, k = 1, dirty = true, MAX_K = MAX_K }

  function S:ensure(k)
    if not G then return nil end
    k = k or self.k or 1
    if not self.canvas or self.k ~= k then
      local pw, ph = math.floor(self.W * k + 0.5), math.floor(self.H * k + 0.5)
      local ok, canvas = pcall(G.newCanvas, pw, ph, { dpiscale = 1 })
      if not ok then
        if k > 1 then return self:ensure(1) end
        return nil
      end
      canvas:setFilter("nearest", "nearest")
      if self.canvas and self.canvas.release then pcall(self.canvas.release, self.canvas) end
      self.canvas, self.k = canvas, k
      self.dirty = true
    end
    return self.canvas
  end

  -- drawFn(G, w, h) into the canvas at density k. Errors are logged once and the frame kept.
  function S:render(drawFn, k)
    local canvas = self:ensure(k or self.k)
    if not canvas then return false end
    G.push("all")
    G.setCanvas(canvas)
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    G.clear(0, 0, 0, 1)
    if self.k ~= 1 then G.scale(self.k, self.k) end
    G.setColor(1, 1, 1, 1)
    local ok, err = pcall(drawFn, G, self.W, self.H)
    G.setCanvas()
    G.pop()
    if not ok and not self.warned then
      self.warned = true
      mod.log:warn("WoobNav: drawing failed (%s)", tostring(err))
    end
    self.dirty = false
    return ok
  end

  -- the density a window rect wants: its scale times the screen's DPI, capped at MAX_K
  function S:densityFor(rect)
    if not (G and rect) then return 1 end
    local dpi = G.getDPIScale and G.getDPIScale() or 1
    local k = (rect.scale or 1) * dpi
    if k ~= k then return 1 end
    return math.max(0.5, math.min(MAX_K, k))
  end

  -- the canvas into a window rect { x, y, w, h, scale }, a thin dark bezel round it
  function S:blit(rect)
    if not (G and self.canvas and rect) then return end
    local s = (rect.scale or 1) / self.k
    G.push("all")
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", rect.x - 2, rect.y - 2, rect.w + 4, rect.h + 4)
    G.setColor(1, 1, 1, 1)
    local dpi = G.getDPIScale and G.getDPIScale() or 1
    local exact = math.abs(s * dpi - 1) < 1e-3 or self.k == 1
    if not exact then self.canvas:setFilter("linear", "linear") end
    G.draw(self.canvas, rect.x, rect.y, 0, s, s)
    if not exact then self.canvas:setFilter("nearest", "nearest") end
    G.pop()
  end

  -- The second display without stalling the GPU: requestImageData / pollImageData where the
  -- engine's LOVE has them (as Kanto Gear does), else the blocking read. No new frame while one
  -- is being read; one stuck for STALE_S starts over on a fresh canvas.
  S.STALE_S = 1.0
  function S:dropStale(now)
    if self.pending and now and now - self.pending.at > S.STALE_S then
      self.pending = nil
      if self.canvas and self.canvas.release then pcall(self.canvas.release, self.canvas) end
      self.canvas = nil
    end
  end

  function S:requestPush(k, drawFn, now)
    self:dropStale(now)
    if self.pending then return nil end
    k = math.max(1, math.floor(k or 2))
    if drawFn then self:render(drawFn, k) end
    local src = self.canvas
    if not src then return nil end
    local pw, ph = src:getPixelWidth(), src:getPixelHeight()
    if src.requestImageData and src.pollImageData then
      local ok, started = pcall(src.requestImageData, src)
      if ok and started ~= false then
        self.pending = { src = src, w = pw, h = ph, at = now or 0 }
        return nil
      end
    end
    local ok, data = pcall(src.newImageData, src)
    if not ok then return nil end
    return data, pw, ph
  end

  function S:pollPush()
    local p = self.pending
    if not p then return nil end
    local ok, data = pcall(p.src.pollImageData, p.src)
    if not ok then
      self.pending = nil
      return nil
    end
    if not data then return nil end
    self.pending = nil
    return data, p.w, p.h
  end

  return S
end
