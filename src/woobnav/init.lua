-- WoobNav: a Kanto Gear app listing every wild Pokemon on the player's map with its odds, and a
-- summary page per species. Reached only through Kanto Gear (its Silph Store / Home tile; the
-- Gear's module API, kanto_gear exports.modules, api 1): without the Gear nothing registers
-- and no hook is installed.
--
-- Read only: it shows exports.encounters (src/rates.lua through src/runtime.lua) and never
-- changes a table, a roll or the RNG. While it is open the Gear stands down and the WoobNav
-- shows itself (src/woobnav/display.lua) following the Gear's DISPLAY MODE; the buttons stay
-- with the game.
--
--   makeWoobNav({ mod, load = fn(path) -> chunk result, Rates })
--     -> WoobNav { registered, open(), close(), isOpen(), state, View, Display } | nil

return function(deps)
  local mod, load, Rates = deps.mod, deps.load, deps.Rates
  local function sub(name) return load("src/woobnav/" .. name .. ".lua") end

  local Layout, Gate = sub("layout"), sub("gate")
  local makeSurface, makeHost, makeDisplay = sub("surface"), sub("host"), sub("display")
  local makeArt, makeInfo, makeView, makeSpec = sub("art"), sub("info"), sub("view"), sub("gear")
  if not (Layout and Gate and makeSurface and makeHost and makeDisplay and makeArt and makeInfo
          and makeView and makeSpec and Rates) then
    mod.log:warn("WoobNav: a file is missing -- reinstall the mod; the Kanto Gear app is off")
    return nil
  end

  local ex = mod.exports
  local Art = makeArt(mod)
  local Info = makeInfo({ mod = mod, profileOf = function(id)
    local ok, p = pcall(ex.profileOf, id)
    return ok and p or nil
  end })
  local View = makeView({ Art = Art, Rates = Rates })

  local N = { View = View, Art = Art, Info = Info, registered = false }
  local state = { open = false, screen = "area", page = 1, tab = "info", rows = {}, stale = true }
  N.state = state

  local Display -- set below

  local function dirty()
    if Display then Display.dirty = true end
  end

  -- ------- the model

  local function tod()
    local ok, s = pcall(ex.settings)
    return ok and type(s) == "table" and s.timeOfDay or "off"
  end

  local NOTE_TIME = { MORN = "MORNING", DAY = "DAY", NITE = "NIGHT" }

  local function rowsOf(enc)
    local rows = {}
    for _, s in ipairs(enc and enc.sections or {}) do
      for _, m in ipairs(s.mons or {}) do
        rows[#rows + 1] = { id = m.id, name = Info.name(m.id), chance = m.chance, minLevel = m.minLevel,
                            maxLevel = m.maxLevel, method = s.method, time = s.time, pooled = m.pooled,
                            caught = Info.caught(m.id) }
      end
    end
    for _, r in ipairs(enc and enc.rare or {}) do
      rows[#rows + 1] = { id = r.id, name = Info.name(r.id), rare = true, odds = r.odds, method = r.method,
                          caught = false }
    end
    return rows
  end

  function N.refresh()
    state.stale = false
    local okM, mapId = pcall(ex.currentMap)
    mapId = okM and mapId or nil
    state.mapId = mapId
    local ok, enc = pcall(ex.encounters, mapId)
    enc = ok and enc or nil
    state.enc = enc
    state.rows = rowsOf(enc)
    state.page = math.min(state.page, View.pages(#state.rows))
    local note
    if enc and not enc.active then note = "GAME'S OWN"
    elseif enc and enc.random then note = "RANDOM"
    elseif enc and enc.time then note = NOTE_TIME[enc.time]
    elseif enc and enc.period then note = enc.period == "night" and "NIGHT" or "DAY" end
    state.model = {
      title = enc and enc.name or (mapId and tostring(mapId)) or "WOOBNAV",
      note = note, rows = state.rows, page = state.page,
      empty = enc and enc.random and "RANDOM: a new Pokemon every encounter here."
        or (mapId and "No wild Pokemon here." or "Step outside to scan the area."),
    }
    dirty()
  end

  -- where the chosen species is met here, at every time of day the map keeps apart
  local function hereOf(id)
    local out = {}
    local function add(enc, period)
      for _, s in ipairs(enc and enc.sections or {}) do
        for _, m in ipairs(s.mons or {}) do
          if m.id == id then
            out[#out + 1] = { method = s.method, time = s.time or period, chance = m.chance,
                              minLevel = m.minLevel, maxLevel = m.maxLevel }
          end
        end
      end
      for _, r in ipairs(enc and enc.rare or {}) do
        if r.id == id then out[#out + 1] = { method = r.method, rare = true, odds = r.odds } end
      end
    end
    local gen = tonumber(mod.generation) or 1
    if gen == 2 then
      local ok, enc = pcall(ex.encounters, state.mapId, { time = "all" })
      add(ok and enc or nil, nil)
    elseif tod() ~= "off" then
      local okD, day = pcall(ex.encounters, state.mapId, { period = "day" })
      local okN, night = pcall(ex.encounters, state.mapId, { period = "night" })
      local before = #out
      add(okD and day or nil, "DAY")
      local dayRows = #out - before
      add(okN and night or nil, "NITE")
      -- the same at both times: one row, no time on it
      if dayRows * 2 == #out - before then
        local same = true
        for i = before + 1, before + dayRows do
          local a, b = out[i], out[i + dayRows]
          if a.method ~= b.method or math.abs((a.chance or 0) - (b.chance or 0)) > 0.01 then same = false end
        end
        if same then
          for i = #out, before + dayRows + 1, -1 do table.remove(out, i) end
          for i = before + 1, before + dayRows do out[i].time = nil end
        end
      end
    else
      add(state.enc, nil)
    end
    -- the same odds and levels at several times of day: one row with each time's icon
    local merged, byKey = {}, {}
    for _, h in ipairs(out) do
      local key = table.concat({ h.method, tostring(h.rare), ("%.3f"):format(h.chance or 0),
                                 tostring(h.minLevel), tostring(h.maxLevel) }, "|")
      local m = byKey[key]
      if m and h.time and m.times then
        m.times[#m.times + 1] = h.time
      else
        h.times = h.time and { h.time } or nil
        byKey[key] = h
        merged[#merged + 1] = h
      end
    end
    for _, h in ipairs(merged) do
      -- every time of day: no time to show
      if h.times and #h.times >= ((tonumber(mod.generation) == 2) and 3 or 2) then h.times = nil end
      h.time = nil
    end
    return merged
  end

  local function openSummary(row)
    if not row then return end
    state.screen, state.tab, state.selected = "summary", "info", row.id
    state.page_ = state.page
    local ok, pg = pcall(Info.page, row.id)
    state.summary = ok and pg or { id = row.id, name = row.name, types = {}, stats = {}, abilities = {},
                                   line = {}, total = 0 }
    state.here = hereOf(row.id)
    dirty()
  end

  -- ------- open / close

  function N.open()
    state.open, state.screen, state.page, state.tab = true, "area", 1, "info"
    state.stale = true
    state.pressed, state.down = nil, nil
    dirty()
    return true
  end

  function N.close()
    state.open = false
    state.pressed, state.down = nil, nil
    dirty()
  end

  function N.isOpen() return state.open == true end

  -- ------- input

  local function act(target)
    if target == "back" then
      if state.screen == "summary" then
        state.screen = "area"
        dirty()
      else
        N.close()
      end
      return
    end
    if state.screen == "area" then
      local pages = View.pages(#state.rows)
      if target == "prev" then
        state.page = state.page <= 1 and pages or state.page - 1
      elseif target == "next" then
        state.page = state.page >= pages and 1 or state.page + 1
      else
        local n = target and tonumber(target:match("^card:(%d+)$"))
        if n then openSummary(state.rows[(state.page - 1) * View.PER_PAGE + n]) end
      end
      if state.model then state.model.page = state.page end
    elseif state.screen == "summary" then
      local tab = target and target:match("^tab:(%a+)$")
      if tab then state.tab = tab end
    end
    dirty()
  end
  N.act = act

  local function hitAt(x, y)
    return View.hit(state.screen, x, y, state.model)
  end

  function N.pointer(phase, x, y)
    if phase == "down" then
      local t = hitAt(x, y)
      state.down = { x = x, y = y, target = t }
      state.pressed = t
    elseif phase == "move" then
      local d = state.down
      if d then state.pressed = (hitAt(x, y) == d.target) and d.target or nil end
    elseif phase == "up" then
      local d = state.down
      state.down, state.pressed = nil, nil
      if not d then return end
      local t = hitAt(x, y)
      local dx, dy = (x or 0) - d.x, (y or 0) - d.y
      if state.screen == "area" and math.abs(dx) >= 40 and math.abs(dy) < 30 then
        act(dx < 0 and "next" or "prev")
      elseif t and t == d.target then
        act(t)
      end
    else
      state.down, state.pressed = nil, nil
    end
    dirty()
  end

  -- ------- drawing

  -- run each frame the WoobNav is up, outside its canvas: follows the player's map and builds
  -- the pictures the page will draw
  function N.prepare()
    if not state.open then return end
    local okM, mapId = pcall(ex.currentMap)
    mapId = okM and mapId or nil
    if mapId ~= state.mapId then
      state.page, state.screen = 1, "area"
      state.stale = true
    end
    if state.stale then N.refresh() end
    local ids = {}
    if state.screen == "summary" then
      ids[1] = state.selected
    else
      local first = (state.page - 1) * View.PER_PAGE
      for n = 1, View.PER_PAGE do
        local row = state.rows[first + n]
        if row then ids[#ids + 1] = row.id end
      end
    end
    Art.prepare(ids)
  end

  function N.draw(G, w, h)
    if state.screen == "summary" and state.summary then
      View.drawSummary(G, state.summary, state.here, state.tab, state.pressed)
    else
      View.drawArea(G, state.model or { rows = {} }, state.pressed)
    end
  end

  -- ------- events: what the list shows changes

  local function stale()
    state.stale = true
    dirty()
  end
  pcall(function()
    mod.events:on("map.entered", stale)
    mod.events:on("mod." .. mod.id .. ".tables_changed", stale)
    mod.events:on("mod." .. mod.id .. ".period_changed", stale)
    mod.events:on("world.tod_changed", stale)
    mod.events:on("mod.options_changed", stale)
    mod.events:on("battle.ended", function() Info.reset(); stale() end)
    for _, name in ipairs({ "save.loaded", "save.created", "checkpoint.restored" }) do
      mod.events:on(name, function()
        Info.reset()
        Art.dropPictures()
        stale()
      end)
    end
  end)

  -- ------- Kanto Gear

  local app = {
    isOpen = N.isOpen,
    draw = N.draw,
    pointer = N.pointer,
    prepare = N.prepare,
  }

  -- `stand` (tests, drivers): a stand-in for the Gear's exports.modules
  local function register(stand)
    if N.registered then return true end
    local gear = mod.find and mod:find("kanto_gear")
    local modules = stand or (gear and gear.exports and gear.exports.modules)
    if not (type(modules) == "table" and modules.api == 1 and type(modules.register) == "function") then
      return false
    end
    local spec = makeSpec({ shown = N.isOpen, open = N.open })
    local ok, done, why = pcall(modules.register, spec)
    if ok and done == true then
      N.registered = true
      local Surface = makeSurface(mod, Layout)
      local Host = makeHost(mod)
      Display = makeDisplay({ mod = mod, Layout = Layout, Surface = Surface, Gate = Gate, Host = Host, app = app })
      N.Display = Display
      Display.install()
      mod.log:info("WoobNav: in Kanto Gear's Silph Store")
      return true
    end
    mod.log:warn("WoobNav: Kanto Gear refused the app (%s)", tostring(ok and why or done))
    return false
  end
  N.register = register

  if not register() then
    -- the Gear's exports may come later than this mod's load
    pcall(function()
      mod.events:on("game.ready", function() register() end)
    end)
  end

  -- a test seam (not an API: it may change in any release)
  ex._woobnav = N
  return N
end
