-- Standalone: luajit mods/modern_spawns/tests/trainers_gen2_test.lua (from the
-- gen1recomp root; needs Crystal imported). TRAINER TEAMS on Gold/Silver/Crystal:
--   * OFF: no trainer.party wrapper, the battle's own Pokemon;
--   * Falkner's team is all Flying types, Morty's all Ghost, Karen's all Dark;
--   * the rival's lines are the same new families in every fight;
--   * rebuilt Pokemon are the new species' (stats, name), at the game's level,
--     keeping the game's own held items;
--   * ON + ITEMS: every item handed out exists and works in this game;
--   * the Battle Tower (member id 1) and link battles (no class) are left alone.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Mon = require("src.battle.gen2.Mon")
local Trainers = require("src.world.gen2.Trainers")

local data = H.gen2Data("crystal")
local run = T.sdk.loadMods({ "mods/modern_spawns" }, { data = data, generation = 2 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "JOHTO" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local set, game = H.manager(loader)
game.data = data
local api = loader.exports.modern_spawns

local function member(class, id)
  for _, m in ipairs(data.gen2Trainers.classes[class].trainers) do
    if m.id == id then return m end
  end
end
local function battle(class, id)
  local m = member(class, id)
  local own = Trainers.party(data, { roster = m.party })
  return Runtime.call("trainer.party", function(_, _, p) return p end, class, id, own), own, m
end
local function types(species)
  local s = {}
  for _, t in ipairs(data.pokemon[species].types) do s[(t:gsub("_TYPE$", ""))] = true end
  return s
end

-- ------- OFF

T.eq(Runtime.wantsHook("trainer.party"), false, "OFF: no trainer.party wrapper")
local out, own = battle("FALKNER", "FALKNER1")
T.check(out == own, "OFF: the battle's own Pokemon")

-- ------- ON

set("trainer_teams", "on")
local function check(class, id, gymType)
  local new, vanilla, m = battle(class, id)
  T.eq(#new, #vanilla, class .. ": the same team size")
  for i, mon in ipairs(new) do
    T.eq(mon.level, vanilla[i].level, class .. ": the game's level")
    T.check(data.pokemon[mon.species] ~= nil, class .. ": " .. mon.species .. " is registered")
    T.eq(mon.name, data.pokemon[mon.species].name, class .. ": the new species' own name")
    if gymType then T.check(types(mon.species)[gymType], class .. ": " .. mon.species .. " is a " .. gymType .. " type") end
    if m.party[i].item then T.eq(mon.item, m.party[i].item, class .. ": its own held item kept") end
  end
  return new, vanilla
end
local falkner = check("FALKNER", "FALKNER1", "FLYING")
check("MORTY", "MORTY1", "GHOST")
-- Karen: five families, and Crystal's 251 have four Dark lines at her levels
-- (Pupitar is no Dark type yet): one may fall back to a shared type
local karen = check("KAREN", "KAREN1")
local dark = 0
for _, mon in ipairs(karen) do if types(mon.species).DARK then dark = dark + 1 end end
T.check(dark >= 4, "Karen's team is Dark types where Crystal has them (" .. dark .. " of " .. #karen .. ")")
check("CLAIR", "CLAIR1", "DRAGON")
local changed = 0
for i, mon in ipairs(falkner) do
  if mon.species ~= member("FALKNER", "FALKNER1").party[i].species then changed = changed + 1 end
end
T.check(changed > 0, "Falkner fields new Pokemon (" .. falkner[1].species .. ", " .. falkner[2].species .. ")")

-- the rival across fights
local familyOf, consistent, seen = {}, true, 0
for _, class in ipairs({ "RIVAL1", "RIVAL2" }) do
  for _, m in ipairs(data.gen2Trainers.classes[class].trainers) do
    local new, vanilla = check(class, m.id)
    for i, mon in ipairs(new) do
      local from = api.profileOf(vanilla[i].species).family
      local to = api.profileOf(mon.species).family
      if familyOf[from] and familyOf[from] ~= to then consistent = false end
      familyOf[from] = to
      seen = seen + 1
    end
  end
end
T.check(consistent, "the rival's lines are the same new families in every fight (" .. seen .. " Pokemon)")

-- left alone: the Battle Tower and link battles
local tower = Trainers.party(data, { roster = member("FALKNER", "FALKNER1").party })
T.check(Runtime.call("trainer.party", function(_, _, p) return p end, "FALKNER", 1, tower) == tower,
        "the Battle Tower's call (member id 1) is left alone")
T.check(Runtime.call("trainer.party", function(_, _, p) return p end, nil, 1, tower) == tower,
        "a link battle (no class) is left alone")

-- ------- ON + ITEMS

set("trainer_teams", "items")
local items, bossItems = 0, 0
for class, record in pairs(data.gen2Trainers.classes) do
  for _, m in ipairs(record.trainers or {}) do
    local new = battle(class, m.id)
    for i, mon in ipairs(new) do
      if mon.item and not (m.party[i] and m.party[i].item) then
        items = items + 1
        local it = data.items[mon.item]
        T.check(it and it.heldEffect and it.heldEffect ~= "HELD_NONE",
                class .. ": " .. tostring(mon.item) .. " exists and works")
        if class == "FALKNER" or class == "KAREN" then bossItems = bossItems + 1 end
      end
    end
  end
end
T.check(items > 50, "trainers hold items (" .. items .. ")")
T.check(bossItems >= 6, "bosses' Pokemon hold items (" .. bossItems .. ")")
local itemTeam = battle("FALKNER", "FALKNER1")
T.check(itemTeam[1].species == falkner[1].species, "ON + ITEMS keeps the same species")

-- ------- the Battle Tower: a one-to-one map over its roster

local BattleTower = require("src.core.gen2.BattleTower")
local function lcg(seed)
  local s = seed
  return function(n)
    s = (s * 1103515245 + 12345) % 2147483648
    return (s % n) + 1
  end
end
-- the row positions each draw picks, for ten opponents in a row per level group
local function draws()
  local out, species = {}, {}
  for group = 1, 10 do
    local save, random = {}, lcg(group)
    for _ = 1, 10 do
      local opp = BattleTower.drawOpponent(data, save, random, group)
      local rows = BattleTower.roster(data).groups[opp.group]
      for _, r in ipairs(opp.rows) do
        for i, row in ipairs(rows) do
          if row == r then out[#out + 1] = opp.group .. ":" .. i break end
        end
        species[#species + 1] = r
      end
    end
  end
  return table.concat(out, ","), species
end

set("trainer_teams", "off")
local own = BattleTower.roster(data)
T.check(own == data.gen2Trainers.battleTower, "OFF: the tower's own roster")
local offDraws = draws()
set("trainer_teams", "on")
local tower = BattleTower.roster(data)
T.check(tower ~= own and BattleTower.roster(data) == tower, "ON: a remapped copy, kept between draws")
local onDraws, drawn = draws()
T.eq(onDraws, offDraws, "the tower draws the same rows ON as OFF")
local mapped, changedRows, bad = {}, 0, {}
for g, rows in pairs(own.groups) do
  for i, row in ipairs(rows) do
    local new = tower.groups[g][i]
    local prior = mapped[row.species]
    if prior and prior ~= new.species then bad[#bad + 1] = "map:" .. row.species end
    mapped[row.species] = new.species
    T.eq(new.item, row.item, "a set keeps its item")
    T.eq(new.level, row.level, "a set keeps its level")
    if new.species ~= row.species then
      changedRows = changedRows + 1
      if new.stats or new.hp or new.maxHp or new.pp then bad[#bad + 1] = "stats:" .. new.species end
      if not (type(new.moves) == "table" and #new.moves > 0) then bad[#bad + 1] = "moves:" .. new.species end
      if new.dvs ~= row.dvs then bad[#bad + 1] = "dvs:" .. new.species end
      local profile = api.profileOf(new.species)
      if profile and profile.special then bad[#bad + 1] = "special:" .. new.species end
    end
  end
end
local targets = {}
for from, to in pairs(mapped) do
  if targets[to] then bad[#bad + 1] = "twice:" .. to end
  targets[to] = from
end
T.eq(table.concat(bad, " "), "", "one species per species, moves built, stats cleared, no specials")
T.check(changedRows > 100, "the tower fields new Pokemon (" .. changedRows .. " sets)")
local apiMap = api.facilitySpecies("crystal_battle_tower")
local agree = apiMap ~= nil
for from, to in pairs(mapped) do if apiMap and apiMap[from] ~= to then agree = false end end
T.check(agree, "facilitySpecies answers the tower's map")
T.eq(api.trainerIdentity("RIVAL1", data.gen2Trainers.classes.RIVAL1.trainers[1].id,
  Trainers.party(data, { roster = data.gen2Trainers.classes.RIVAL1.trainers[1].party })), "rival",
  "trainerIdentity: the rival is one trainer")
local party = BattleTower.battleParty(data, { drawn[1], drawn[2], drawn[3] })
T.eq(#party, 3, "a remapped team builds")
for _, mon in ipairs(party) do
  T.eq(mon.name, data.pokemon[mon.species].name, "built as " .. mon.species)
  T.check(mon.hp == mon.maxHp and mon.maxHp > 0, mon.species .. " has its own stats")
end
set("trainer_teams", "items")
T.check(BattleTower.roster(data).groups[1][1].species == tower.groups[1][1].species,
        "ON + ITEMS: the same tower species")

set("trainer_teams", "off")
T.check(BattleTower.roster(data) == own, "back OFF: the tower's own roster")
T.eq(api.facilitySpecies("crystal_battle_tower"), nil, "OFF: no facility map")
T.eq(Runtime.wantsHook("trainer.party"), false, "back OFF: the wrapper is gone")

run.release()
T.finish("modern_spawns trainers (Crystal)")
