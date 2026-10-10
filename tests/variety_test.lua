-- Standalone: luajit mods/modern_spawns/tests/variety_test.lua (from the
-- gen1recomp root; needs Emerald imported under emerald/ and
-- mods/national_dex_gen3).
--
-- The generator used to draw each role from its best 8 scorers, and most
-- modern species have no observed wild level as low as an early route's, so
-- an early route produced the same handful of species no matter the seed
-- (Emerald's Route 101: 8 distinct species over 200 seeds, Scatterbug in 16%
-- of slots). These checks hold the variety fix: first-stage low-BST species
-- count as plausible on low slots (SpawnConfig.plausible_basic), a
-- generation with no observed wild data is not taxed for being estimated, and
-- the draw is a softmax within a score window (SpawnConfig.selection).
-- Thresholds sit well under what it measures (57 / 81 / 14%) so a tuning
-- change has room, and well over the old behaviour (8 / 22 / 0%).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local data = H.gen3Data("emerald")
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" },
                           { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local set, game = H.manager(loader)
game.data = data
local ms = loader.exports.modern_spawns
local MAP = "EM_ROUTE101"

local function genOf(id)
  local p = ms.profileOf(id)
  return p and p.generation or 0
end

-- every slot drawn across n tables for the map, as { counts, total, special }
local function sample(mode, n)
  set("spawn_mode", mode)
  local counts, total = {}, 0
  for i = 1, n do
    if mode == "seeded" then
      loader.modSave.modern_spawns = { seed = "V" .. i }
      ms.invalidate()
    end
    local t = ms.drawFor(MAP, "land")
    for _, slot in ipairs(t and t.slots or {}) do
      counts[slot.species] = (counts[slot.species] or 0) + 1
      total = total + 1
    end
  end
  return counts, total
end

local function summarize(counts, total)
  local distinct, topShare, topId = 0, 0, nil
  for id, c in pairs(counts) do
    distinct = distinct + 1
    if c / total > topShare then topShare, topId = c / total, id end
  end
  return distinct, topShare, topId
end

-- ------- SEEDED: many seeds, many different rosters

local counts, total = sample("seeded", 200)
local distinct, topShare, topId = summarize(counts, total)
T.check(distinct >= 30, "SEEDED over 200 seeds: at least 30 distinct species (" .. distinct .. ")")
T.check(topShare <= 0.12, "no species dominates SEEDED (" .. tostring(topId) .. " "
  .. math.floor(topShare * 100 + 0.5) .. "%)")
T.check((counts.SCATTERBUG or 0) / total <= 0.10, "Scatterbug is not the answer for Route 101 (any more)")

local gens = {}
for id, c in pairs(counts) do gens[genOf(id)] = (gens[genOf(id)] or 0) + c end
T.check((gens[9] or 0) / total >= 0.05, "Gen 9 is not starved by being on estimated profiles ("
  .. math.floor((gens[9] or 0) * 100 / total + 0.5) .. "%)")
local over = 0
for g = 1, 9 do if (gens[g] or 0) / total > 0.30 then over = over + 1 end end
T.eq(over, 0, "no single generation takes more than 30% of the slots")

-- ------- RANDOM: wider still

local rcounts, rtotal = sample("random", 200)
local rdistinct = summarize(rcounts, rtotal)
T.check(rdistinct >= 40, "RANDOM over 200 draws: at least 40 distinct species (" .. rdistinct .. ")")

-- ------- the quality rails still hold

set("max_generation", "3")
local capped = sample("seeded", 60)
local overCap = 0
for id in pairs(capped) do if genOf(id) > 3 then overCap = overCap + 1 end end
T.eq(overCap, 0, "GEN 1-3 still keeps every species at or under #386")
set("max_generation", "9")

local special = 0
for id in pairs(counts) do
  local p = ms.profileOf(id)
  if p and p.special then special = special + 1 end
end
T.eq(special, 0, "no legendary or mythical ever enters the wild tables")

-- levels are the cart's own, only species change
local live = data.gen3Encounters[MAP].land.slots
local generated = ms.tableFor(MAP, "land")
local levelsKept = true
for i, slot in ipairs(generated.slots) do
  if slot.minLevel ~= live[i].minLevel or slot.maxLevel ~= live[i].maxLevel then levelsKept = false end
end
T.check(levelsKept, "slot levels are untouched")

run.release()
T.finish("modern_spawns variety (Emerald)")
