-- Standalone: luajit mods/modern_spawns/tests/trainers_gen3_test.lua (from the
-- gen1recomp root; needs Emerald and FireRed imported and mods/national_dex_gen3
-- installed). TRAINER TEAMS on the Gen 3 games' story trainers:
--   * OFF: no trainer.party wrapper, the battle's own party;
--   * Roxanne's team is all Rock types, Phoebe's all Ghost, Brock's all Rock;
--   * May / Brendan / Wally and FireRed's rival keep one family per line;
--   * rows carry the new species' numeric slot, at the game's level, with no
--     custom moves left behind; doubles keep their size;
--   * ON + ITEMS: items are numbers in both heldItem and item, and work;
--   * trainer ids 0 (Trainer Tower), nil (Frontier, link) and 1024 (secret
--     bases) are left alone.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")

local function load(game)
  H.mountGen3(game)
  local data = H.gen3Data(game)
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, game .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "HOENN" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  local set, game_ = H.manager(loader)
  game_.data = data
  local Trainers = require("src.core.game3.scripting.trainers")
  local G3 = require("src.mods.Gen3Compat")
  local idOfSlot = {}
  for id in loader.content.pokemon:each() do
    local rec = loader.content.pokemon:get(id)
    if type(rec) == "table" and rec.index and not (rec.form or rec.baseSpecies) then
      idOfSlot[rec.index] = idOfSlot[rec.index] or id
    end
  end
  local g = { run = run, loader = loader, set = set, api = loader.exports.modern_spawns, data = data }
  function g.find(className, name)
    local out = {}
    for id, t in pairs(Trainers.pack().trainers) do
      local cn = t.className or Trainers.pack().classNames[t.class]
      if cn == className and t.name == name then out[#out + 1] = id end
    end
    table.sort(out)
    return out
  end
  function g.battle(id)
    local foe = Trainers.foeFromId(id)
    local named = G3.partyNames(foe.party)
    return Runtime.call("trainer.party", function(_, _, p) return p end, foe.trainerClass, id, named), named
  end
  function g.speciesOf(row) return idOfSlot[tonumber(row.species) or -1] or row.species end
  function g.types(id)
    local rec = loader.content.pokemon:get(id)
    local s = {}
    for _, t in ipairs(type(rec) == "table" and rec.types or {}) do
      s[(tostring(t):gsub("_TYPE$", ""):gsub("^TYPE_", ""))] = true
    end
    return s
  end
  return g
end

local builtSets = 0
local function checkTyped(g, label, id, gymType)
  local new, vanilla = g.battle(id)
  T.eq(#new, #vanilla, label .. ": the same team size")
  local changed = 0
  for i, row in ipairs(new) do
    T.eq(row.level, vanilla[i].level, label .. ": the game's level")
    local sid = g.speciesOf(row)
    T.check(sid ~= nil and g.loader.content.pokemon:get(sid) ~= nil, label .. ": " .. tostring(sid) .. " is registered")
    if gymType then T.check(g.types(sid)[gymType], label .. ": " .. tostring(sid) .. " is a " .. gymType .. " type") end
    if row.species ~= vanilla[i].speciesId then
      changed = changed + 1
      T.eq(type(row.species), "number", label .. ": a numeric species slot")
      T.check(row.moveIds == nil, label .. ": no old move ids left behind")
      if type(vanilla[i].moves) == "table" and #vanilla[i].moves > 0 then
        T.check(type(row.moves) == "table" and #row.moves > 0 and row.moves ~= vanilla[i].moves,
                label .. ": custom moves become a built set for " .. tostring(sid))
        builtSets = builtSets + 1
      end
    end
  end
  return new, vanilla, changed
end

-- ======================================================== Emerald

local em = load("emerald")
local roxanne = em.find("LEADER", "ROXANNE")
T.check(#roxanne >= 1, "Emerald: Roxanne found (" .. #roxanne .. " fights)")
T.eq(Runtime.wantsHook("trainer.party"), false, "OFF: no trainer.party wrapper")
local out, own = em.battle(roxanne[1])
T.check(out == own, "OFF: the battle's own party")

em.set("trainer_teams", "on")
local _, _, changed = checkTyped(em, "Roxanne", roxanne[1], "ROCK")
T.check(changed > 0, "Roxanne fields new Pokemon")
for i = 2, #roxanne do checkTyped(em, "Roxanne rematch " .. i, roxanne[i], "ROCK") end
checkTyped(em, "Phoebe", em.find("ELITE FOUR", "PHOEBE")[1], "GHOST")
checkTyped(em, "Wallace", em.find("CHAMPION", "WALLACE")[1], "WATER")

-- May and Brendan: one family per line across every fight
for _, name in ipairs({ "MAY", "BRENDAN", "WALLY" }) do
  local familyOf, consistent, n = {}, true, 0
  local starters, badStarters = 0, {}
  for _, id in ipairs(em.find("POKéMON TRAINER", name)) do
    local new, vanilla = checkTyped(em, name, id)
    for i, row in ipairs(new) do
      local from = em.api.profileOf(em.speciesOf({ species = vanilla[i].speciesId }))
      local to = em.api.profileOf(em.speciesOf(row))
      if from and to then
        if familyOf[from.family] and familyOf[from.family] ~= to.family then consistent = false end
        familyOf[from.family] = to.family
        n = n + 1
        local ok, why = H.rivalStarterOk(from, to)
        if ok ~= nil then
          starters = starters + 1
          if not ok then badStarters[#badStarters + 1] = tostring(id) .. ": " .. why end
        end
      end
    end
  end
  T.check(consistent and n > 0, name .. " keeps one family per line across fights (" .. n .. " Pokemon)")
  if name ~= "WALLY" then
    T.check(starters >= 6, name .. "'s starter in every fight (" .. starters .. ")")
    T.eq(table.concat(badStarters, "; "), "", name .. "'s starter loses to yours and evolves with the original")
  end
end

T.check(builtSets > 0, "custom-move Pokemon get built sets (" .. builtSets .. ")")

-- left alone: Trainer Tower (0), Frontier / link (nil), secret bases (1024)
local named = em.battle(roxanne[1])
for _, id in ipairs({ 0, 1024 }) do
  T.check(Runtime.call("trainer.party", function(_, _, p) return p end, 0, id, named) == named,
          "trainer id " .. id .. " is left alone")
end
T.check(Runtime.call("trainer.party", function(_, _, p) return p end, 0, nil, named) == named,
        "no trainer id is left alone")

-- ON + ITEMS: numbers in both fields, and they work
em.set("trainer_teams", "items")
local HeldItems = require("src.core.game3.battle.held_items")
local items, wrong = 0, {}
for _, id in ipairs(roxanne) do
  local new, vanilla = em.battle(id)
  for i, row in ipairs(new) do
    if row.item and not vanilla[i].heldItem then
      items = items + 1
      if type(row.item) ~= "number" or row.heldItem ~= row.item then wrong[#wrong + 1] = "fields" end
      if (HeldItems.effectOf(row.item)) == 0 then wrong[#wrong + 1] = tostring(row.item) end
    end
  end
end
T.check(items >= #roxanne, "Roxanne's Pokemon hold items (" .. items .. ")")
T.eq(table.concat(wrong, " "), "", "every item is a number in heldItem and item, and does something")
em.set("trainer_teams", "off")
T.eq(Runtime.wantsHook("trainer.party"), false, "back OFF: the wrapper is gone")
em.run.release()

-- ======================================================== FireRed

local fr = load("firered")
fr.set("trainer_teams", "on")
checkTyped(fr, "Brock", fr.find("LEADER", "BROCK")[1], "ROCK")
checkTyped(fr, "Lorelei", fr.find("ELITE FOUR", "LORELEI")[1], "ICE")
local familyOf, consistent, n = {}, true, 0
local starters, badStarters = 0, {}
for _, cn in ipairs({ "RIVAL", "CHAMPION" }) do
  for _, id in ipairs(fr.find(cn, "TERRY")) do
    local new, vanilla = checkTyped(fr, "rival " .. cn, id)
    for i, row in ipairs(new) do
      local from = fr.api.profileOf(fr.speciesOf({ species = vanilla[i].speciesId }))
      local to = fr.api.profileOf(fr.speciesOf(row))
      if from and to then
        if familyOf[from.family] and familyOf[from.family] ~= to.family then consistent = false end
        familyOf[from.family] = to.family
        n = n + 1
        local ok, why = H.rivalStarterOk(from, to)
        if ok ~= nil then
          starters = starters + 1
          if not ok then badStarters[#badStarters + 1] = cn .. " " .. id .. ": " .. why end
        end
      end
    end
  end
end
T.check(consistent and n > 20, "FireRed's rival keeps one family per line, champion included (" .. n .. " Pokemon)")
T.check(starters >= 6, "FireRed's rival's starter in every fight (" .. starters .. ")")
T.eq(table.concat(badStarters, "; "), "", "FireRed's rival's starter loses to yours and evolves with the original")
fr.run.release()

T.finish("modern_spawns trainers (Gen 3)")
