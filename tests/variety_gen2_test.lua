-- Standalone: luajit mods/modern_spawns/tests/variety_gen2_test.lua (from the
-- gen1recomp root; needs Crystal imported under crystal/ and mods/national_dex).
--
-- On Gold/Silver/Crystal `national_dex` can't register anything past #251
-- (its Gen 2 schema rejects those records), so the whole pool is Gen 1-2 and
-- Route 29's level 2-3 slots had about 6 candidates: Charmander and Sentret,
-- every time, whatever the mode. With plausible basics admitted on low slots
-- it measures 50 distinct species over 200 seeds; the thresholds sit under that.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")

local data = H.gen2Data("crystal")
local run = T.sdk.loadMods({ "mods/national_dex", "mods/modern_spawns" },
                           { data = data, generation = 2 })
local loader = run.loader
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local set, game = H.manager(loader)
game.writeOptions = nil
game.persistOptions = function() end
game.data = data
local ms = loader.exports.modern_spawns
T.check(ms.isActive(), "active on Crystal")

local function sample(mode, n)
  set("spawn_mode", mode)
  local counts, total = {}, 0
  for i = 1, n do
    if mode == "seeded" then
      loader.modSave.modern_spawns = { seed = "V" .. i }
      ms.invalidate()
    end
    local t = ms.drawFor("ROUTE_29", "grass")
    for _, slot in ipairs(t and t.slots.DAY or {}) do
      counts[slot.species] = (counts[slot.species] or 0) + 1
      total = total + 1
    end
  end
  return counts, total
end

-- Route 29's own daytime species: LIMITED (the classic mode) favours a
-- replacement that resembles what it replaces, so these win their slots back
-- now and then; the "no species dominates" bar is for newcomers, and the
-- originals get their own cap (see variety_test.lua). It is looser than
-- Emerald's 35%: only Gen 1-2 species exist here and few fit levels 2-3, so
-- the cart's own win back more often (measured 41% at 0.13.0's tuning)
local ORIGINAL = { PIDGEY = true, SENTRET = true, RATTATA = true, HOPPIP = true }

local counts, total = sample("seeded", 200)
local distinct, topShare, topId, originals = 0, 0, nil, 0
for id, c in pairs(counts) do
  distinct = distinct + 1
  if ORIGINAL[id] then originals = originals + c
  elseif c / total > topShare then topShare, topId = c / total, id end
end
T.check(distinct >= 15, "SEEDED over 200 seeds: at least 15 distinct species (" .. distinct .. ")")
T.check(topShare <= 0.20, "no newcomer dominates (" .. tostring(topId) .. " "
  .. math.floor(topShare * 100 + 0.5) .. "%)")
T.check(originals / total <= 0.50, "the route's own species hold at most 50% of LIMITED's slots ("
  .. math.floor(originals * 100 / total + 0.5) .. "%)")
T.check(not ((counts.CHARMANDER or 0) / total > 0.15 and (counts.SENTRET or 0) / total > 0.15
  and distinct <= 6), "not just Charmander and Sentret any more")

local rcounts = sample("random", 100)
local rdistinct = 0
for _ in pairs(rcounts) do rdistinct = rdistinct + 1 end
T.check(rdistinct >= 25, "RANDOM over 100 draws: at least 25 distinct species (" .. rdistinct .. ")")

-- the Gen 2 ceiling is still respected: nothing past #251 exists here
local beyond = 0
for id in pairs(counts) do
  local p = ms.profileOf(id)
  if p and p.generation and p.generation > 2 then beyond = beyond + 1 end
end
T.eq(beyond, 0, "only Gen 1-2 species, as the game has registered")

run.release()
T.finish("modern_spawns variety (Crystal)")
