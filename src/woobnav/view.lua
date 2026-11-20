-- WoobNav: its two screens on the 240x216 logical space, in Kanto Gear's pixel style.
--
--   AREA      the header (back to Kanto Gear, the place's name), six cards a page (two across,
--             three down: picture, name, chance, levels, how it's met), the page buttons
--   SUMMARY   the header (back to the list, the species' name), its picture, number, types,
--             category, height and weight; where it is met HERE; tabs INFO / STATS / EVOLVES
--
-- Layout and hit-testing are pure (View.hit, View.pages); drawing goes through src/woobnav/art.lua.

return function(deps)
  local Art, Rates = deps.Art, deps.Rates
  local floor, max, min = math.floor, math.max, math.min
  local View = {}

  View.PER_PAGE = 6
  local CARD_W, CARD_H = 114, 50
  local GRID_X, GRID_Y, GAP_X, GAP_Y = 4, 30, 4, 3
  local FOOT_Y, FOOT_H = 190, 22
  local PREV = { x = 4, y = FOOT_Y, w = 44, h = FOOT_H }
  local NEXT = { x = 192, y = FOOT_Y, w = 44, h = FOOT_H }
  local BACK = { x = 0, y = 0, w = 26, h = 24 }
  local TAB_Y, TAB_H = 128, 16
  local TABS = { "info", "stats", "evolves" }
  local TAB_LABEL = { info = "INFO", stats = "STATS", evolves = "EVOLVES" }

  function View.card(i)
    local slot = (i - 1) % View.PER_PAGE
    local col, row = slot % 2, floor(slot / 2)
    return { x = GRID_X + col * (CARD_W + GAP_X), y = GRID_Y + row * (CARD_H + GAP_Y), w = CARD_W, h = CARD_H }
  end

  local function tabRect(i)
    local w = 74
    return { x = 4 + (i - 1) * (w + 5), y = TAB_Y, w = w, h = TAB_H }
  end

  function View.pages(n)
    return max(1, math.ceil((n or 0) / View.PER_PAGE))
  end

  local function inside(r, x, y)
    return x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
  end

  -- what a point touches: "back", "prev", "next", "card:<n on the page>", "tab:<name>" or nil
  function View.hit(screen, x, y, model)
    if not (x and y) then return nil end
    if inside(BACK, x, y) then return "back" end
    if screen == "area" then
      local pages = View.pages(model and #model.rows or 0)
      if pages > 1 and inside(PREV, x, y) then return "prev" end
      if pages > 1 and inside(NEXT, x, y) then return "next" end
      local first = ((model and model.page or 1) - 1) * View.PER_PAGE
      for n = 1, View.PER_PAGE do
        if model and model.rows[first + n] and inside(View.card(n), x, y) then return "card:" .. n end
      end
    elseif screen == "summary" then
      for i, name in ipairs(TABS) do
        if inside(tabRect(i), x, y) then return "tab:" .. name end
      end
    end
    return nil
  end

  -- ------- drawing

  local function levelText(lo, hi)
    lo, hi = tonumber(lo), tonumber(hi)
    if not lo then return "" end
    if hi and hi ~= lo then return ("Lv %d-%d"):format(lo, hi) end
    return ("Lv %d"):format(lo)
  end
  View.levelText = levelText

  local METHOD_NAME = { grass = "GRASS", cave = "CAVE", surf = "SURF", old = "OLD ROD", good = "GOOD ROD",
                        super = "SUPER ROD", rock = "ROCK SMASH" }
  View.METHOD_NAME = METHOD_NAME

  local function chanceText(row)
    if row.rare then return "RARE" end
    return Rates.text(row.chance)
  end

  local function pageButton(r, left, enabled, pressed)
    local a = enabled and Art.C.acc or Art.rampOf(Art.C.silverDark)
    local off = Art.button(r.x, r.y, r.w, r.h, a, pressed and enabled, 4)
    Art.ART(left and Art.CHEV_L or Art.CHEV_R, r.x + floor(r.w / 2) - 1, r.y + 7 + off, { ["#"] = Art.WHITE })
  end

  local function card(row, r, pressed)
    local C = Art.C
    Art.window(r.x, r.y, r.w, r.h, pressed and C.focus or (row.rare and Art.hex("fff6dc") or C.surface))
    -- the seat behind the picture
    Art.RR(r.x + 3, r.y + 3, 46, 44, 3, C.paper2)
    Art.R(r.x + 5, r.y + 42, 42, 3, C.line)
    if not Art.pokemon(row.id, r.x + 26, r.y + 45, 44, 42) then
      Art.text("label", "?", r.x + 22, r.y + 16, C.disabled)
    end
    local tx = r.x + 52
    Art.text("small", Art.fit("small", row.name, r.w - 64), tx, r.y + 3, C.ink)
    if row.caught then Art.ball(r.x + r.w - 10, r.y + 4) end
    local pct = chanceText(row)
    Art.text("label", pct, tx, r.y + 15, row.rare and C.amber or C.ink)
    Art.methodIcon(row.method, tx, r.y + 39)
    local lv = row.rare and ("1 in " .. tostring(row.odds or 1024)) or levelText(row.minLevel, row.maxLevel)
    local after = tx + 10
    if row.time then
      Art.timeIcon(row.time, after, r.y + 39)
      after = after + 9
    end
    Art.text("small", Art.fit("small", lv, r.x + r.w - 3 - after), after, r.y + 37, C.muted)
    -- the odds at a glance: a hairline as Kanto Gear's wild cards have
    if not row.rare then
      local f = max(1, floor(56 * min(1, (row.chance or 0) / 50) + 0.5))
      local cc = (row.chance or 0) >= 25 and C.hp or (row.chance or 0) >= 10 and C.hpMid or Art.hex("c070f0")
      Art.R(tx, r.y + 34, 56, 1, C.line)
      Art.R(tx, r.y + 34, f, 1, cc)
    end
  end

  -- model = { title, note, rows, page, empty }
  function View.drawArea(G, model, pressed)
    local C = Art.C
    Art.backdrop(23)
    Art.header(model.title or "WOOBNAV", nil, true, pressed == "back")
    local rows = model.rows or {}
    if #rows == 0 then
      Art.window(14, 70, 212, 60)
      local lines = Art.wrap("label", model.empty or "No wild Pokemon here.", 196)
      for i, l in ipairs(lines) do
        local w = Art.width("label", l)
        Art.text("label", l, 120 - floor(w / 2), 78 + (i - 1) * 15, C.ink)
      end
    end
    local page = model.page or 1
    local first = (page - 1) * View.PER_PAGE
    for n = 1, View.PER_PAGE do
      local row = rows[first + n]
      if row then card(row, View.card(n), pressed == "card:" .. n) end
    end
    -- the foot: pages, and what these numbers are
    local pages = View.pages(#rows)
    Art.window(52, FOOT_Y + 1, 136, FOOT_H - 2, C.surface, nil, false)
    local mid = model.note and (model.note .. "  " .. page .. "/" .. pages) or (page .. "/" .. pages)
    mid = Art.fit("small", mid, 128)
    local w = Art.width("small", mid)
    Art.text("small", mid, 120 - floor(w / 2), FOOT_Y + 5, C.muted)
    if pages > 1 then
      pageButton(PREV, true, true, pressed == "prev")
      pageButton(NEXT, false, true, pressed == "next")
    end
  end

  local function typePill(name, x, y)
    local c = Art.TYPE[name] or Art.C.silverDark
    local w = Art.width("small", name) + 8
    Art.RR(x, y, w, 12, 3, Art.mix(c, { 0, 0, 0, 1 }, 0.35))
    Art.RR(x + 1, y + 1, w - 2, 10, 2, c)
    Art.text("small", name, x + 4, y, Art.WHITE)
    return w
  end

  local function statBars(pg, x, y, w)
    local C = Art.C
    local n = #pg.stats
    local rowH = n > 5 and 8 or 10
    for i, s in ipairs(pg.stats) do
      local yy = y + (i - 1) * rowH
      Art.text("small", s[1], x, yy - 2, C.muted)
      Art.text("small", tostring(s[2]), x + 44, yy - 2, C.ink, 20, "right")
      local bw = w - 72
      local f = max(1, floor(bw * min(1, s[2] / 200) + 0.5))
      local cc = s[2] >= 90 and C.hp or s[2] >= 50 and C.hpMid or C.hpLow
      Art.R(x + 70, yy + 3, bw, 4, C.line)
      Art.R(x + 70, yy + 3, f, 4, cc)
    end
    Art.text("small", "TOTAL " .. tostring(pg.total), x, y + n * rowH - 1, C.ink)
  end

  -- here = { { method, time?, chance, minLevel, maxLevel, rare? } }
  function View.drawSummary(G, pg, here, tab, pressed)
    local C = Art.C
    Art.backdrop(23)
    Art.header(pg.name or "?", pg.types[1] and Art.TYPE[pg.types[1]] or nil, true, pressed == "back")
    -- the top card
    Art.window(4, 28, 232, 64)
    Art.RR(7, 31, 64, 58, 3, C.paper2)
    Art.R(9, 84, 60, 3, C.line)
    if not Art.pokemon(pg.id, 39, 87, 62, 56) then Art.text("label", "?", 35, 50, C.disabled) end
    local x = 76
    local no = pg.dex and ("No. %03d"):format(pg.dex) or "No. ---"
    Art.text("small", no, x, 31, C.muted)
    if pg.caught then Art.ball(x + Art.width("small", no) + 4, 33) end
    local px = x
    for _, t in ipairs(pg.types) do px = px + typePill(t, px, 44) + 3 end
    if pg.category then Art.text("small", Art.fit("small", pg.category .. " Pokemon", 156), x, 58, C.ink) end
    if pg.height then Art.text("small", "HT " .. pg.height, x, 68, C.muted) end
    if pg.weight then Art.text("small", "WT " .. pg.weight, x, 78, C.muted) end
    -- where it is met here
    Art.window(4, 95, 232, 31)
    Art.text("small", "HERE", 8, 98, C.acc.D)
    local shown = 0
    for i, h in ipairs(here or {}) do
      if i > 4 then break end
      shown = i
      local col, row = (i - 1) % 2, floor((i - 1) / 2)
      local hx, hy = 38 + col * 98, 99 + row * 12
      Art.methodIcon(h.method, hx, hy + 2)
      local tx = hx + 10
      for _, t in ipairs(h.times or (h.time and { h.time }) or {}) do
        Art.timeIcon(t, tx, hy + 2)
        tx = tx + 8
      end
      if h.times or h.time then tx = tx + 1 end
      local s = (h.rare and ("1/" .. tostring(h.odds or 1024)) or Rates.text(h.chance)) .. " " .. levelText(h.minLevel, h.maxLevel)
      Art.text("small", Art.fit("small", s, hx + 96 - tx), tx, hy - 1, C.ink)
    end
    if shown == 0 then Art.text("small", "Not met here now", 38, 104, C.muted) end
    if #(here or {}) > 4 then Art.text("small", "+" .. (#here - 4), 214, 112, C.muted) end
    -- the tabs
    for i, name in ipairs(TABS) do
      local r = tabRect(i)
      local on = tab == name
      local a = on and Art.C.acc or Art.rampOf(Art.hex("8c9a92"))
      local off = Art.button(r.x, r.y, r.w, r.h, a, pressed == "tab:" .. name or on, 4)
      local label = TAB_LABEL[name]
      local w = Art.width("small", label)
      Art.text("small", label, r.x + floor((r.w - w) / 2), r.y + 1 + off, Art.WHITE)
    end
    -- the tab's page
    Art.window(4, 147, 232, 66)
    if tab == "stats" then
      if #pg.stats > 0 then statBars(pg, 10, 151, 220)
      else Art.text("small", "No stats known.", 10, 152, C.muted) end
    elseif tab == "evolves" then
      local y = 151
      if #pg.line <= 1 then
        Art.text("small", "It does not evolve.", 10, y, C.muted)
      end
      if #pg.line > 1 then
        for i, step in ipairs(pg.line) do
          if i > 5 then break end
          local yy = y + (i - 1) * 12
          local name = step.name or step.id
          local mark = step.id == pg.id and "> " or "  "
          Art.text("small", mark .. name, 10, yy, step.id == pg.id and C.acc.D or C.ink)
          if step.how then Art.text("small", step.how, 150, yy, C.muted) end
        end
      end
      if #pg.abilities > 0 then
        Art.text("small", Art.fit("small", "ABILITY " .. table.concat(pg.abilities, " / "), 220), 10, 199, C.muted)
      end
    else
      local lines = Art.wrap("small", pg.text ~= nil and pg.text ~= "" and pg.text or "No Pokedex entry.", 220)
      for i, l in ipairs(lines) do
        if i > 6 then break end
        Art.text("small", l, 10, 150 + (i - 1) * 10, C.ink)
      end
    end
  end

  return View
end
