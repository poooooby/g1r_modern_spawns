-- TRAINER TEAMS on Gold, Silver and Crystal: the trainer data, who is who,
-- and the trainer.party hook's shape.
--
-- Trainers are classes (FALKNER) holding named members (FALKNER1) with
-- parties ({ species, level, item?, moves? }). The hook gets (class, member
-- id, the battle's freshly built Pokemon); a changed slot is rebuilt the way
-- the game builds a trainer's Pokemon (Mon.new, fixed trainer DVs), so its
-- stats, moves and name are the new species'. The Battle Tower (member id 1)
-- and link battles (no class) are left alone here.

return function(reg, mod)
  local A = { generation = 2, cartGeneration = 2 }

  local function engine(name)
    local ok, module = pcall(require, name)
    return ok and type(module) == "table" and module or nil
  end

  -- Gym leaders, the Elite Four and the champion keep their type
  A.GYM_TYPES = {
    FALKNER = "FLYING", BUGSY = "BUG", WHITNEY = "NORMAL", MORTY = "GHOST", CHUCK = "FIGHTING",
    JASMINE = "STEEL", PRYCE = "ICE", CLAIR = "DRAGON",
    BROCK = "ROCK", MISTY = "WATER", LT_SURGE = "ELECTRIC", ERIKA = "GRASS", JANINE = "POISON",
    SABRINA = "PSYCHIC", BLAINE = "FIRE",
    WILL = "PSYCHIC", KOGA = "POISON", BRUNO = "FIGHTING", KAREN = "DARK", CHAMPION = "DRAGON",
  }
  -- bosses with no single type, and the rival
  local BOSS = { BLUE = true, RED = true, RIVAL1 = true, RIVAL2 = true }
  local RIVAL = { RIVAL1 = true, RIVAL2 = true }
  -- the Elite Four and the champion: every Pokemon may hold an item (ON + ITEMS)
  local ELITE = { WILL = true, KOGA = true, BRUNO = true, KAREN = true, CHAMPION = true }

  local function memberOf(class, memberId)
    local record = reg.get("trainers", class)
    for _, member in ipairs(type(record) == "table" and record.trainers or {}) do
      if member.id == memberId then return member end
    end
    return nil
  end

  function A.identityOf(class, member)
    if RIVAL[class] then return "rival" end
    return class .. ":" .. tostring(member and member.name or "?")
  end

  local function isBoss(class) return A.GYM_TYPES[class] ~= nil or BOSS[class] == true end

  function A.identities()
    local out = {}
    for _, class in ipairs(reg.ids("trainers")) do
      local record = reg.get("trainers", class)
      for _, member in ipairs(type(record) == "table" and record.trainers or {}) do
        local id = A.identityOf(class, member)
        local info = out[id] or { appearances = {}, gymType = A.GYM_TYPES[class], boss = isBoss(class) }
        out[id] = info
        -- the lowest and highest of its battles' top levels: the rival's
        -- first and final battle (ON + ITEMS)
        local top
        for _, row in ipairs(member.party or {}) do
          if type(row.species) == "string" then
            local level = tonumber(row.level) or 5
            info.appearances[#info.appearances + 1] = { species = row.species, level = level }
            top = math.max(top or level, level)
          end
        end
        if top then
          info.firstTop = math.min(info.firstTop or top, top)
          info.lastTop = math.max(info.lastTop or top, top)
        end
      end
    end
    return out
  end

  -- Only story trainers: a member id the data knows (the Battle Tower passes
  -- the number 1, link battles no class).
  function A.read(class, memberId, party)
    if type(class) ~= "string" or type(memberId) ~= "string" then return nil end
    local member = memberOf(class, memberId)
    if not member or type(party) ~= "table" or #party == 0 then return nil end
    local rows = {}
    for i, mon in ipairs(party) do
      if type(mon) ~= "table" or type(mon.species) ~= "string" then return nil end
      local own = member.party and member.party[i]
      rows[i] = { species = mon.species, level = tonumber(mon.level) or 5,
                  item = mon.item, customMoves = own and own.moves and #own.moves > 0 }
    end
    return { identity = A.identityOf(class, member), key = class .. ":" .. memberId,
             gymType = A.GYM_TYPES[class], boss = isBoss(class), elite = ELITE[class] == true, rows = rows }
  end

  local function data() return mod.game and mod.game.data end

  local function plainType(t) return t and (tostring(t):gsub("_TYPE$", "")) or nil end

  -- WoobleDex's MOVE SPLIT (option move_split, off by default; one setting for every game):
  -- physical or special by the move itself, as its battles then resolve every hit, from the
  -- move's damage class in today's games (its moveById export). nil while the option is off,
  -- for a status move, or without WoobleDex: the game's own split by type stands
  -- (src/trainer_items.lua). Choice Band / Choice Specs follow it.
  local function splitCategory(id)
    local okO, on = pcall(function()
      local options = mod.game.mods.modOptions
      return options and options.national_dex_gen3 and options.national_dex_gen3.move_split
    end)
    if not (okO and on == true) then return nil end
    local okF, dex = pcall(function() return mod:find("national_dex_gen3") end)
    local fn = okF and type(dex) == "table" and type(dex.exports) == "table" and dex.exports.moveById
    if type(fn) ~= "function" then return nil end
    local ok, rec = pcall(fn, id)
    local c = ok and type(rec) == "table" and rec.damageClass
    return (c == "physical" or c == "special") and c or nil
  end

  -- move -> { name, type (plain), power, accuracy, category? (MOVE SPLIT only) }
  local function moveInfo(id)
    local m = data() and data().moves and data().moves[id]
    if not m then return nil end
    return { name = m.id or id, type = plainType(m.type), power = m.power, accuracy = m.accuracy,
             category = splitCategory(id) }
  end

  local function typesOf(species)
    local def = data() and data().pokemon and data().pokemon[species]
    local set = {}
    for _, t in ipairs(def and def.types or {}) do set[plainType(t)] = true end
    return set
  end

  -- a built set (see src/trainers.lua buildSet), for the species' own moves
  function A.builtSet(Planner, species, level)
    local def = data() and data().pokemon and data().pokemon[species]
    if not def then return nil end
    return Planner.buildSet(def.levelMoves, level, typesOf(species), moveInfo)
  end

  -- the moves its item is chosen by (built set)
  function A.movesFor(species, level)
    local out = {}
    local Planner = A.Planner
    for _, id in ipairs(Planner and A.builtSet(Planner, species, level) or {}) do
      local m = moveInfo(id)
      if m then out[#out + 1] = m end
    end
    return out
  end

  function A.statsOf(species)
    local def = data() and data().pokemon and data().pokemon[species]
    local b = def and def.baseStats or {}
    return { hp = b.hp, attack = b.attack, defense = b.defense, speed = b.speed,
             spAttack = b.specialAttack, spDefense = b.specialDefense }
  end

  -- An item the game has AND can hold to some effect: the cart's own held
  -- effect, or one WoobleDex registered and runs (its newer held items).
  function A.itemAvailable(name)
    local items = data() and data().items
    local item = items and items[name]
    if not item then return false end
    if item.heldEffect and item.heldEffect ~= "HELD_NONE" then return true end
    local ok, dex = pcall(function() return mod:find("national_dex_gen3") end)
    local held = ok and dex and dex.exports and dex.exports._heldModern
    return type(held) == "table" and type(held.byId) == "table" and held.byId[name] ~= nil
  end

  local TRAINER_DVS = { attack = 9, defense = 8, speed = 8, special = 8 }

  -- The party with each changed slot rebuilt; unchanged slots keep their own
  -- built Pokemon.
  function A.write(party, battle, species, items)
    local Mon = engine("src.battle.gen2.Mon")
    local d = data()
    if not (Mon and d) then return nil end
    local out = {}
    for i, mon in ipairs(party) do
      local newSpecies = species[i] or mon.species
      local item = items and items[i]
      if newSpecies ~= mon.species or item then
        local moves
        if battle.rows[i].customMoves and A.Planner then
          local built = A.builtSet(A.Planner, newSpecies, mon.level)
          if built then
            moves = {}
            for _, id in ipairs(built) do
              local def = d.moves and d.moves[id]
              moves[#moves + 1] = { id = id, pp = def and def.pp or 0, maxPp = def and def.pp or 0 }
            end
          end
        end
        local dvs = {}
        for k, v in pairs(TRAINER_DVS) do dvs[k] = v end
        local rebuilt = Mon.new(d, newSpecies, mon.level, {
          moves = moves, item = item or mon.item, dvs = dvs, nickname = mon.nickname })
        out[i] = rebuilt or mon
      else
        out[i] = mon
      end
    end
    return out
  end

  function A.canShow(id)
    local d = data()
    if d and d.pokemon then return d.pokemon[id] ~= nil end
    return reg.get("pokemon", id) ~= nil
  end

  return A
end
