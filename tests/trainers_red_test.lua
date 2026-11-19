-- Standalone: luajit mods/modern_spawns/tests/trainers_red_test.lua (from the
-- gen1recomp root; needs Red imported and the national_dex repo beside
-- gen1recomp, at ../national_dex).
-- TRAINER TEAMS on Red/Blue/Yellow:
--   * OFF: no trainer.party wrapper at all, the game's own party object;
--   * Brock's team is all Rock types, Misty's all Water;
--   * the rival's lines are the same new families in every fight;
--   * the shared party data is never changed; every species is registered and
--     under GENERATIONS; never a legendary;
--   * it works with MODERN SPAWNS OFF.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMods({ "../national_dex", "mods/modern_spawns" },
                           { data = Data, modOptions = { national_dex = { national_dex = "on" } } })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "KANTO" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local set = H.manager(loader)
local api = loader.exports.modern_spawns

local function party(class, index)
  local p = Data.trainers[class].parties[index]
  return Runtime.call("trainer.party", function(_, _, rows) return rows end, class, index, p), p
end

-- ------- OFF: nothing wrapped, the game's own object

T.eq(api.settings().trainerTeams, "off", "TRAINER TEAMS is off by default")
T.eq(Runtime.wantsHook("trainer.party"), false, "OFF: no trainer.party wrapper")
local out, own = party("OPP_BROCK", 1)
T.check(out == own, "OFF: Brock's own party object")

-- ------- ON

set("trainer_teams", "on")
T.eq(Runtime.wantsHook("trainer.party"), true, "ON: trainer.party is wrapped")
local snapshot = H.serialize(Data.trainers)
local function types(id)
  local p = api.profileOf(id)
  local s = {}
  for _, t in ipairs(p and p.types or {}) do s[(t:gsub("_TYPE$", ""))] = true end
  return s
end
local function check(class, index, gymType)
  local new, vanilla = party(class, index)
  T.eq(#new, #vanilla, class .. ": the same team size")
  for i, row in ipairs(new) do
    T.eq(row.level, vanilla[i].level, class .. ": the game's level")
    T.check(Data.pokemon[row.species] ~= nil, class .. ": " .. row.species .. " is registered")
    local p = api.profileOf(row.species)
    T.check(p and not p.special, class .. ": " .. row.species .. " is no legendary")
    if gymType then T.check(types(row.species)[gymType], class .. ": " .. row.species .. " is a " .. gymType .. " type") end
  end
  return new, vanilla
end
local brock = check("OPP_BROCK", 1, "ROCK")
check("OPP_MISTY", 1, "WATER")
check("OPP_LORELEI", 1, "ICE")
check("OPP_AGATHA", 1, "GHOST")
local changed = 0
for i, row in ipairs(brock) do
  if row.species ~= Data.trainers.OPP_BROCK.parties[1][i].species then changed = changed + 1 end
end
T.check(changed > 0, "Brock fields new Pokemon (" .. brock[1].species .. ", " .. brock[2].species .. ")")

-- the rival: each original family is one new family in every fight
local familyOf = {}
local consistent, seen = true, 0
local starters, badStarters = 0, {}
for _, class in ipairs({ "OPP_RIVAL1", "OPP_RIVAL2", "OPP_RIVAL3" }) do
  for index in ipairs(Data.trainers[class].parties) do
    local new, vanilla = check(class, index)
    for i, row in ipairs(new) do
      local from = api.profileOf(vanilla[i].species).family
      local to = api.profileOf(row.species).family
      if familyOf[from] and familyOf[from] ~= to then consistent = false end
      familyOf[from] = to
      seen = seen + 1
      local ok, why = H.rivalStarterOk(api.profileOf(vanilla[i].species), api.profileOf(row.species))
      if ok ~= nil then
        starters = starters + 1
        if not ok then badStarters[#badStarters + 1] = class .. "#" .. index .. ": " .. why end
      end
    end
  end
end
T.check(consistent, "the rival's lines are the same new families in every fight (" .. seen .. " Pokemon)")
T.check(starters >= 6, "the rival's starter in every fight (" .. starters .. ")")
T.eq(table.concat(badStarters, "; "), "", "the rival's starter loses to yours and evolves with the original")
T.eq(H.serialize(Data.trainers), snapshot, "the shared party data is never changed")

-- the same seed, the same team; GENERATIONS caps it
local again = party("OPP_BROCK", 1)
T.eq(H.serialize(again), H.serialize(brock), "the same seed gives the same team")
set("max_generation", "1")
for _, row in ipairs((party("OPP_GIOVANNI", 3))) do
  T.check((api.profileOf(row.species).generation or 9) <= 1, "GEN 1: " .. row.species .. " is Gen 1")
end
set("max_generation", "9")

-- independent of the wild tables
set("enabled", "off")
local wildOff = party("OPP_BROCK", 1)
T.eq(H.serialize(wildOff), H.serialize(brock), "MODERN SPAWNS OFF: trainer teams are unchanged")
set("enabled", "on")

-- ON + ITEMS on Red: no held items, the same teams
set("trainer_teams", "items")
T.eq(H.serialize((party("OPP_BROCK", 1))), H.serialize(brock), "ON + ITEMS on Red: the same teams, no items")

set("trainer_teams", "off")
T.eq(Runtime.wantsHook("trainer.party"), false, "back OFF: the wrapper is gone")
local off, own2 = party("OPP_BROCK", 1)
T.check(off == own2, "back OFF: Brock's own party object")

run.release()
T.finish("modern_spawns trainers (Red)")
