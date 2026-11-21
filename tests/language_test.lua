-- Standalone: luajit mods/modern_spawns/tests/language_test.lua (from the gen1recomp root; needs
-- Crystal imported and mods/kanto_gear). LANGUAGE, the WoobNav's words:
--   * the option offers the seven languages lang/ has (WoobOS's and Kanto Gear's seven);
--   * every lang/ file is data only, has a name, only English's keys, and the same %s / %d;
--   * every character of every language is in WoobNav's fonts (HGSS, or the Japanese atlases);
--   * switching it changes the WoobNav's words at once and drops no spawn table (EVERY MAP's
--     rosters stay the same).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local ROOT = H.modRoot()

local function readFile(path)
  local f = io.open(ROOT .. "/" .. path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local makeI18n = H.module("src/i18n.lua")
local L = makeI18n({ read = readFile })

-- ------- the option and the files

do
  local schema = H.module("options.lua")
  local row
  for _, r in ipairs(schema) do if r.key == "language" then row = r end end
  T.check(row ~= nil and row.type == "choice", "a LANGUAGE choice row")
  T.eq(row.default, "en", "English by default")
  local codes = {}
  for i, c in ipairs(row.choices) do
    codes[i] = c[2]
    T.check(not c[1]:find("[\128-\255]"), c[1] .. ": an ASCII label (the Game Boy menus)")
  end
  T.eq(table.concat(codes, ","), table.concat(L.CODES, ","), "the row offers every language, in order")
  T.eq(#L.languages(), 7, "seven languages load (" .. #L.languages() .. ")")
end

local function signature(s)
  local out = {}
  for spec in s:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs])") do out[#out + 1] = spec end
  return table.concat(out)
end

do
  local en = L.raw("en")
  local hgss = H.module("assets/fonts/glyphs.lua")
  local ja = H.module("assets/fonts/ja_glyphs.lua")
  local have = {}
  for ch in (hgss .. ja):gmatch("[%z\1-\127\194-\244][\128-\191]*") do have[ch] = true end
  for _, lang in ipairs(L.languages()) do
    local words = L.raw(lang.code)
    local extra, missing, badFmt, badChar = {}, {}, {}, {}
    for k, v in pairs(words) do
      if en[k] == nil then extra[#extra + 1] = k end
      if en[k] and signature(v) ~= signature(en[k]) then badFmt[#badFmt + 1] = k end
      for ch in v:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if not have[ch] then badChar[ch] = true end
      end
    end
    for k in pairs(en) do if words[k] == nil then missing[#missing + 1] = k end end
    table.sort(extra); table.sort(missing); table.sort(badFmt)
    local chars = {}
    for ch in pairs(badChar) do chars[#chars + 1] = ch end
    T.eq(table.concat(extra, " "), "", lang.code .. ": no key English lacks")
    T.eq(table.concat(missing, " "), "", lang.code .. ": every English key")
    T.eq(table.concat(badFmt, " "), "", lang.code .. ": the same %s / %d as English")
    T.eq(table.concat(chars, " "), "", lang.code .. ": every character in the WoobNav's fonts")
    T.check(lang.name ~= lang.code, lang.code .. ": named (" .. lang.name .. ")")
  end
  -- the lookups
  L.set("de")
  T.eq(L("time.NITE"), "NACHT", "German words")
  T.eq(L.f("level.range", 3, 5), "Lv 3-5", "...formatted")
  T.eq(L("no.such.key"), "no.such.key", "an unknown key shows itself")
  T.eq(L.set("xx"), false, "an unknown language is refused")
  T.eq(L.code(), "de", "...and the language stays")
  L.set("en")
end

-- ------- in the WoobNav: Crystal with Kanto Gear

do
  local data = H.gen2Data("crystal")
  data.gen2Pokedex = dofile("crystal/data/generated/pokedex.lua")
  local run = T.sdk.loadMods({ "mods/kanto_gear", "mods/modern_spawns" }, { data = data, generation = 2 })
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "WOOBNAV" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", spawn_mode = "map" }
  local set, game = H.manager(loader)
  game.data = data
  local ex = loader.exports.modern_spawns
  local N = ex._woobnav
  if not N.registered then N.register({ api = 1, register = function() return true end }) end
  N.open()
  loader.events:emit("map.entered", { mapId = "ROUTE_32" })
  N.prepare()
  local s = N.state
  T.eq(N.T.code(), "en", "English to begin with")
  local enNote = s.model.note
  T.check(enNote == "MORNING" or enNote == "DAY" or enNote == "NIGHT", "the time in English (" .. tostring(enNote) .. ")")
  local before = ex.encounters("ROUTE_32")

  set("language", "fr")
  N.prepare()
  T.eq(N.T.code(), "fr", "LANGUAGE FRANCAIS: the WoobNav in French")
  local FR = { MORNING = "MATIN", DAY = "JOUR", NIGHT = "NUIT" }
  T.eq(s.model.note, FR[enNote], "...its words at once (" .. tostring(s.model.note) .. ")")
  T.eq(N.View.levelText(3, 5), "N. 3-5", "...the levels too")
  N.act("card:1")
  local pg = s.summary
  T.eq(pg.stats[1][1], "hp", "the stats keep their keys (the words come at draw time)")
  N.act("back")

  -- no spawn table dropped: EVERY MAP's roster for this visit is the same
  local after = ex.encounters("ROUTE_32")
  local function ids(enc)
    local out = {}
    for _, sec in ipairs(enc.sections or {}) do
      for _, m in ipairs(sec.mons or {}) do out[#out + 1] = sec.method .. ":" .. tostring(m.id) .. ":" .. m.chance end
    end
    return table.concat(out, ",")
  end
  T.eq(ids(after), ids(before), "LANGUAGE drops no table: EVERY MAP's roster is unchanged")

  set("language", "ja")
  N.prepare()
  T.eq(N.T("card.rare"), "レア", "Japanese")
  set("language", "en")
  N.prepare()
  T.eq(s.model.note, enNote, "back to English")
  N.close()
  run.release()
end

T.finish("modern_spawns LANGUAGE (the WoobNav's words)")
