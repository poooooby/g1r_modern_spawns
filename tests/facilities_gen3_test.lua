-- Standalone: luajit mods/modern_spawns/tests/facilities_gen3_test.lua (from the
-- gen1recomp root; needs Emerald, Ruby and FireRed imported and
-- mods/national_dex_gen3 installed). TRAINER TEAMS in the Gen 3 facilities:
--   * OFF: every pack is the engine's own table;
--   * ON: the Frontier's mons / brains / tents follow ONE map (one species per
--     species, no legendaries), each changed set keeps its item, nature and
--     EVs and gets a built moveset; Unown stays (the Factory skips it);
--   * the facilities' own draws pick the same sets ON as OFF (a trainer's
--     party, the Factory's rentals), only with the new species;
--   * Pyramid / Pike wild Pokemon, Trainer Hill, Ruby's Battle Tower and
--     FireRed's Trainer Tower are remapped too.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local function load(game)
  H.mountGen3(game)
  local data = H.gen3Data(game)
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, game .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "FRONTIER" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  local set, game_ = H.manager(loader)
  game_.data = data
  local idOfSlot = {}
  for id in loader.content.pokemon:each() do
    local rec = loader.content.pokemon:get(id)
    if type(rec) == "table" and rec.index then idOfSlot[rec.index] = idOfSlot[rec.index] or id end
  end
  local g = { run = run, set = set, api = loader.exports.modern_spawns, loader = loader }
  function g.special(slot)
    local p = g.api.profileOf(idOfSlot[slot])
    return p and p.special
  end
  function g.known(slot) return idOfSlot[slot] ~= nil end
  return g
end

-- every row of a list (0- or 1-based), old and new side by side
local function pairsOf(old, new, out)
  out = out or {}
  for k, row in pairs(old or {}) do
    if type(row) == "table" then out[#out + 1] = { old = row, new = new[k] } end
  end
  return out
end

-- one species per species; same item / nature / EVs; moves for the changed
local function checkSets(g, label, rowsList, itemKey)
  local map, bad, changed = {}, {}, 0
  for _, p in ipairs(rowsList) do
    local o, n = p.old, p.new
    if map[o.species] and map[o.species] ~= n.species then bad[#bad + 1] = "map:" .. o.species end
    map[o.species] = n.species
    if n[itemKey] ~= o[itemKey] then bad[#bad + 1] = "item:" .. o.species end
    if n.nature ~= o.nature or n.evSpread ~= o.evSpread or n.evs ~= o.evs then bad[#bad + 1] = "nature/evs:" .. o.species end
    if n.species ~= o.species then
      changed = changed + 1
      if not g.known(n.species) then bad[#bad + 1] = "unknown:" .. n.species end
      if g.special(n.species) then bad[#bad + 1] = "special:" .. n.species end
      if not (type(n.moves) == "table" and n.moves ~= o.moves and #n.moves >= 1 and #n.moves <= 4) then
        bad[#bad + 1] = "moves:" .. n.species
      end
    end
  end
  local seen = {}
  for from, to in pairs(map) do
    if seen[to] then bad[#bad + 1] = "twice:" .. to end
    seen[to] = from
  end
  T.eq(table.concat(bad, " "), "", label .. ": one species per species, sets kept, moves built")
  return map, changed
end

-- ======================================================== Emerald

local em = load("emerald")
local D = require("src.core.game3.rse.frontier.trainers")
local Rng = require("src.core.game3.rng")
local own = D.__modernSpawnsOriginal_pack
T.check(type(own) == "function", "the Frontier's packs are wrapped")
T.check(D.pack("mons") == own("mons"), "OFF: the Frontier's own mons")

-- a trainer's party under a pinned RNG
local function trainerParties()
  local out = {}
  for _, tid in ipairs({ 0, 20, 60, 99, 150, 199, 250, 299 }) do
    Rng.SeedRng(4660 + tid)
    local sess = { frontier = { lvlMode = 0 }, party = {} }
    local party = D.fillTrainerParty(sess, tid, 0, 3, {}, { facility = 0 })
    for i, mon in ipairs(party) do
      out[#out + 1] = { tid = tid, i = i, species = tonumber(mon.species), personality = mon.personality,
                        item = mon.heldItem or 0, moves = mon.moves }
    end
  end
  return out
end
local offParties = trainerParties()

em.set("trainer_teams", "on")
local mons, brains, tents = D.pack("mons"), D.pack("brains"), D.pack("tents")
T.check(mons ~= own("mons") and D.pack("mons") == mons, "ON: a remapped copy, kept between reads")
T.check(D.pack("trainers") == own("trainers"), "the other packs are the engine's own")
local rowsList = pairsOf(own("mons").mons, mons.mons)
for facility, symbols in pairs(own("brains").mons) do
  for symbol, list in pairs(symbols) do pairsOf(list, brains.mons[facility][symbol], rowsList) end
end
local brainStart = #rowsList
for name, tent in pairs(own("tents")) do
  if type(tent) == "table" and tent.mons then pairsOf(tent.mons, tents[name].mons, rowsList) end
end
local map, changed = checkSets(em, "Frontier", rowsList, "itemTableId")
T.check(changed > 800, "the Frontier fields new Pokemon (" .. changed .. " sets)")
T.eq(map[201], 201, "Unown stays Unown (the Factory skips it)")
local apiMap = em.api.facilitySpecies("emerald_frontier")
T.check(type(apiMap) == "table" and next(apiMap) ~= nil, "facilitySpecies answers the Frontier's map")
T.eq(em.api.facilitySpecies("frlg_trainer_tower"), nil, "no Trainer Tower on Emerald")
local brainSpecial = {}
for _, p in ipairs(rowsList) do
  if p.new.heldItem and em.special(p.new.species) then brainSpecial[#brainSpecial + 1] = p.new.species end
end
T.eq(#brainSpecial, 0, "the Frontier Brains field no legendaries")
-- brains keep their own held item field
for i = 1, brainStart do
  local p = rowsList[i]
  if p.old.heldItem then T.eq(p.new.heldItem, p.old.heldItem, "a Brain's set keeps its item") break end
end

local onParties = trainerParties()
local same, mapped = #onParties == #offParties, true
for i, a in ipairs(offParties) do
  local b = onParties[i]
  if not b or a.personality ~= b.personality or a.item ~= b.item then same = false end
  if b and map[a.species] ~= b.species then mapped = false end
end
T.check(same and #offParties >= 24, "a trainer draws the same sets ON as OFF (" .. #offParties .. " Pokemon)")
T.check(mapped, "... each one its set's new species")

-- the Factory's first six rentals
local Factory = require("src.core.game3.rse.frontier.factory")
local function rentals()
  Rng.SeedRng(77)
  local sess = { frontier = { lvlMode = 0, factoryWinStreaks = {}, rentalMons = {} }, vars = {} }
  local ok, err = pcall(Factory.generateInitialRentalMons, sess)
  if not ok then return nil, err end
  local out = {}
  for i = 1, 6 do out[i] = sess.frontier.rentalMons[i].monId end
  return table.concat(out, ",")
end
local onRentals, rentalErr = rentals()
em.set("trainer_teams", "off")
T.check(D.pack("mons") == own("mons"), "back OFF: the Frontier's own mons")
local offRentals = rentals()
T.check(onRentals ~= nil, "the Factory draws rentals (" .. tostring(rentalErr) .. ")")
T.eq(onRentals, offRentals, "the Factory offers the same rentals ON as OFF")
em.set("trainer_teams", "on")

-- Pyramid and Pike wild Pokemon
local Pyramid = require("src.core.game3.rse.frontier.pyramid")
local Pike = require("src.core.game3.rse.frontier.pike")
local Pokemon = require("src.core.game3.pokemon")
local pyrRow = Pyramid.manifest().wildMons50[1][1]
local wild = Pyramid.__modernSpawnsTrainers_generateWildMon({
  species = pyrRow.species, level = 50, personality = 12345, moves = pyrRow.moves, ability = 0, abilityNum = 0 })
T.check(wild and wild.species == map[pyrRow.species] and wild.species ~= pyrRow.species,
        "a Pyramid Pokemon follows the Frontier's map")
if wild then
  local pair = Pokemon.abilities(wild.species)
  T.check(wild.ability == pair[wild.abilityNum + 1], "... with an ability of its new species")
  T.check(#wild.moves >= 1 and #wild.moves <= 4, "... and up to four moves (" .. #wild.moves .. ": " .. table.concat(wild.moves, ",") .. " from " .. table.concat(pyrRow.moves or {}, ",") .. ")")
end
local pikeHeader = Pike.manifest().wildMons[1][1]
local pikeRow = pikeHeader[1]
local pikeWild = Pike.__modernSpawnsTrainers_tryGenerateWildMon({
  species = pikeRow.species, level = 45, abilityNum = 1, moves = pikeRow.moves })
T.check(pikeWild and pikeWild.species == map[pikeRow.species], "a Pike Pokemon follows the Frontier's map")

-- Trainer Hill
local Hill = require("src.core.game3.rse.trainer_hill")
local hillTrainer = Hill.manifest().challenges[1].floors[1].trainers[1]
local newHill = Hill.__modernSpawnsTrainers_trainer(hillTrainer)
T.check(newHill and newHill ~= hillTrainer and newHill.name == hillTrainer.name, "a Trainer Hill trainer is a remapped copy")
local hillChanged = 0
for i, mon in ipairs(newHill and newHill.mons or {}) do
  if mon.species ~= hillTrainer.mons[i].species then
    hillChanged = hillChanged + 1
    T.eq(mon.nickname, "", "a remapped Hill Pokemon goes by its species' name")
    T.eq(mon.heldItem, hillTrainer.mons[i].heldItem, "... and keeps its item")
  end
end
T.check(hillChanged > 0, "Trainer Hill fields new Pokemon (" .. hillChanged .. ")")
em.set("trainer_teams", "off")
em.run.release()

-- ======================================================== Ruby: Battle Tower

local ru = load("ruby")
local RsTower = require("src.core.game3.rse.battle_tower_rs")
RsTower.reset()
local rsOwn = RsTower.__modernSpawnsOriginal_pack()
T.check(RsTower.pack() == rsOwn, "OFF: Ruby's own Battle Tower pack")
ru.set("trainer_teams", "on")
local rsPack = RsTower.pack()
T.check(rsPack ~= rsOwn and rsPack.trainers == rsOwn.trainers, "ON: a remapped copy, the trainers the tower's own")
local rsRows = pairsOf(rsOwn.mons50, rsPack.mons50)
pairsOf(rsOwn.mons100, rsPack.mons100, rsRows)
local _, rsChanged = checkSets(ru, "Ruby's Battle Tower", rsRows, "heldItem")
T.check(rsChanged > 100, "Ruby's Battle Tower fields new Pokemon (" .. rsChanged .. " sets)")
for _, p in ipairs(rsRows) do
  if p.new.teamFlags ~= p.old.teamFlags then T.check(false, "a set keeps its team flags") break end
end
ru.set("trainer_teams", "off")
T.check(RsTower.pack() == rsOwn, "back OFF: Ruby's own pack")
ru.run.release()

-- ======================================================== FireRed: Trainer Tower

local fr = load("firered")
local Tower = require("src.core.game3.trainer_tower")
Tower.resetPack()
local pack = Tower.pack()
T.check(type(pack) == "table" and pack.floors ~= nil, "FireRed's Trainer Tower pack loads")
local floor
for _, floors in pairs(pack and pack.floors or {}) do
  floor = floors[1]
  if floor then break end
end
local session = { party = { { species = 1, level = 40 } } }
local offTeam = Tower.buildEnemyParty(session, floor, 0)
fr.set("trainer_teams", "on")
local onTeam = Tower.buildEnemyParty(session, floor, 0)
T.eq(#onTeam, #offTeam, "the Trainer Tower team keeps its size")
local towerChanged = 0
for i, mon in ipairs(onTeam) do
  T.eq(mon.level, offTeam[i].level, "the Trainer Tower's level")
  T.eq(mon.heldItem, offTeam[i].heldItem, "the Trainer Tower set keeps its item")
  if mon.species ~= offTeam[i].species then
    towerChanged = towerChanged + 1
    T.check(mon.nickname == nil, "a remapped Trainer Tower Pokemon goes by its species' name")
    T.check(not fr.special(mon.species), "no legendary in the Trainer Tower")
    local pair = Pokemon.abilities(mon.species)
    T.check(mon.abilityNum == 0 or (pair[2] or 0) ~= 0, "an ability slot its new species has")
  end
end
T.check(towerChanged > 0, "the Trainer Tower fields new Pokemon (" .. towerChanged .. ")")
fr.set("trainer_teams", "off")
local backTeam = Tower.buildEnemyParty(session, floor, 0)
T.eq(backTeam[1].species, offTeam[1].species, "back OFF: the tower's own Pokemon")
fr.run.release()

T.finish("modern_spawns trainers (Gen 3 facilities)")
