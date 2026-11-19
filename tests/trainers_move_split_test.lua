-- Standalone: luajit mods/modern_spawns/tests/trainers_move_split_test.lua (from
-- the gen1recomp root; needs Crystal and Emerald imported and
-- mods/national_dex_gen3). TRAINER TEAMS' held items with WoobleDex's MOVE
-- SPLIT (physical / special by the move, as today's games, instead of by type):
--   * Choice Band goes to a Pokemon whose attacks are all physical and Choice
--     Specs to one whose attacks are all special -- by type with MOVE SPLIT
--     off, by the move with it on (Fire Punch and Crunch are physical, Shadow
--     Ball and Sludge Bomb special);
--   * Crystal and Emerald hand the item code each move's class from WoobleDex
--     only while MOVE SPLIT is on; off, the game's own split by type stands.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Rng = H.module("src/rng.lua")
local Items = H.module("src/trainer_items.lua")

local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

-- ------- the item: Band and Specs follow each move's class

local everything = function() return true end
-- no Eviolite / Black Sludge / Assault Vest / Life Orb / Choice Scarf / Focus Sash
local function ace(moves, stats)
  return Items.choose({ role = "ace", strong = true, mon = { types = set({ "GHOST" }), canEvolve = false, moves = moves },
    stats = stats, maxGen = 9, available = everything, rng = Rng.new(1) })
end
local special = { hp = 60, attack = 65, defense = 60, speed = 70, spAttack = 130, spDefense = 75 }
local physical = { hp = 60, attack = 130, defense = 60, speed = 70, spAttack = 65, spDefense = 75 }
T.eq(ace({ { type = "GHOST", power = 80 }, { type = "POISON", power = 90 } }, special), "LEFTOVERS",
     "split by type: Shadow Ball and Sludge Bomb are physical, so no Choice Specs for a special attacker")
T.eq(ace({ { type = "GHOST", power = 80, category = "special" }, { type = "POISON", power = 90, category = "special" } },
     special), "CHOICE_SPECS", "split by move: Shadow Ball and Sludge Bomb are special: Choice Specs")
T.eq(ace({ { type = "FIRE", power = 75 }, { type = "DARK", power = 80 } }, physical), "LEFTOVERS",
     "split by type: Fire Punch and Crunch are special, so no Choice Band for a physical attacker")
T.eq(ace({ { type = "FIRE", power = 75, category = "physical" }, { type = "DARK", power = 80, category = "physical" } },
     physical), "CHOICE_BAND", "split by move: Fire Punch and Crunch are physical: Choice Band")

-- ------- the games: each move's class, only while MOVE SPLIT is on

-- today's classes of moves Gen 2 and 3 split the other way by type
local MODERN = { SHADOW_BALL = "special", SLUDGE_BOMB = "special", CRUNCH = "physical", BITE = "physical",
  FIRE_PUNCH = "physical", ICE_PUNCH = "physical", THUNDERPUNCH = "physical", THUNDER_PUNCH = "physical",
  SHADOW_CLAW = "physical", DARK_PULSE = "special", SLUDGE_WAVE = "special", HYDRO_PUMP = "special",
  WATERFALL = "physical", CROSS_CHOP = "physical", SHADOW_PUNCH = "physical" }
local TYPE_PHYSICAL = set({ "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL" })
local SPECIES = { "GENGAR", "HAUNTER", "HOUNDOOM", "MUK", "HITMONCHAN", "TYRANITAR", "SNEASEL", "MISDREAVUS",
                  "GYARADOS", "FERALIGATR", "KINGDRA", "UMBREON", "WEEZING", "MACHAMP" }

local function check(label, game, gen)
  local data
  if gen == 2 then
    data = H.gen2Data(game)
  else
    H.mountGen3(game)
    data = H.gen3Data(game)
  end
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" }, { data = data, generation = gen })
  T.eq(#run.errors, 0, label .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "SPLIT" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9", trainer_teams = "items" }
  local setOpt, game_ = H.manager(loader)
  game_.data = data
  local ms = loader.exports.modern_spawns
  -- WoobleDex installs its battle wraps (MOVE SPLIT's included) once the game is ready
  loader.events:emit("game.ready", { game = game_ })
  local ManagerState = require("src.mods.ManagerState")
  local manager = setmetatable({ game = game_ }, { __index = ManagerState })
  local function split(on) ManagerState.setOption(manager, "national_dex_gen3", "move_split", on) end

  local function movesNow()
    local out = {}
    for _, id in ipairs(SPECIES) do
      for _, m in ipairs(ms._trainerMovesFor(id, 60) or {}) do
        if (tonumber(m.power) or 0) > 1 then out[#out + 1] = m end
      end
    end
    return out
  end

  split(false)
  local off = movesNow()
  T.check(#off > 20, label .. ": the item code sees the trainers' moves (" .. #off .. ")")
  local wrongOff = {}
  for _, m in ipairs(off) do
    local byType = TYPE_PHYSICAL[m.type] and "physical" or "special"
    -- Crystal gives no class (the item code splits by type); Emerald the engine's, by type
    if m.category ~= nil and m.category ~= byType then wrongOff[#wrongOff + 1] = m.name end
  end
  T.eq(table.concat(wrongOff, " "), "", label .. " MOVE SPLIT off: by type, the game's own split")

  split(true)
  local on, flipped, wrongOn = movesNow(), {}, {}
  for _, m in ipairs(on) do
    local want = MODERN[m.name]
    if want then
      if m.category ~= want then wrongOn[#wrongOn + 1] = m.name .. "=" .. tostring(m.category) end
      if want ~= (TYPE_PHYSICAL[m.type] and "physical" or "special") then flipped[m.name] = true end
    end
  end
  local names = {}
  for name in pairs(flipped) do names[#names + 1] = name end
  table.sort(names)
  T.check(#names >= 2, label .. " MOVE SPLIT on: moves whose class differs from their type's ("
    .. table.concat(names, ", ") .. ")")
  T.eq(table.concat(wrongOn, " "), "", label .. " MOVE SPLIT on: each move's class by the move")

  split(false)
  local again = movesNow()
  local same = #again == #off
  for i = 1, math.min(#again, #off) do
    if again[i].category ~= off[i].category then same = false end
  end
  T.check(same, label .. ": back off, back to the split by type")
  run.release()
end

check("Crystal", "crystal", 2)
check("Emerald", "emerald", 3)

T.finish("modern_spawns trainers (MOVE SPLIT)")
