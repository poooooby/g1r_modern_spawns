-- TRAINER TEAMS' held items (ON + ITEMS), pure: which item fits a trainer's
-- Pokemon. Every row has the generation it arrived in, so GENERATIONS gates
-- items the way it gates species, and a newer item that suits the Pokemon
-- better wins (Black Sludge over Leftovers for a Poison type, Eviolite for one
-- that can still evolve). Only items the running game has AND can use in
-- battle are handed out: the caller's `available(name)` says so (the cart's
-- own effects, or WoobleDex's for the newer ones).

local Items = {}

-- Type boosters by type, in the order they are tried (each game spells some
-- of them its own way; Gold/Silver/Crystal's Dragon booster is the Dragon
-- Scale, the Gen 3 games' the Dragon Fang).
Items.TYPE_BOOST = {
  NORMAL = { { "SILK_SCARF", 3 }, { "PINK_BOW", 2 }, { "POLKADOT_BOW", 2 } },
  FIRE = { { "CHARCOAL", 2 } },
  WATER = { { "MYSTIC_WATER", 2 }, { "SEA_INCENSE", 3 } },
  GRASS = { { "MIRACLE_SEED", 2 } },
  ELECTRIC = { { "MAGNET", 2 } },
  ICE = { { "NEVERMELTICE", 2 }, { "NEVER_MELT_ICE", 2 } },
  FIGHTING = { { "BLACKBELT", 2 }, { "BLACKBELT_I", 2 }, { "BLACK_BELT", 2 } },
  POISON = { { "POISON_BARB", 2 } },
  GROUND = { { "SOFT_SAND", 2 } },
  FLYING = { { "SHARP_BEAK", 2 } },
  PSYCHIC = { { "TWISTEDSPOON", 2 }, { "TWISTED_SPOON", 2 } },
  BUG = { { "SILVERPOWDER", 2 }, { "SILVER_POWDER", 2 } },
  ROCK = { { "HARD_STONE", 2 } },
  GHOST = { { "SPELL_TAG", 2 } },
  DRAGON = { { "DRAGON_FANG", 2 }, { "DRAGON_SCALE", 2 } },
  DARK = { { "BLACKGLASSES", 2 }, { "BLACK_GLASSES", 2 } },
  STEEL = { { "METAL_COAT", 2 } },
}
-- Plates (Gen 4; the Pixie Plate Gen 6): a stronger booster where they exist
Items.PLATE = {
  FIRE = "FLAME_PLATE", WATER = "SPLASH_PLATE", ELECTRIC = "ZAP_PLATE", GRASS = "MEADOW_PLATE",
  ICE = "ICICLE_PLATE", FIGHTING = "FIST_PLATE", POISON = "TOXIC_PLATE", GROUND = "EARTH_PLATE",
  FLYING = "SKY_PLATE", PSYCHIC = "MIND_PLATE", BUG = "INSECT_PLATE", ROCK = "STONE_PLATE",
  GHOST = "SPOOKY_PLATE", DRAGON = "DRACO_PLATE", DARK = "DREAD_PLATE", STEEL = "IRON_PLATE",
  FAIRY = "PIXIE_PLATE",
}

Items.BERRIES = {
  { name = "LUM_BERRY", gen = 3, score = 32 },
  { name = "SITRUS_BERRY", gen = 3, score = 31 },
  { name = "MIRACLEBERRY", gen = 2, score = 29 },
  { name = "GOLD_BERRY", gen = 2, score = 28 },
  { name = "ORAN_BERRY", gen = 3, score = 20 },
  { name = "BERRY", gen = 2, score = 20 },
}

-- Physical and special by type, as Gen 2 and 3 split them (a move's own
-- category wins when it has one)
local PHYSICAL = { NORMAL = true, FIGHTING = true, FLYING = true, POISON = true, GROUND = true,
                   ROCK = true, BUG = true, GHOST = true, STEEL = true }

local function categoryOf(m)
  if m.category == "physical" or m.category == "special" then return m.category end
  return PHYSICAL[m.type] and "physical" or "special"
end

-- what the Pokemon's moves look like: { damaging, all = every move damaging,
-- physical, special counts, bestType = its strongest same-type attack's type }
local function shape(mon)
  local s = { damaging = 0, physical = 0, special = 0, count = #(mon.moves or {}) }
  local best, bestValue = nil, -1
  for _, m in ipairs(mon.moves or {}) do
    if (tonumber(m.power) or 0) > 1 then
      s.damaging = s.damaging + 1
      local cat = categoryOf(m)
      s[cat] = s[cat] + 1
      local value = tonumber(m.power) or 0
      if mon.types[m.type] then value = value * 1.5 end
      if value > bestValue then best, bestValue = m.type, value end
    end
  end
  s.all = s.count > 0 and s.damaging == s.count
  -- no attack: its first type
  if not best then
    for t in pairs(mon.types) do
      if not best or t < best then best = t end
    end
  end
  s.bestType = best
  return s
end

-- The "ace" items, best first by score; cond(mon, stats, shape)
Items.ACE = {
  { name = "EVIOLITE", gen = 5, score = 45, cond = function(mon) return mon.canEvolve end },
  { name = "BLACK_SLUDGE", gen = 4, score = 44, cond = function(mon) return mon.types.POISON end },
  { name = "ASSAULT_VEST", gen = 6, score = 43, cond = function(_, st, sh)
      return sh.all and st.hp >= 80 and st.spDefense >= 80 end },
  { name = "LIFE_ORB", gen = 4, score = 42, cond = function(_, st, sh)
      return math.max(st.attack, st.spAttack) >= 100 and sh.damaging >= 3 end },
  { name = "CHOICE_BAND", gen = 3, score = 41, cond = function(_, st, sh)
      return sh.all and sh.special == 0 and st.attack >= st.spAttack end },
  { name = "CHOICE_SPECS", gen = 4, score = 41, cond = function(_, st, sh)
      return sh.all and sh.physical == 0 and st.spAttack >= st.attack end },
  { name = "CHOICE_SCARF", gen = 4, score = 41, cond = function(_, st, sh)
      return sh.all and st.speed >= 80 and math.max(st.attack, st.spAttack) >= 90 end },
  { name = "LEFTOVERS", gen = 2, score = 40, cond = function() return true end },
  { name = "FOCUS_SASH", gen = 4, score = 39, cond = function(_, st)
      return st.speed >= 90 and st.hp <= 60 and st.defense <= 70 end },
}

-- A type booster for `t`: the plate where allowed and present, else the
-- game's own booster.
local function typeItem(t, allowed)
  local plate = Items.PLATE[t]
  if plate and allowed(plate, plate == "PIXIE_PLATE" and 6 or 4) then
    return { name = plate, score = 34 }
  end
  for _, row in ipairs(Items.TYPE_BOOST[t] or {}) do
    if allowed(row[1], row[2]) then return { name = row[1], score = 30 } end
  end
  return nil
end

local function bestBerry(allowed)
  for _, b in ipairs(Items.BERRIES) do
    if allowed(b.name, b.gen) then return { name = b.name, score = b.score } end
  end
  return nil
end

-- One Pokemon's item, or nil.
--   args.role       "ace" (a boss's strongest), "boss" or "ordinary"
--   args.slot       its party position (bosses alternate berries and boosters)
--   args.mon        { types (plain names set), canEvolve, moves = { {type, power, category?} } }
--   args.stats      { hp, attack, defense, speed, spAttack, spDefense }
--   args.maxGen     items up to this generation (max(GENERATIONS, the cart's own))
--   args.available  function(name) -> true when the game has it and it works
--   args.used       names already held on this team (skipped)
--   args.rng        Rng for the ordinary trainer's chance and coin
--   args.chance     the ordinary trainer's chance (Config.TrainerConfig)
function Items.choose(args)
  local used = args.used or {}
  local function allowed(name, gen)
    return gen <= args.maxGen and not used[name] and args.available(name)
  end
  local mon, st = args.mon, args.stats or {}
  for _, k in ipairs({ "hp", "attack", "defense", "speed", "spAttack", "spDefense" }) do
    st[k] = tonumber(st[k]) or 0
  end
  local sh = shape(mon)
  local options = {}
  local function add(entry)
    if entry then options[#options + 1] = entry end
  end
  if args.role == "ordinary" then
    if args.rng:next() >= (args.chance or 0) then return nil end
    if args.rng:int(1, 2) == 1 then
      add(bestBerry(allowed))
    else
      add(sh.bestType and typeItem(sh.bestType, allowed))
    end
  elseif args.role == "ace" then
    for _, row in ipairs(Items.ACE) do
      if allowed(row.name, row.gen) and row.cond(mon, st, sh) then
        add({ name = row.name, score = row.score })
      end
    end
    add(sh.bestType and typeItem(sh.bestType, allowed))
  else
    -- a boss's other Pokemon: a booster or a berry by slot, unless a newer
    -- item suits it better (Eviolite, Black Sludge)
    if (args.slot or 1) % 2 == 1 then
      add(sh.bestType and typeItem(sh.bestType, allowed))
    else
      add(bestBerry(allowed))
    end
    for _, row in ipairs(Items.ACE) do
      if (row.name == "EVIOLITE" or row.name == "BLACK_SLUDGE")
        and allowed(row.name, row.gen) and row.cond(mon, st, sh) then
        add({ name = row.name, score = row.score })
      end
    end
    -- nothing of its slot's kind: the other kind
    if #options == 0 then
      add(bestBerry(allowed))
      add(sh.bestType and typeItem(sh.bestType, allowed))
    end
  end
  if #options == 0 then return nil end
  table.sort(options, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.name < b.name
  end)
  return options[1].name
end

Items._shape = shape
return Items
