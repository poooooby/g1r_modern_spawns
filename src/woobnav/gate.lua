-- WoobNav: who gets the second display. The engine hands every render.compose wrapper the
-- SecondScreen bridge in ctx.secondScreen (Kanto Gear takes it from there every frame). The
-- WoobNav wraps render.compose outside the Gear and passes the proxy below instead. While the
-- WoobNav claims the screen, the proxy tells the mods inside it the display is gone (detected()
-- false), swallows their frames and leaves the touch queue to the WoobNav. Released, it passes
-- every call through, and the display is enabled as the inner mod last asked. Pure: no love
-- calls. From NaviPlay's src/second_gate.lua (MIT, (c) 2026 poooooby).

local Gate = {}
Gate.__index = Gate

function Gate.new(real)
  local g = setmetatable({ real = real, claimed = false, wantedEnabled = nil }, Gate)
  local function pass(name, ...)
    local fn = real and real[name]
    if fn then return fn(...) end
  end
  g.proxy = {
    usable = function(...) return pass("usable", ...) end,
    available = function(...) return pass("available", ...) end,
    detected = function(...)
      if g.claimed then return false end
      return pass("detected", ...)
    end,
    push = function(...)
      if g.claimed then return true end
      return pass("push", ...)
    end,
    pollTouch = function(...)
      if g.claimed then return nil end
      return pass("pollTouch", ...)
    end,
    setEnabled = function(on, ...)
      g.wantedEnabled = on and true or false
      if g.claimed then return end
      return pass("setEnabled", on, ...)
    end,
  }
  -- anything else the bridge offers passes through untouched
  setmetatable(g.proxy, { __index = function(_, k)
    local v = real and real[k]
    if type(v) == "function" then return function(...) return v(...) end end
    return v
  end })
  return g
end

function Gate:claim()
  self.claimed = true
end

-- hands the display back, enabled as the inner mod last asked (off when it never asked)
function Gate:release()
  if not self.claimed then return end
  self.claimed = false
  local fn = self.real and self.real.setEnabled
  if fn then pcall(fn, self.wantedEnabled or false) end
end

return Gate
