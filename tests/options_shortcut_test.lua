-- Standalone: luajit mods/modern_spawns/tests/options_shortcut_test.lua (from
-- the gen1recomp root; needs Red, Crystal and FireRed imported). The WOOBLESPAWNS row
-- on the game's OPTION screen:
--   * it is added after every other row (Red, Crystal, FireRed);
--   * A opens the Mod Manager on WoobleSpawns' settings page, whose rows are
--     this mod's options (GENERATIONS, TRAINER TEAMS...);
--   * B there closes the Manager, back to OPTION.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local StateStack = require("src.core.StateStack")
local Data = require("src.core.Data")
Data:load()

local function sameRows(_, rows) return rows end
local VANILLA = { { id = "textSpeed", label = "TEXT SPEED" }, { id = "mods", label = "MODS" } }

local function check(name, run)
  T.eq(#run.errors, 0, name .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local rows = Runtime.call("ui.options.rows", sameRows, {}, { VANILLA[1], VANILLA[2] })
  T.eq(#rows, 3, name .. ": one row added")
  T.eq(rows[1].id, "textSpeed", name .. ": the game's rows come first")
  local row = rows[3]
  T.eq(row.id, "modern_spawns:settings", name .. ": the WoobleSpawns row is last")
  T.eq(row.label, "WOOBLESPAWNS", name .. ": labelled WOOBLESPAWNS")
  T.eq(row.value({}), "OPEN", name .. ": its value reads OPEN")
  T.check(row.step == nil and type(row.activate) == "function", name .. ": A opens it, left/right do nothing")
  return row
end

-- ------- Red: the row, and A / B in the Mod Manager

local red = T.sdk.loadMods({ "mods/modern_spawns" }, { data = Data })
local row = check("Red", red)
local loader = red.loader
loader.modOptions.modern_spawns = { enabled = "on" }
local game = { mods = loader, save = { options = {} }, writeOptions = function() end,
               stack = setmetatable({ states = {} }, { __index = StateStack }) }
loader.game = game
row.activate(game)
local top = game.stack.states[#game.stack.states]
T.check(top and top.screenId == "ManagerState", "A pushes the Mod Manager")
T.eq(top and top.screen, "options", "it opens on a settings page")
T.eq(top and top.currentMod and top.currentMod.id, "modern_spawns", "WoobleSpawns' settings page")
local keys = {}
for _, r in ipairs(top and top.optionRows or {}) do keys[#keys + 1] = tostring(r.key or r.id or r.label) end
local listed = table.concat(keys, ",")
T.check(listed:find("max_generation", 1, true) and listed:find("trainer_teams", 1, true),
        "its rows are this mod's options (" .. listed .. ")")
T.eq(#(top and top.backStack or { 1 }), 0, "nothing under it in the Manager")
local depth = #game.stack.states
top:goBack()
T.eq(#game.stack.states, depth - 1, "B closes the Manager, back to OPTION")
red.release()

-- ------- Crystal: the same row on Gen 2's OPTION screen

local crystal = T.sdk.loadMods({ "mods/modern_spawns" }, { data = H.gen2Data("crystal"), generation = 2 })
check("Crystal", crystal)
crystal.release()

-- ------- FireRed: Gen 3 opens the Manager as its own overlay

local firered = T.sdk.loadMods({ "mods/modern_spawns" }, { data = H.gen3Data("firered"), generation = 3 })
local g3row = check("FireRed", firered)
local g3game = { mods = firered.loader, options = {}, save = { options = {} }, writeOptions = function() end }
firered.loader.game = g3game
g3row.activate(g3game)
local Overlay = require("src.ui.game3.mod_manager")
local mgr = Overlay._mgr
T.check(Overlay.open and mgr ~= nil, "Gen 3: A opens the Mod Manager")
T.eq(mgr and mgr.screen, "options", "Gen 3: on a settings page")
T.eq(mgr and mgr.currentMod and mgr.currentMod.id, "modern_spawns", "Gen 3: WoobleSpawns' settings page")
if mgr then mgr:goBack() end
T.eq(Overlay.open, false, "Gen 3: B closes the Manager, back to OPTION")
firered.release()

T.finish("modern_spawns OPTION shortcut")
