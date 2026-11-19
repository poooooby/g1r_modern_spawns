-- TRAINER TEAMS on FireRed, LeafGreen, Ruby, Sapphire and Emerald (story
-- trainers; the facilities are src/facilities_gen3.lua).
--
-- The hook gets (trainer class number, trainer id, the party with species,
-- moves and held items as names -- Gen3Compat.partyNames). A changed row gets
-- the new species' numeric slot, no moves (the engine teaches the moves it
-- knows at that level) or a built set where the game gave it custom moves,
-- and an item in both `heldItem` and `item` (the battle reads `item`). Only
-- story trainers: a trainer id the trainers pack knows, never 0 (Trainer
-- Tower), 1024 (secret bases) or nil (Frontier, Trainer Hill, link battles).

return function(reg, mod, world)
  local A = { generation = 3, cartGeneration = 3 }

  local function engine(name)
    local ok, module = pcall(require, name)
    return ok and type(module) == "table" and module or nil
  end

  -- by trainer name, for LEADER / ELITE FOUR / CHAMPION
  A.GYM_TYPES = {
    BROCK = "ROCK", MISTY = "WATER", ["LT. SURGE"] = "ELECTRIC", ERIKA = "GRASS", KOGA = "POISON",
    SABRINA = "PSYCHIC", BLAINE = "FIRE", GIOVANNI = "GROUND",
    LORELEI = "ICE", BRUNO = "FIGHTING", AGATHA = "GHOST", LANCE = "DRAGON",
    ROXANNE = "ROCK", BRAWLY = "FIGHTING", WATTSON = "ELECTRIC", FLANNERY = "FIRE", NORMAN = "NORMAL",
    WINONA = "FLYING", ["TATE&LIZA"] = "PSYCHIC", JUAN = "WATER", WALLACE = "WATER",
    SIDNEY = "DARK", PHOEBE = "GHOST", GLACIA = "ICE", DRAKE = "DRAGON",
  }
  local TYPED = { LEADER = true, ["ELITE FOUR"] = true, CHAMPION = true }
  local BOSS = { LEADER = true, ["ELITE FOUR"] = true, CHAMPION = true, RIVAL = true,
                 ["AQUA LEADER"] = true, ["MAGMA LEADER"] = true }

  local function pack()
    local Trainers = engine("src.core.game3.scripting.trainers")
    local ok, p = pcall(function() return Trainers and Trainers.pack() end)
    return ok and type(p) == "table" and p or nil
  end

  local RSE_RIVALS = { MAY = true, BRENDAN = true }
  local rivalNames
  local function classify(row, p)
    local className = tostring(row.className or (p.classNames and p.classNames[row.class]) or "")
    local name = tostring(row.name or "?")
    if not rivalNames then
      rivalNames = {}
      for _, t in pairs(p.trainers or {}) do
        local cn = t.className or (p.classNames and p.classNames[t.class])
        if cn == "RIVAL" and t.name then rivalNames[t.name] = true end
      end
    end
    -- FireRed's rival keeps one name across the RIVAL and CHAMPION classes
    local identity = className .. ":" .. name
    if (className == "RIVAL" or className == "CHAMPION") and rivalNames[name] then identity = "rival" end
    local gymType = TYPED[className] and A.GYM_TYPES[name] or nil
    local boss = BOSS[className] == true or className:find("TRAINER", 1, true) ~= nil and name ~= "?"
    -- Ruby, Sapphire and Emerald's rival is May or Brendan (POKéMON TRAINER)
    local rival = identity == "rival" or (className:find("TRAINER", 1, true) ~= nil and RSE_RIVALS[name] == true)
    return identity, gymType, boss, rival
  end

  -- the registry id for a numeric species slot (the cart's own and modded)
  local idOfSlot
  local function speciesIdOf(slot)
    if not idOfSlot then
      idOfSlot = {}
      for _, id in ipairs(reg.ids("pokemon")) do
        local rec = reg.get("pokemon", id)
        local index = type(rec) == "table" and tonumber(rec.index)
        -- a form shares nothing here: the base species keeps its own slot
        if index and not (rec.form or rec.baseSpecies) then idOfSlot[index] = idOfSlot[index] or id end
      end
    end
    return idOfSlot[tonumber(slot) or -1]
  end
  A.speciesIdOf = speciesIdOf

  function A.identities()
    local p = pack()
    local out = {}
    for _, row in pairs(p and p.trainers or {}) do
      local identity, gymType, boss, rival = classify(row, p)
      local info = out[identity] or { appearances = {}, gymType = gymType, boss = boss, rival = rival }
      out[identity] = info
      for _, m in ipairs(row.party or {}) do
        local id = speciesIdOf(m.species)
        if id then info.appearances[#info.appearances + 1] = { species = id, level = tonumber(m.level) or 5 } end
      end
    end
    return out
  end

  function A.read(_, trainerId, party)
    trainerId = tonumber(trainerId)
    if not trainerId or trainerId <= 0 or trainerId == 1024 or type(party) ~= "table" or #party == 0 then
      return nil
    end
    local p = pack()
    local own = p and p.trainers and p.trainers[trainerId]
    if not own then return nil end
    local identity, gymType, boss, rival = classify(own, p)
    local rows = {}
    for i, row in ipairs(party) do
      if type(row) ~= "table" then return nil end
      local id = tonumber(row.speciesId) and speciesIdOf(tonumber(row.speciesId)) or row.species
      -- a two-opponent battle merges two trainers' parties: each row is its own trainer's
      local rowOwner = tonumber(row.trainerId)
      local rowIdentity
      if rowOwner and rowOwner ~= trainerId and p.trainers[rowOwner] then
        rowIdentity = (classify(p.trainers[rowOwner], p))
      end
      local item = row.heldItem
      if item == "" or item == 0 or item == "NONE" or item == "ITEM_NONE" then item = nil end
      rows[i] = { species = id, level = tonumber(row.level) or 5, item = item,
                  customMoves = type(row.moves) == "table" and #row.moves > 0,
                  identity = rowIdentity }
    end
    return { identity = identity, key = "trainer:" .. trainerId, gymType = gymType, boss = boss,
             rival = rival, rows = rows }
  end

  -- ------------------------------------------------------------ moves

  local TYPE_NAMES
  local function typeName(t)
    if type(t) == "string" then return (t:gsub("_TYPE$", ""):gsub("^TYPE_", "")) end
    if not TYPE_NAMES then
      TYPE_NAMES = {}
      local Types = engine("src.core.game3.battle.types")
      for name, id in pairs(Types and Types.ID or {}) do TYPE_NAMES[id] = name end
    end
    return TYPE_NAMES[tonumber(t) or -1]
  end

  local function moveInfo(num)
    local Moves = engine("src.core.game3.battle.moves")
    local ok, m = pcall(function() return Moves.get(num) end)
    if not ok or type(m) ~= "table" then return nil end
    return { name = m.id, type = typeName(m.type), power = m.power, accuracy = m.accuracy,
             category = m.category ~= "status" and m.category or nil }
  end

  local function slotOf(id)
    local rec = reg.get("pokemon", id)
    return type(rec) == "table" and tonumber(rec.index) or nil
  end
  A.slotOf = slotOf
  A.moveInfo = moveInfo

  local function learnset(id)
    local Pokemon = engine("src.core.game3.pokemon")
    local slot = slotOf(id)
    local out = {}
    if not (Pokemon and slot) then return out end
    for _, r in ipairs(Pokemon.learnset(slot) or {}) do
      out[#out + 1] = { level = tonumber(r.level or r[1]) or 1, move = tonumber(r.move or r[2]) }
    end
    return out
  end

  local function typesOf(id)
    local rec = reg.get("pokemon", id)
    local set = {}
    for _, t in ipairs(type(rec) == "table" and rec.types or {}) do
      local n = typeName(t)
      if n then set[n] = true end
    end
    return set
  end

  function A.builtSet(Planner, id, level)
    return Planner.buildSet(learnset(id), level, typesOf(id), moveInfo)
  end

  function A.movesFor(id, level)
    local out = {}
    for _, num in ipairs(A.Planner and A.builtSet(A.Planner, id, level) or {}) do
      local m = moveInfo(num)
      if m then out[#out + 1] = m end
    end
    return out
  end

  function A.statsOf(id)
    local rec = reg.get("pokemon", id)
    local b = type(rec) == "table" and rec.baseStats or {}
    return { hp = b.hp, attack = b.attack, defense = b.defense, speed = b.speed,
             spAttack = b.spAttack or b.specialAttack, spDefense = b.spDefense or b.specialDefense }
  end

  -- the engine teaches what it knows at that level, and errors on nothing
  function A.canShow(id, level)
    for _, r in ipairs(learnset(id)) do
      if r.level <= (level or 100) and r.move and r.move > 0 then return true end
    end
    return false
  end

  -- ------------------------------------------------------------ items

  local function wooble()
    local ok, dex = pcall(function() return mod:find("national_dex_gen3") end)
    local held = ok and dex and dex.exports and dex.exports._held
    return type(held) == "table" and type(held.state) == "table" and held.state.byId or nil
  end

  -- the item's number, when the game has it AND it does something held
  function A.itemNumber(name)
    local byId = wooble()
    if byId and byId[name] and tonumber(byId[name].index) then return tonumber(byId[name].index) end
    local ItemsData = engine("src.core.game3.items_data")
    local HeldItems = engine("src.core.game3.battle.held_items")
    local ok, num = pcall(function() return ItemsData.toNumericId(name) end)
    if not (ok and tonumber(num)) then return nil end
    local okE, effect = pcall(function() return HeldItems.effectOf(num) end)
    if okE and tonumber(effect) and effect ~= 0 then return tonumber(num) end
    return nil
  end

  function A.itemAvailable(name) return A.itemNumber(name) ~= nil end

  -- ------------------------------------------------------------ write

  function A.write(party, battle, species, items)
    local out = {}
    for i, row in ipairs(party) do
      local copy = {}
      for k, v in pairs(row) do copy[k] = v end
      local newId = species[i]
      if newId and newId ~= battle.rows[i].species then
        local slot = slotOf(newId)
        if slot then
          copy.species, copy.speciesId = slot, slot
          copy.nickname = nil
          if battle.rows[i].customMoves and A.Planner then
            copy.moves = A.builtSet(A.Planner, newId, battle.rows[i].level)
          else
            copy.moves = nil
          end
          copy.moveIds = nil
        end
      end
      local item = items and items[i]
      local num = item and A.itemNumber(item)
      if num then
        copy.heldItem, copy.heldItemId, copy.item = num, num, num
      end
      out[i] = copy
    end
    return out
  end

  return A
end
