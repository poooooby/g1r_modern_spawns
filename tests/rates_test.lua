-- Standalone: luajit mods/modern_spawns/tests/rates_test.lua (from the gen1recomp root).
-- src/rates.lua, the odds behind exports.encounters and the WoobNav (pure):
--   * a section's chances add up to 100, from each slot's own odds;
--   * a COMPLETE pool splits its slot evenly, or by TIME OF DAY weights;
--   * a pool nobody in which may come out leaves the slot to its own species;
--   * a look counts as its base; a slot without odds is never rolled;
--   * Gen 2 grass blocks read their own pools by the slot's index.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Rates = H.module("src/rates.lua")

local function byId(list)
  local out = {}
  for _, m in ipairs(list) do out[m.id] = m end
  return out
end
local function sum(list)
  local s = 0
  for _, m in ipairs(list) do s = s + m.chance end
  return s
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- ------- the cart's odds, slot by slot (Gen 1's /256 ladder)

local ladder = { 51, 51, 39, 25, 25, 25, 13, 13, 11, 3 }
local slots = {}
for i = 1, 10 do slots[i] = { species = i <= 2 and "PIDGEY" or "RATTATA", level = i + 1 } end
local out = Rates.section({ slots = slots, weights = ladder })
T.check(near(sum(out), 100), "a table's chances add up to 100")
T.eq(#out, 2, "one row per species")
T.check(near(byId(out).PIDGEY.chance, 102 * 100 / 256), "a species' chance is its slots' share of the odds")
T.eq(out[1].id, "RATTATA", "most likely first")
T.eq(byId(out).PIDGEY.minLevel, 2, "its lowest level")
T.eq(byId(out).PIDGEY.maxLevel, 3, "its highest level")
T.eq(byId(out).RATTATA.pooled, false, "a slot's own species is not pooled")

-- a Gen 3 slot's own level range
local g3 = Rates.section({ slots = { { species = "A", level = 2, maxLevel = 4 }, { species = "A", level = 5, maxLevel = 5 } },
                           weights = { 60, 40 } })
T.eq(g3[1].minLevel, 2, "Gen 3: the lowest of the slots' ranges")
T.eq(g3[1].maxLevel, 5, "Gen 3: the highest of the slots' ranges")

-- ------- COMPLETE: the pool splits its slot

local pools = { [1] = { "PIDGEY", "SPEAROW", "HOOTHOOT", "TAILLOW" }, [2] = { "PIDGEY", "SPEAROW", "HOOTHOOT", "TAILLOW" } }
local even = Rates.section({ slots = slots, weights = ladder, pools = pools })
T.check(near(sum(even), 100), "pools still add up to 100")
local e = byId(even)
T.check(near(e.SPEAROW.chance, 102 * 100 / 256 / 4), "a pool member shares its slot evenly")
T.eq(e.SPEAROW.pooled, true, "...and is marked pooled")
T.eq(e.PIDGEY.pooled, false, "the slot's own species is not pooled")

-- TIME OF DAY: weighted the way the encounter hook draws (3 at its time, 1 at the other, 0 under STRICT)
local W = { PIDGEY = 3, SPEAROW = 3, HOOTHOOT = 1, TAILLOW = 0 }
local tod = byId(Rates.section({ slots = slots, weights = ladder, pools = pools,
                                 weightOf = function(id) return W[id] end }))
T.check(near(tod.HOOTHOOT.chance, 102 * 100 / 256 / 7), "an off-hours member weighs 1 of 7")
T.check(near(tod.PIDGEY.chance, 102 * 100 / 256 * 3 / 7), "an in-hours member weighs 3 of 7")
T.eq(tod.TAILLOW, nil, "a member that may not come out now is not listed")

-- nobody may come out: the slot keeps its own species
local none = byId(Rates.section({ slots = slots, weights = ladder, pools = pools, weightOf = function() return 0 end }))
T.check(near(none.PIDGEY.chance, 102 * 100 / 256), "a pool with no member out now leaves the slot to its own species")
T.eq(none.SPEAROW, nil, "...and lists no member")

-- looks count as their base
local looks = byId(Rates.section({ slots = { { species = "ROTOM_WASH", level = 5 }, { species = "ROTOM", level = 6 } },
                                   weights = { 1, 1 }, baseOf = function(id) return id:match("^ROTOM_") and "ROTOM" or nil end }))
T.check(looks.ROTOM ~= nil and near(looks.ROTOM.chance, 100) and looks.ROTOM_WASH == nil, "a look counts as its base")

-- a slot past the ladder is never rolled
local zero = Rates.section({ slots = { { species = "A", level = 1 }, { species = "B", level = 1 } }, weights = { 10, 0 } })
T.check(#zero == 1 and zero[1].id == "A", "a slot without odds is not listed")
T.eq(#Rates.section({ slots = {}, weights = {} }), 0, "an empty table lists nothing")

-- ------- Gen 2 grass: blocks of one flat table, each with its own pools

local flat, w2, times = {}, {}, {}
local G2 = { 30, 30, 20, 10, 5, 4, 1 }
for b, time in ipairs({ "MORN", "DAY", "NITE" }) do
  for i = 1, 7 do
    flat[#flat + 1] = { species = time == "NITE" and "HOOTHOOT" or "PIDGEY", level = 2 }
    w2[#w2 + 1], times[#times + 1] = G2[i], time
  end
end
local nite = {}
for i, t in ipairs(times) do if t == "NITE" then nite[#nite + 1] = i end end
local p2 = { [15] = { "HOOTHOOT", "NOCTOWL" } }
local n = byId(Rates.section({ slots = flat, weights = w2, indices = nite, pools = p2 }))
T.check(near(n.HOOTHOOT.chance, 100 - 15), "NITE: its own block only, slot 15 split with its pool")
T.check(near(n.NOCTOWL.chance, 15), "the NITE block's pool reads slot 15's")
T.eq(n.PIDGEY, nil, "no MORN / DAY species at night")

-- ------- the 5% floor: TIME OF DAY's lean never takes anyone under it

local function frac(ws)
  local s, out = 0, {}
  for _, w in ipairs(ws) do s = s + w end
  for i, w in ipairs(ws) do out[i] = w / s end
  return out
end
local same = { 3, 1 }
T.eq(Rates.floored(same, 0.25), same, "nobody under the floor: the weights as they were")
local f = frac(Rates.floored({ 3, 3, 1 }, 0.25))
T.check(near(f[3], 0.25), "the lean's 1 of 7 raised to the floor")
T.check(near(f[1], 0.375) and near(f[2], 0.375), "...the rest share what is left by their weights")
f = frac(Rates.floored({ 3, 3, 1, 1 }, 0.25))
T.check(near(f[1], 0.25) and near(f[4], 0.25), "a full pool: all equal")
f = frac(Rates.floored({ 3, 0, 1 }, 0.5))
T.check(f[2] == 0 and near(f[1], 0.5) and near(f[3], 0.5), "a member that may not come out stays out")
f = frac(Rates.floored({ 3, 3 }, 1, { 2 }))
T.check(near(f[1], 1) and f[2] == 0, "room for one: the other time's pick steps aside")
-- a section: a 20% slot pooled four ways with a 3:3:1:1 lean keeps each at 5%
local one = { { species = "A", level = 5 }, { species = "B", level = 5 } }
local leaned = byId(Rates.section({ slots = one, weights = { 20, 80 }, pools = { [1] = { "A", "C", "D", "E" } },
                                    weightOf = function(id) return (id == "A" or id == "C") and 3 or 1 end,
                                    floor = 5 }))
T.check(near(leaned.E.chance, 5) and near(leaned.A.chance, 5), "a section's pool held at 5% each under the lean")
local free = byId(Rates.section({ slots = one, weights = { 20, 80 }, pools = { [1] = { "A", "C", "D", "E" } },
                                  weightOf = function(id) return (id == "A" or id == "C") and 3 or 1 end }))
T.check(near(free.E.chance, 2.5), "...without the floor the lean gives 2.5%")

-- ------- how a chance reads

T.eq(Rates.text(35.2), "35%", "a chance in whole percent")
T.eq(Rates.text(0.4), "<1%", "under one percent")
T.eq(Rates.text(100), "100%", "a sure thing")
T.eq(Rates.text(0), "0%", "nothing")

T.finish("modern_spawns rates")
