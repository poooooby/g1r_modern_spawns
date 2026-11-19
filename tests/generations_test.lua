-- Standalone: luajit mods/modern_spawns/tests/generations_test.lua (from the
-- gen1recomp root; needs Emerald imported and mods/national_dex_gen3).
-- GENERATIONS = CUSTOM: any set of generations (Gen 3-8; Gen 1, 3, 6):
--   * a generation set's key is "N" for Gen 1-N (so no existing setting's
--     tables or teams drift) and the list otherwise;
--   * the GEN 1 .. GEN 9 rows show in the Mod Manager only under CUSTOM;
--   * CUSTOM with all nine ON is GEN 1-9, table for table;
--   * Gen 3-8 / Gen 1, 3, 6: wild tables and COMPLETE's pools hold only
--     those generations, and COMPLETE makes every one of their species
--     catchable or evolvable from one that is;
--   * every generation OFF, or only generations no species mod added: the
--     game's own tables;
--   * TRAINER TEAMS steps through a left-out middle stage (GEN 2 + 4:
--     Happiny -> Blissey), and items of a left-out generation are never held.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Config = H.module("src/config.lua")
local Rng = H.module("src/rng.lua")
local Trainers = H.module("src/trainers.lua")
local Items = H.module("src/trainer_items.lua")

local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

-- ------- the key: "N" for Gen 1-N, the list otherwise

T.eq(Config.genSet(set({ 1, 2, 3, 4, 5 })).key, "5", "Gen 1-5 keys as 5, as the old cap did")
T.eq(Config.genSet(set({ 1 })).key, "1", "Gen 1 keys as 1")
T.eq(Config.genSet(set({ 3, 4, 5, 6, 7, 8 })).key, "3,4,5,6,7,8", "Gen 3-8 keys as its list")
T.eq(Config.genSet(set({ 6, 1, 3 })).key, "1,3,6", "Gen 1, 3, 6 keys as its sorted list")
T.eq(Config.genSet(set({ 6, 1, 3 })).max, 6, "its highest generation")
T.eq(Config.genSet({}), nil, "no generation: nil")
T.eq(Rng.hash("S", 5), Rng.hash("S", Config.genSet(set({ 1, 2, 3, 4, 5 })).key),
     "a range hashes exactly as the number did")

-- ------- reading the option

local function fakeMod(options)
  return { options = { get = function(_, key) return options[key] end } }
end
local function listOf(s)
  local out = {}
  for g in pairs(s) do out[#out + 1] = g end
  table.sort(out)
  return table.concat(out, ",")
end
T.eq(listOf(Config.generations(fakeMod({ max_generation = "5" }))), "1,2,3,4,5", "GEN 1-5")
T.eq(listOf(Config.generations(fakeMod({}))), "1,2,3,4,5,6,7,8,9", "default GEN 1-9")
T.eq(listOf(Config.generations(fakeMod({ max_generation = "custom" }))), "1,2,3,4,5,6,7,8,9",
     "CUSTOM starts with every generation ON")
T.eq(listOf(Config.generations(fakeMod({ max_generation = "custom", gen_1 = true, gen_2 = false,
  gen_3 = "on", gen_4 = false, gen_5 = false, gen_6 = true, gen_7 = false, gen_8 = false, gen_9 = false }))),
  "1,3,6", "CUSTOM reads the toggles (a hand-edited \"on\" too)")
T.eq(Config.maxGeneration(fakeMod({ max_generation = "custom", gen_7 = false, gen_8 = false, gen_9 = false })),
     6, "maxGeneration: the highest picked")

-- ------- TRAINER TEAMS: a left-out middle stage is stepped through

local function poolOf(rows)
  local list, byId = {}, {}
  for _, r in ipairs(rows) do
    local c = { id = r[1], gen = r[2], parent = r[3], evolveLevel = r[4], types = set({ "NORMAL" }), bst = 400 }
    list[#list + 1], byId[c.id] = c, c
  end
  for _, c in ipairs(list) do
    local d, p = 1, c.parent
    while p do d = d + 1 p = byId[p] and byId[p].parent end
    c.stage = d
  end
  return { list = list, byId = byId }
end
local pool = poolOf({ { "HAPPINY", 4 }, { "CHANSEY", 1, "HAPPINY" }, { "BLISSEY", 2, "CHANSEY" },
                      { "ZUBAT", 1 }, { "GOLBAT", 1, "ZUBAT", 22 }, { "CROBAT", 2, "GOLBAT" } })
local cfg = Config.TrainerConfig
local branch = function() return 1 end
local ix24 = Trainers.index(pool, "2,4", set({ 2, 4 }))
T.eq(Trainers.stageFor(ix24, cfg, "HAPPINY", 10, 1, branch), "HAPPINY", "GEN 2 + 4: a low-level Happiny")
T.eq(Trainers.stageFor(ix24, cfg, "HAPPINY", 50, 1, branch), "BLISSEY",
     "GEN 2 + 4: Happiny grows into Blissey, past the Gen 1 Chansey")
T.eq(table.concat(ix24.next("HAPPINY"), ","), "BLISSEY", "next() steps through Chansey")
T.eq(Trainers.stageFor(ix24, cfg, "ZUBAT", 50, 1, branch), "CROBAT", "GEN 2 alone: Crobat (its root skipped)")
local ix9 = Trainers.index(pool, 9)
T.eq(table.concat(ix9.next("HAPPINY"), ","), "CHANSEY", "Gen 1-9: the ordinary next stage")
local ix1 = Trainers.index(pool, 1)
T.eq(#ix1.next("CHANSEY"), 0, "GEN 1: Chansey's line ends at Chansey, as before")

-- ------- items of a left-out generation are never held

local genOf = {}
for _, list in pairs(Items.TYPE_BOOST) do for _, e in ipairs(list) do genOf[e[1]] = e[2] end end
for t, name in pairs(Items.PLATE) do genOf[name] = t == "FAIRY" and 6 or 4 end
for _, b in ipairs(Items.BERRIES) do genOf[b.name] = b.gen end
for _, a in ipairs(Items.ACE) do genOf[a.name] = a.gen end
local everything = function() return true end
local fire = { types = set({ "FIRE" }), canEvolve = true,
               moves = { { type = "FIRE", power = 90 }, { type = "NORMAL", power = 70 } } }
local strong = { hp = 78, attack = 84, defense = 78, speed = 100, spAttack = 109, spDefense = 85 }
local g136 = set({ 1, 2, 3, 6 }) -- Gen 1, 3, 6 on Emerald: the cart's own Gen 1-3 too
local bad, n = {}, 0
local rng = Rng.new(7)
for slot = 1, 6 do
  for _, role in ipairs({ "ace", "boss", "basic" }) do
    for _, mon in ipairs({ fire, { types = set({ "POISON" }), canEvolve = false, moves = { { type = "POISON", power = 80 } } },
                           { types = set({ "FAIRY" }), canEvolve = false, moves = { { type = "FAIRY", power = 80 } } } }) do
      local item = Items.choose({ role = role, strong = true, slot = slot, mon = mon, stats = strong, maxGen = 6,
                                  gens = g136, available = everything, rng = rng })
      if item then
        n = n + 1
        if not genOf[item] or not g136[genOf[item]] then bad[#bad + 1] = item .. "(" .. tostring(genOf[item]) .. ")" end
      end
    end
  end
end
T.check(n > 20, "items handed out (" .. n .. ")")
T.eq(table.concat(bad, " "), "", "Gen 1, 3, 6: never a Gen 4 or 5 item (no Life Orb, Eviolite, plates)")
T.eq(Items.choose({ role = "boss", slot = 1, mon = fire, stats = strong, maxGen = 6, gens = g136,
                    available = everything, rng = rng }), "CHARCOAL", "no Gen 4 plate: the Charcoal")

-- ======================================================== Emerald

local data = H.gen3Data("emerald")
local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local loader = run.loader
loader.modSave.modern_spawns = { seed = "GENS" }
loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
local setOpt, game = H.manager(loader)
game.data = data
local ms = loader.exports.modern_spawns
T.check(ms.apiVersion >= 3, "apiVersion 3")

-- the Mod Manager: the toggles show only under CUSTOM
local ManagerState = require("src.mods.ManagerState")
local schema = H.schema()
local function rowIds()
  local state = setmetatable({ game = game, cursor = 1 }, { __index = ManagerState })
  local ids = {}
  for _, row in ipairs(state:buildOptionRows({ id = "modern_spawns" }, schema)) do
    if tostring(row.id):match("^gen_%d$") then ids[#ids + 1] = row.id end
  end
  return table.concat(ids, ",")
end
T.eq(rowIds(), "", "GEN 1-9: no GEN rows")
setOpt("max_generation", "custom")
T.eq(rowIds(), "gen_1,gen_2,gen_3,gen_4,gen_5,gen_6,gen_7,gen_8,gen_9", "CUSTOM: the nine GEN rows")

local maps = {}
for id in pairs(data.gen3Encounters) do
  if type(id) == "string" then maps[#maps + 1] = id end
end
table.sort(maps)
local lookOf = {}
for _, c in ipairs(ms.candidates({ maxGeneration = 9 })) do
  for _, v in ipairs(c.variants or {}) do lookOf[v] = c.id end
end
local function wildSpecies()
  local seen = {}
  for _, mapId in ipairs(maps) do
    for _, terrain in ipairs({ "land", "water", "fish.good", "fish.super" }) do
      local def = ms.tableFor(mapId, terrain)
      for _, s in ipairs(def and def.slots or {}) do
        local p = ms.profileOf(lookOf[s.species] or s.species)
        if p then seen[p.id] = true end
      end
      for _, list in pairs(ms.poolFor(mapId, terrain) or {}) do
        for _, id in ipairs(list) do seen[lookOf[id] or id] = true end
      end
    end
  end
  return seen
end
local function digest()
  local parts = {}
  for _, mapId in ipairs(maps) do
    parts[#parts + 1] = H.serialize(ms.tableFor(mapId, "land")) .. H.serialize(ms.poolFor(mapId, "land"))
  end
  return table.concat(parts)
end

-- CUSTOM, all nine ON = GEN 1-9
setOpt("spawn_mode", "complete")
local custom9 = digest()
setOpt("max_generation", "9")
T.check(digest() == custom9, "CUSTOM with every generation ON gives GEN 1-9's tables")
setOpt("max_generation", "custom")

local function pick(list)
  local on = set(list)
  for g = 1, 9 do setOpt("gen_" .. g, on[g] == true) end
end

for _, case in ipairs({ { { 3, 4, 5, 6, 7, 8 }, "GEN 3-8" }, { { 1, 3, 6 }, "GEN 1, 3, 6" } }) do
  local list, label = case[1], case[2]
  pick(list)
  local allowed = set(list)
  T.eq(table.concat(ms.generations(), ","), table.concat(list, ","), label .. ": generations()")
  T.eq(ms.maxGeneration(), list[#list], label .. ": maxGeneration() is the highest")
  for _, mode in ipairs({ "seeded", "complete" }) do
    setOpt("spawn_mode", mode)
    local seen, outside = wildSpecies(), {}
    for id in pairs(seen) do
      local p = ms.profileOf(id)
      if p and not allowed[p.generation] then outside[#outside + 1] = id .. "(" .. p.generation .. ")" end
    end
    table.sort(outside)
    T.eq(table.concat(outside, " ", 1, math.min(#outside, 8)), "", label .. " " .. mode .. ": only those generations")
    if mode == "complete" then
      local expected = ms.candidates({ generations = list })
      local obtainable = H.obtainable(seen, ms, allowed)
      local absent = {}
      for _, c in ipairs(expected) do
        if not obtainable(c.id) then absent[#absent + 1] = c.id end
      end
      T.check(#expected > 100, label .. ": candidates({ generations }) (" .. #expected .. ")")
      T.eq(#absent, 0, label .. " COMPLETE: all " .. #expected .. " species catchable or evolve from one ("
        .. table.concat(absent, ", ", 1, math.min(#absent, 8)) .. ")")
    end
  end
end

-- every generation OFF: the game's own tables
pick({})
T.eq(ms.isActive(), false, "CUSTOM with nothing ON: inactive")
T.eq(ms.tableFor(maps[1], "land"), nil, "... and the game's own tables")
T.eq(ms.generations(), nil, "generations() answers nil while inactive")
T.eq(#ms.settings().generations, 0, "settings().generations: none picked")
pick({ 4 })
T.eq(ms.isActive(), true, "one generation is enough")
run.release()

-- ======================================================== Red, the cart's own 151 only

local Data = require("src.core.Data")
Data:load()
local red = T.sdk.loadMods({ "mods/modern_spawns" }, { data = Data })
local rl = red.loader
rl.modSave.modern_spawns = { seed = "GENS" }
rl.modOptions.modern_spawns = { enabled = "on", max_generation = "custom", gen_1 = false,
  gen_2 = false, gen_3 = true, gen_4 = false, gen_5 = false, gen_6 = false, gen_7 = false,
  gen_8 = false, gen_9 = false }
H.manager(rl)
T.eq(rl.exports.modern_spawns.isActive(), false,
     "Red with no species mod, CUSTOM Gen 3 only: inactive, the game's own tables")
red.release()

T.finish("modern_spawns generations (CUSTOM)")
