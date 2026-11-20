-- Standalone: luajit mods/modern_spawns/tests/woobnav_test.lua (from the gen1recomp root;
-- needs Crystal and Emerald imported, mods/kanto_gear and mods/national_dex_gen3). The WoobNav,
-- a Kanto Gear app:
--   * its Store spec passes Kanto Gear's own checks (24x24 icon, words, accent, gens 1-3);
--   * with the Gear, it registers and installs its hooks; without it, nothing (no hook);
--   * the area list is every species exports.encounters lists, six a page, the pages wrap and
--     a swipe turns them; a card opens the species' summary, the tabs switch, back goes to the
--     list, back again closes it (shown() false, the Gear resumes);
--   * the summary has the species' number, types, stats and evolution line, and where it is
--     met on the map at each time of day;
--   * the layout: Kanto Gear's 240x216 screen, its COMBINED SCREEN cuts, touches mapped in;
--   * the second-display gate mutes the Gear while the WoobNav holds the display.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Layout = H.module("src/woobnav/layout.lua")
local Gate = H.module("src/woobnav/gate.lua")
local makeSpec = H.module("src/woobnav/gear.lua")

-- ------- the Store spec, against Kanto Gear's rules (runtime/modules.lua validate)

do
  local spec = makeSpec({ shown = function() return false end, open = function() return true end })
  T.check(type(spec.id) == "string" and spec.id:match("^[a-z][a-z0-9_]*$") ~= nil, "id: lowercase letters, digits, _")
  T.check(#spec.label > 0 and #spec.label <= 20, "label: 1-20 characters")
  T.check(#spec.description >= 1 and #spec.description <= 3, "description: 1-3 lines")
  local accents = { blue = true, amber = true, red = true, green = true, slate = true }
  T.check(accents[spec.accent] == true, "accent: one of the Gear's")
  T.eq(#spec.icon.rows, 24, "icon: 24 rows")
  local badRow, badChar = {}, {}
  for i, row in ipairs(spec.icon.rows) do
    if #row ~= 24 then badRow[#badRow + 1] = i end
    for ch in row:gmatch(".") do
      if ch ~= "." and ch ~= "o" and not (spec.icon.pal[ch] and spec.icon.pal[ch]:match("^%x%x%x%x%x%x$")) then
        badChar[ch] = true
      end
    end
  end
  T.eq(table.concat(badRow, ","), "", "icon: every row 24 wide")
  T.eq(next(badChar), nil, "icon: every colour is in the palette, as six hex digits")
  for _, g in ipairs({ 1, 2, 3 }) do
    T.eq(spec.available({ generation = g, gen3 = g == 3 }), true, "available on Gen " .. g)
  end
  T.eq(spec.available(nil), false, "not without a game")
  for lang, words in pairs(spec.translations) do
    T.check(words[spec.label] ~= nil, lang .. ": the label translated")
  end
end

-- ------- layout

do
  T.eq(Layout.W, 240, "Kanto Gear's screen width")
  T.eq(Layout.H, 216, "Kanto Gear's screen height")
  local side = Layout.gear(1280, 720, { layout = "side" })
  T.check(side.surface.x >= side.game.w and side.surface.w <= 1280 - side.game.w, "side: the WoobNav right of the game")
  T.check(math.abs(side.surface.w / side.surface.h - 240 / 216) < 0.02, "side: at the screen's own shape")
  local stacked = Layout.gear(720, 1280, { layout = "stacked" })
  T.check(stacked.surface.y >= stacked.game.h, "stacked: the WoobNav under the game")
  local full = Layout.gear(1280, 720, { layout = "fullscreen" })
  T.eq(full.game.w, 1280, "fullscreen: the whole window")
  local lx, ly, inside = Layout.toLogical({ x = 100, y = 50, scale = 2 }, 100 + 40, 50 + 30)
  T.check(lx == 20 and ly == 15 and inside, "a window point maps into the screen")
  local _, _, outside = Layout.toLogical({ x = 100, y = 50, scale = 2 }, 90, 50)
  T.eq(outside, false, "a point left of it is outside")
  local a, x, y = Layout.parseTouch("down,12,34")
  T.check(a == "down" and x == 12 and y == 34, "a second-display touch")
  a, x, y = Layout.parseTouch("56,78")
  T.check(a == "tap" and x == 56 and y == 78, "a bare point is a tap")
  T.eq(Layout.parseTouch("nonsense"), nil, "anything else is nothing")
end

-- ------- the second-display gate

do
  local b = { pushes = 0, enabled = {}, queue = { "down,1,2" } }
  b.usable = function() return true end
  b.available = function() return true end
  b.detected = function() return true end
  b.push = function() b.pushes = b.pushes + 1; return true end
  b.pollTouch = function() return table.remove(b.queue, 1) end
  b.setEnabled = function(on) b.enabled[#b.enabled + 1] = on end
  local g = Gate.new(b)
  local p = g.proxy
  T.eq(p.detected(), true, "unclaimed: the display is there for the Gear")
  g:claim()
  T.eq(p.detected(), false, "claimed: the Gear sees no display")
  T.eq(p.push({}, 1, 1), true, "claimed: the Gear's frame is taken...")
  T.eq(b.pushes, 0, "...and dropped")
  T.eq(p.pollTouch(), nil, "claimed: no touch reaches the Gear")
  T.eq(#b.queue, 1, "claimed: the touch is left for the WoobNav")
  p.setEnabled(true)
  T.eq(#b.enabled, 0, "claimed: the Gear's enable only noted")
  g:release()
  T.eq(b.enabled[1], true, "released: enabled as the Gear asked")
  T.eq(p.detected(), true, "released: the Gear has the display again")
end

-- ------- without Kanto Gear: no app, no hook

do
  local data = H.gen2Data("crystal")
  local run = T.sdk.loadMods({ "mods/modern_spawns" }, { data = data, generation = 2 })
  local N = run.loader.exports.modern_spawns._woobnav
  T.check(N ~= nil and N.registered == false, "without Kanto Gear the WoobNav is not registered")
  T.eq(Runtime.wantsHook("render.viewport"), false, "...and wraps no render hook")
  T.eq(Runtime.wantsHook("input.pointer"), false, "...nor the pointer")
  run.release()
end

-- ------- Crystal with Kanto Gear

local function crystal()
  local data = H.gen2Data("crystal")
  data.gen2Pokedex = dofile("crystal/data/generated/pokedex.lua")
  local run = T.sdk.loadMods({ "mods/kanto_gear", "mods/modern_spawns" }, { data = data, generation = 2 })
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "WOOBNAV" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  local set, game = H.manager(loader)
  game.data = data
  return run, loader, set
end

do
  local run, loader = crystal()
  local gearRec = loader.mods.kanto_gear
  local ex = loader.exports.modern_spawns
  local N = ex._woobnav
  if gearRec and gearRec.state == "loaded" then
    T.eq(N.registered, true, "Kanto Gear: the WoobNav registers in its Store")
    T.eq(Runtime.wantsHook("render.viewport"), true, "...and its display hooks are in")
  else
    -- the Gear switched off for Crystal on this machine: the app's own flow is tested anyway
    T.check(true, "Kanto Gear off here (" .. tostring(gearRec and gearRec.state) .. "): registration skipped")
    N.register({ api = 1, register = function() return true end })
  end
  T.eq(N.isOpen(), false, "closed until the Gear opens it")
  T.eq(N.open(), true, "opening answers true (the screen is taken)")
  T.eq(N.isOpen(), true, "shown() is true while open")

  -- a battle hands the screen to Kanto Gear, and it comes back after
  T.eq(N.inBattle(), false, "no battle on the field")
  N.battleOverride = true
  T.eq(N.shown(), false, "in a battle: not shown, so the Gear takes over")
  T.eq(N.isOpen(), true, "...though still open underneath")
  T.eq(N.Display.wantedMode(), "off", "...and its display stands down")
  N.battleOverride = false
  T.eq(N.shown(), true, "after the battle: shown again")
  T.eq(N.state.stale, true, "...its list read afresh")
  N.battleOverride = nil

  -- the display it asks for
  local D = N.Display
  D.state.gearOptions = { display_mode = "combined" }
  T.eq(D.wantedMode(), "split", "COMBINED SCREEN: the window split")
  D.state.gearOptions = { display_mode = "fullscreen" }
  T.eq(D.wantedMode(), "split", "FULLSCREEN: the window, the WoobNav alone on it")
  T.eq(D.state.style, "fullscreen", "...as fullscreen")
  D.state.gearOptions = { display_mode = "phone" }
  T.eq(D.wantedMode(), "split", "PHONE: the window (no stream for another mod's frames)")
  D.state.gearOptions = nil

  -- the area list
  loader.events:emit("map.entered", { mapId = "ROUTE_32" })
  N.prepare()
  local s = N.state
  T.eq(s.mapId, "ROUTE_32", "the player's map")
  T.eq(s.model.title, ex.areaName("ROUTE_32"), "titled with the place's name")
  local enc = ex.encounters("ROUTE_32")
  local want = #enc.rare
  for _, sec in ipairs(enc.sections) do want = want + #sec.mons end
  T.eq(#s.rows, want, "a card for every species of every way it's met (" .. want .. ")")
  local first = s.rows[1]
  T.check(first.chance and first.chance > 0 and first.minLevel and first.method, "a card has its chance, levels and method")
  local pages = N.View.pages(#s.rows)
  T.check(pages >= 2, "Route 32 runs to more than one page (" .. pages .. ")")
  T.eq(N.View.PER_PAGE, 6, "six a page")
  -- paging: buttons, wrap, swipe
  T.eq(N.View.hit("area", 200, 200, s.model), "next", "the next-page button")
  T.eq(N.View.hit("area", 10, 200, s.model), "prev", "the previous-page button")
  T.eq(N.View.hit("area", 10, 10, s.model), "back", "the back button, top left")
  N.act("next")
  T.eq(s.page, 2, "next page")
  N.act("prev")
  N.act("prev")
  T.eq(s.page, pages, "previous from the first wraps to the last")
  N.act("next")
  T.eq(s.page, 1, "next from the last wraps to the first")
  N.pointer("down", 200, 100)
  N.pointer("move", 120, 102)
  N.pointer("up", 100, 104)
  T.eq(s.page, 2, "a swipe left turns the page")
  N.pointer("down", 60, 100)
  N.pointer("up", 140, 100)
  T.eq(s.page, 1, "a swipe right turns it back")
  -- a tap: down and up on the same card
  local card1 = N.View.card(1)
  N.pointer("down", card1.x + 10, card1.y + 10)
  T.eq(s.pressed, "card:1", "the pressed card shows pressed")
  N.pointer("up", card1.x + 11, card1.y + 10)
  T.eq(s.screen, "summary", "a tap on a card opens its summary")
  T.eq(s.selected, s.rows[1].id, "...of that species")

  -- the summary
  local pg = s.summary
  T.check(pg.dex and pg.dex > 0, "its National number")
  T.check(#pg.types >= 1, "its types")
  T.check(#pg.stats == 6 and pg.total > 0, "six base stats and their total")
  T.check(pg.category ~= nil and pg.height ~= nil and pg.weight ~= nil, "category, height and weight")
  T.check(type(pg.text) == "string" and #pg.text > 10, "the Pokedex's words")
  T.check(#pg.line >= 1, "its evolution line")
  T.check(#s.here >= 1, "where it's met here")
  for _, h in ipairs(s.here) do
    T.check(h.chance and h.chance > 0 and h.method, "a HERE row has its odds and method")
  end
  T.eq(N.View.hit("summary", 100, 135, s.model), "tab:stats", "the STATS tab")
  N.act("tab:stats")
  T.eq(s.tab, "stats", "a tab switches the page")
  -- the theme button, top right on both screens: a moon by day, a sun by night
  local Art = N.Art
  T.eq(N.View.hit("summary", 228, 10, s.model), "theme", "the theme button, top right (summary)")
  T.eq(N.View.hit("area", 228, 10, s.model), "theme", "...and on the list")
  T.eq(Art.dark, false, "light (Kanto Gear's Pokegear) to begin with")
  N.pointer("down", 228, 10)
  T.eq(s.pressed, "theme", "the theme button shows pressed")
  N.pointer("up", 229, 11)
  T.eq(Art.dark, true, "a tap on the moon: night mode")
  T.eq(s.screen, "summary", "...on the same page")
  T.eq(Art.C.surface, Art.DARK.surface, "...its windows dark")
  T.eq(Art.C.ink, Art.DARK.ink, "...its ink light")
  T.eq(loader.modSave.modern_spawns.woobnav_dark, true, "...kept with the save")
  N.loadTheme()
  T.eq(Art.dark, true, "read back from the save")
  N.act("theme")
  T.eq(Art.dark, false, "a tap on the sun: light again")
  T.eq(Art.C.surface, Art.LIGHT.surface, "...its windows light")
  T.eq(loader.modSave.modern_spawns.woobnav_dark, false, "...kept with the save")
  N.act("back")
  T.eq(s.screen, "area", "back: the list again")
  T.eq(N.isOpen(), true, "...still open")
  N.act("back")
  T.eq(N.isOpen(), false, "back on the list closes the WoobNav (the Gear resumes)")
  run.release()
end

-- ------- Emerald: the time of day, and a summary from Gen 3's own Pokedex

do
  H.mountGen3("emerald")
  local data = H.gen3Data("emerald")
  local run = T.sdk.loadMods({ "mods/kanto_gear", "mods/national_dex_gen3", "mods/modern_spawns" },
                             { data = data, generation = 3 })
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "WOOBNAV" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", time_of_day = "prefer" }
  local set, game = H.manager(loader)
  game.data = data
  local ex = loader.exports.modern_spawns
  local N = ex._woobnav
  ex._pinPeriod("night")
  N.open()
  loader.events:emit("map.entered", { mapId = "EM_ROUTE101" })
  N.prepare()
  local s = N.state
  T.check(#s.rows >= 3, "Emerald Route 101 listed (" .. #s.rows .. ")")
  T.eq(s.model.note, "NIGHT", "the list says it's the night's")
  N.act("card:1")
  local pg = s.summary
  T.check(pg.dex and #pg.types >= 1 and #pg.stats == 6 and pg.total > 0, "Gen 3: number, types and stats")
  T.check(#pg.abilities >= 1, "Gen 3: its abilities")
  ex._pinPeriod(nil)
  N.close()
  run.release()
end

T.finish("modern_spawns WoobNav (Kanto Gear app)")
