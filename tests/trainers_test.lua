-- Standalone: luajit mods/modern_spawns/tests/trainers_test.lua (from the
-- gen1recomp root). TRAINER TEAMS' pure planner (src/trainers.lua) and held
-- items (src/trainer_items.lua) on a hand-built pool:
--   * a trainer keeps one family per original family, at the stage its level
--     allows, in every fight; a gym's every Pokemon has the gym's type;
--   * GENERATIONS caps species; legendaries never appear; the same seed gives
--     the same teams;
--   * a facility map is one-to-one even with few species to choose from;
--   * built movesets lead with same-type attacks;
--   * held items follow GENERATIONS and pick the best fit.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Config = H.module("src/config.lua")
local Rng = H.module("src/rng.lua")
local Trainers = H.module("src/trainers.lua")
local Items = H.module("src/trainer_items.lua")

-- a pool in species_pool.lua's shape: id, dex, gen, types, bst, stage,
-- parent, evolveLevel, special
local function set(list) local s = {} for _, t in ipairs(list) do s[t] = true end return s end
local SPECIES = {
  -- original families
  { "PIDGEY", 16, 1, { "NORMAL", "FLYING" }, 251 }, { "PIDGEOTTO", 17, 1, { "NORMAL", "FLYING" }, 349, "PIDGEY", 18 },
  { "PIDGEOT", 18, 1, { "NORMAL", "FLYING" }, 479, "PIDGEOTTO", 36 },
  { "GEODUDE", 74, 1, { "ROCK", "GROUND" }, 300 }, { "GRAVELER", 75, 1, { "ROCK", "GROUND" }, 390, "GEODUDE", 25 },
  { "ONIX", 95, 1, { "ROCK", "GROUND" }, 385 },
  { "RATTATA", 19, 1, { "NORMAL" }, 253 }, { "RATICATE", 20, 1, { "NORMAL" }, 413, "RATTATA", 20 },
  { "BULBASAUR", 1, 1, { "GRASS", "POISON" }, 318 }, { "IVYSAUR", 2, 1, { "GRASS", "POISON" }, 405, "BULBASAUR", 16 },
  { "VENUSAUR", 3, 1, { "GRASS", "POISON" }, 525, "IVYSAUR", 32 },
  -- replacements
  { "STARLY", 396, 4, { "NORMAL", "FLYING" }, 245 }, { "STARAVIA", 397, 4, { "NORMAL", "FLYING" }, 340, "STARLY", 14 },
  { "STARAPTOR", 398, 4, { "NORMAL", "FLYING" }, 485, "STARAVIA", 34 },
  { "PIDOVE", 519, 5, { "NORMAL", "FLYING" }, 264 }, { "TRANQUILL", 520, 5, { "NORMAL", "FLYING" }, 358, "PIDOVE", 21 },
  { "UNFEZANT", 521, 5, { "NORMAL", "FLYING" }, 488, "TRANQUILL", 32 },
  { "ROGGENROLA", 524, 5, { "ROCK" }, 280 }, { "BOLDORE", 525, 5, { "ROCK" }, 390, "ROGGENROLA", 25 },
  { "NACLI", 932, 9, { "ROCK" }, 280 }, { "NACLSTACK", 933, 9, { "ROCK" }, 355, "NACLI", 24 },
  { "ROLYCOLY", 837, 8, { "ROCK" }, 240 }, { "CARKOL", 838, 8, { "ROCK", "FIRE" }, 410, "ROLYCOLY", 18 },
  { "LECHONK", 915, 9, { "NORMAL" }, 254 }, { "OINKOLOGNE", 916, 9, { "NORMAL" }, 489, "LECHONK", 18 },
  { "CHIKORITA", 152, 2, { "GRASS" }, 318 }, { "BAYLEEF", 153, 2, { "GRASS" }, 405, "CHIKORITA", 16 },
  { "MEGANIUM", 154, 2, { "GRASS" }, 525, "BAYLEEF", 32 },
  { "EEVEE", 133, 1, { "NORMAL" }, 325 }, { "VAPOREON", 134, 1, { "WATER" }, 525, "EEVEE" },
  { "JOLTEON", 135, 1, { "ELECTRIC" }, 525, "EEVEE" },
  { "MEWTWO", 150, 1, { "PSYCHIC" }, 680, nil, nil, "legendary" },
  { "KORAIDON", 1007, 9, { "FIGHTING", "DRAGON" }, 670, nil, nil, "legendary" },
}
local function pool()
  local list, byId, depth = {}, {}, {}
  for _, s in ipairs(SPECIES) do
    local c = { id = s[1], dex = s[2], gen = s[3], types = set(s[4]), bst = s[5], parent = s[6],
                evolveLevel = s[7], special = s[8] }
    list[#list + 1], byId[c.id] = c, c
  end
  for _, c in ipairs(list) do
    local d, p = 1, c.parent
    while p do d = d + 1 p = byId[p] and byId[p].parent end
    c.stage = d
  end
  return { list = list, byId = byId }
end

local function ctxFor(seed, cap)
  return { pool = pool(), cap = cap or 9, seed = seed or "TRAIN", Rng = Rng, config = Config.TrainerConfig }
end

-- ------- a rival keeps its families across fights, at the stage the level allows

local ctx = ctxFor("RIVAL", 9)
local ix = Trainers.index(ctx.pool, ctx.cap)
local rival = { { species = "PIDGEY", level = 9 }, { species = "RATTATA", level = 8 },
                { species = "PIDGEOTTO", level = 20 }, { species = "RATICATE", level = 24 },
                { species = "PIDGEOT", level = 40 }, { species = "BULBASAUR", level = 10 },
                { species = "VENUSAUR", level = 42 } }
local plan = Trainers.planIdentity(ctx, ix, "rival", rival)
local early = Trainers.team(ctx, ix, plan, { rival[1], rival[2], rival[6] })
local mid = Trainers.team(ctx, ix, plan, { rival[3], rival[4] })
local late = Trainers.team(ctx, ix, plan, { rival[5], rival[7] })
local function rootOf(id) return ix.root[id] end
T.eq(rootOf(early[1]), rootOf(mid[1]), "the Pidgey line maps to one family (fight 1 and 2)")
T.eq(rootOf(mid[1]), rootOf(late[1]), "... and in the last fight")
T.check(rootOf(early[1]) ~= "PIDGEY", "a new family (" .. tostring(early[1]) .. ")")
T.check(ctx.pool.byId[late[1]].stage >= 3, "Lv 40: a final stage (" .. tostring(late[1]) .. ")")
T.check(ctx.pool.byId[early[1]].stage == 1, "Lv 9: a first stage (" .. tostring(early[1]) .. ")")
T.eq(Trainers.STARTERS[ctx.pool.byId[rootOf(early[3])].dex] and true or false, true,
     "a starter line becomes a starter line (" .. tostring(early[3]) .. ")")
local seen = {}
for _, id in ipairs({ early[1], early[2], early[3] }) do
  T.check(not seen[rootOf(id)], "no two of a family on one trainer")
  seen[rootOf(id)] = true
end

-- ------- a gym leader: every Pokemon has the gym's type

local brock = { { species = "GEODUDE", level = 12 }, { species = "ONIX", level = 14 } }
local gym = Trainers.planIdentity(ctx, ix, "OPP_BROCK", brock, "ROCK")
for _, id in ipairs(Trainers.team(ctx, ix, gym, brock)) do
  T.check(ctx.pool.byId[id].types.ROCK, "Brock's " .. id .. " is a Rock type")
end

-- ------- GENERATIONS and legendaries

local capped = ctxFor("RIVAL", 1)
local cix = Trainers.index(capped.pool, 1)
local cplan = Trainers.planIdentity(capped, cix, "rival", rival)
for _, id in ipairs(Trainers.team(capped, cix, cplan, rival)) do
  T.check(capped.pool.byId[id].gen <= 1, "GEN 1: " .. id .. " is Gen 1")
  T.check(not capped.pool.byId[id].special, "never a legendary")
end
for seed = 1, 20 do
  local c2 = ctxFor(seed, 9)
  local i2 = Trainers.index(c2.pool, 9)
  for _, id in ipairs(Trainers.team(c2, i2, Trainers.planIdentity(c2, i2, "x", rival), rival)) do
    T.check(not c2.pool.byId[id].special, "seed " .. seed .. ": never a legendary")
  end
end
local again = Trainers.team(ctx, ix, Trainers.planIdentity(ctxFor("RIVAL", 9), ix, "rival", rival), rival)
T.eq(table.concat(again, ","), table.concat(Trainers.team(ctx, ix, plan, rival), ","), "same seed, same team")

-- Eevee takes one branch for a trainer, every time
local eevee = { { species = "EEVEE", level = 30 } }
local e1 = Trainers.stageFor(ix, ctx.config, "EEVEE", 30, 2, plan.branch)
local e2 = Trainers.stageFor(ix, ctx.config, "EEVEE", 30, 2, plan.branch)
T.eq(e1, e2, "a branching family takes the same branch every time (" .. tostring(e1) .. ")")
T.eq(Trainers.stageFor(ix, ctx.config, "EEVEE", 20, 1, plan.branch), "EEVEE",
     "a stone evolution waits for Lv " .. ctx.config.stage2_level)

-- ------- facility maps are one-to-one

local originals = { PIDGEY = true, PIDGEOT = true, GEODUDE = true, ONIX = true, RATTATA = true,
                    VENUSAUR = true, MEWTWO = true, EEVEE = true }
local map = Trainers.facilityMap(ctx, ix, "tower", originals)
local used, distinct = {}, true
for o, n in pairs(map) do
  if used[n] then distinct = false end
  used[n] = true
  T.check(not ctx.pool.byId[n].special, "facility: " .. o .. " -> " .. n .. " is no legendary")
end
T.check(distinct, "facility map is one-to-one")
-- more originals than new species: the map stays one-to-one (originals fill in)
local tight = ctxFor("T", 1)
local tix = Trainers.index(tight.pool, 1)
local all = {}
for _, c in ipairs(tight.pool.list) do if c.gen == 1 then all[c.id] = true end end
local tmap = Trainers.facilityMap(tight, tix, "tight", all)
local tused, tdistinct = {}, true
for _, n in pairs(tmap) do
  if tused[n] then tdistinct = false end
  tused[n] = true
end
T.check(tdistinct, "facility map stays one-to-one when species run short")

-- ------- built movesets

local MOVES = {
  TACKLE = { name = "TACKLE", type = "NORMAL", power = 40, accuracy = 100 },
  GUST = { name = "GUST", type = "FLYING", power = 40, accuracy = 100 },
  WING_ATTACK = { name = "WING_ATTACK", type = "FLYING", power = 60, accuracy = 100 },
  QUICK_ATTACK = { name = "QUICK_ATTACK", type = "NORMAL", power = 40, accuracy = 100 },
  STEEL_WING = { name = "STEEL_WING", type = "STEEL", power = 70, accuracy = 90 },
  AGILITY = { name = "AGILITY", type = "PSYCHIC", power = 0, accuracy = 100 },
  DOUBLE_EDGE = { name = "DOUBLE_EDGE", type = "NORMAL", power = 120, accuracy = 100 },
  SAND_ATTACK = { name = "SAND_ATTACK", type = "GROUND", power = 0, accuracy = 100 },
}
local learnset = {
  { level = 1, move = "TACKLE" }, { level = 1, move = "SAND_ATTACK" }, { level = 9, move = "GUST" },
  { level = 13, move = "QUICK_ATTACK" }, { level = 23, move = "WING_ATTACK" }, { level = 30, move = "AGILITY" },
  { level = 33, move = "STEEL_WING" }, { level = 41, move = "DOUBLE_EDGE" },
}
local built = Trainers.buildSet(learnset, 45, set({ "NORMAL", "FLYING" }), function(m) return MOVES[m] end)
T.eq(built[1], "DOUBLE_EDGE", "the best same-type attack first")
T.eq(built[2], "WING_ATTACK", "then its other type's best")
T.eq(built[3], "STEEL_WING", "then one attack of another type")
T.eq(built[4], "AGILITY", "then a status move from the list")
local low = Trainers.buildSet(learnset, 5, set({ "NORMAL", "FLYING" }), function(m) return MOVES[m] end)
T.eq(table.concat(low, ","), "TACKLE,SAND_ATTACK", "Lv 5: only what it knows, an unlisted status move last")
local transform = Trainers.buildSet({ { level = 1, move = "TRANSFORM" } }, 50, set({ "NORMAL" }),
  function(m) return { name = m, type = "NORMAL", power = 0 } end)
T.eq(table.concat(transform or {}, ","), "TRANSFORM", "a Ditto keeps its only move")

-- ------- held items follow GENERATIONS and fit the Pokemon

local function available(names) return function(n) return names[n] == true end end
local everything = available(set({ "LEFTOVERS", "LIFE_ORB", "BLACK_SLUDGE", "EVIOLITE", "CHARCOAL", "FLAME_PLATE",
  "SITRUS_BERRY", "LUM_BERRY", "BERRY", "GOLD_BERRY", "POISON_BARB", "TOXIC_PLATE", "CHOICE_BAND",
  "SILK_SCARF", "PINK_BOW" }))
local fire = { types = set({ "FIRE" }), canEvolve = false,
               moves = { { type = "FIRE", power = 90 }, { type = "FIRE", power = 60 }, { type = "NORMAL", power = 70 },
                         { type = "PSYCHIC", power = 0 } } }
local strong = { hp = 78, attack = 84, defense = 78, speed = 100, spAttack = 109, spDefense = 85 }
local rng = Rng.new(1)
T.eq(Items.choose({ role = "ace", mon = fire, stats = strong, maxGen = 3, available = everything, rng = rng }),
     "LEFTOVERS", "GEN 1-3: a Gen 3 ace holds Leftovers, no Life Orb")
T.eq(Items.choose({ role = "ace", mon = fire, stats = strong, maxGen = 4, available = everything, rng = rng }),
     "LIFE_ORB", "GEN 1-4: an offensive ace holds a Life Orb")
local poison = { types = set({ "POISON" }), canEvolve = false, moves = { { type = "POISON", power = 80 } } }
T.eq(Items.choose({ role = "ace", mon = poison, stats = { hp = 90, attack = 60, defense = 80, speed = 50,
     spAttack = 60, spDefense = 80 }, maxGen = 9, available = everything, rng = rng }),
     "BLACK_SLUDGE", "a Poison type holds Black Sludge over Leftovers")
T.eq(Items.choose({ role = "ace", mon = { types = set({ "NORMAL" }), canEvolve = true,
     moves = { { type = "NORMAL", power = 40 } } }, stats = strong, maxGen = 9, available = everything, rng = rng }),
     "EVIOLITE", "one that can still evolve holds an Eviolite")
T.eq(Items.choose({ role = "boss", slot = 1, mon = fire, stats = strong, maxGen = 3, available = everything, rng = rng }),
     "CHARCOAL", "a boss's odd slot holds its type's booster")
T.eq(Items.choose({ role = "boss", slot = 1, mon = fire, stats = strong, maxGen = 4, available = everything, rng = rng }),
     "FLAME_PLATE", "GEN 1-4: the plate")
T.eq(Items.choose({ role = "boss", slot = 2, mon = fire, stats = strong, maxGen = 2, available = everything, rng = rng }),
     "GOLD_BERRY", "GEN 1-2: a boss's even slot holds the best Gen 2 berry")
T.eq(Items.choose({ role = "boss", slot = 2, mon = fire, stats = strong, maxGen = 3, available = everything, rng = rng }),
     "LUM_BERRY", "GEN 1-3: a Lum Berry")
T.eq(Items.choose({ role = "ace", mon = fire, stats = strong, maxGen = 9,
     available = available(set({ "CHARCOAL" })), rng = rng }), "CHARCOAL",
     "only what the game has: an item missing from the game is never handed out")
T.eq(Items.choose({ role = "ace", mon = fire, stats = strong, maxGen = 9, available = everything, rng = rng,
     used = { LIFE_ORB = true } }) ~= "LIFE_ORB", true, "no two of an item on one team")
local held = 0
local orng = Rng.new(Rng.hash("ordinary"))
for _ = 1, 1000 do
  if Items.choose({ role = "ordinary", mon = fire, stats = strong, maxGen = 9, available = everything,
                    rng = orng, chance = 0.2 }) then held = held + 1 end
end
T.check(held > 140 and held < 260, "an ordinary trainer's Pokemon holds something about 1 in 5 times (" .. held .. ")")

T.finish("modern_spawns trainers (planner)")
