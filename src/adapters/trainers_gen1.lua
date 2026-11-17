-- TRAINER TEAMS on Red, Blue and Yellow: the trainer data, who is who, and the
-- trainer.party hook's shape.
--
-- Trainers are classes (OPP_BROCK) with parties ({ { species, level } }); the
-- hook gets (class, party index, the party's data rows) and must never change
-- those shared rows: it answers with new ones. Gym leaders' and the Elite
-- Four's signature moves (applySpecialMoves, after the hook) still apply: the
-- gym's type is kept, so they fit. Red/Blue/Yellow have no held items.

return function(reg)
  local A = { generation = 1, cartGeneration = 1 }

  -- Gym leaders and the Elite Four keep their type for every Pokemon
  A.GYM_TYPES = {
    OPP_BROCK = "ROCK", OPP_MISTY = "WATER", OPP_LT_SURGE = "ELECTRIC", OPP_ERIKA = "GRASS",
    OPP_KOGA = "POISON", OPP_SABRINA = "PSYCHIC", OPP_BLAINE = "FIRE", OPP_GIOVANNI = "GROUND",
    OPP_LORELEI = "ICE", OPP_BRUNO = "FIGHTING", OPP_AGATHA = "GHOST", OPP_LANCE = "DRAGON",
  }
  local RIVAL = { OPP_RIVAL1 = true, OPP_RIVAL2 = true, OPP_RIVAL3 = true }

  -- One identity per trainer that should look the same across fights: the
  -- rival (every fight, every starter), each gym leader / Elite Four member;
  -- everyone else is their own class and party.
  function A.identityOf(class, partyIndex)
    if RIVAL[class] then return "rival" end
    if A.GYM_TYPES[class] then return class end
    return class .. "#" .. tostring(partyIndex)
  end

  local function rowsOf(party)
    local rows = {}
    for i, slot in ipairs(party or {}) do
      if type(slot) ~= "table" or type(slot.species) ~= "string" then return nil end
      rows[i] = { species = slot.species, level = tonumber(slot.level) or 5 }
    end
    return #rows > 0 and rows or nil
  end

  -- Every identity's Pokemon over all its battles: { [identity] = {
  -- appearances = { {species, level} }, gymType, boss } }.
  function A.identities()
    local out = {}
    for _, class in ipairs(reg.ids("trainers")) do
      local record = reg.get("trainers", class)
      for i, party in ipairs(type(record) == "table" and record.parties or {}) do
        local rows = rowsOf(party)
        if rows then
          local id = A.identityOf(class, i)
          local info = out[id] or { appearances = {}, gymType = A.GYM_TYPES[class],
                                    boss = A.GYM_TYPES[class] ~= nil or RIVAL[class] == true }
          out[id] = info
          for _, r in ipairs(rows) do info.appearances[#info.appearances + 1] = r end
        end
      end
    end
    return out
  end

  -- This battle as the planner sees it, or nil (not a party this mod knows).
  function A.read(class, partyIndex, party)
    if type(class) ~= "string" then return nil end
    local rows = rowsOf(party)
    if not rows then return nil end
    return { identity = A.identityOf(class, partyIndex), key = class .. "#" .. tostring(partyIndex),
             gymType = A.GYM_TYPES[class], boss = A.GYM_TYPES[class] ~= nil or RIVAL[class] == true,
             rows = rows }
  end

  -- New rows (the data rows are shared: never changed in place).
  function A.write(party, battle, species)
    local out = {}
    for i, slot in ipairs(party) do
      local row = {}
      for k, v in pairs(slot) do row[k] = v end
      row.species = species[i] or slot.species
      out[i] = row
    end
    return out
  end

  -- Pokemon.new needs the species' level-1 moves and learnset
  function A.canShow(id)
    local rec = reg.get("pokemon", id)
    return type(rec) == "table" and type(rec.level1Moves) == "table" and type(rec.learnset) == "table"
  end

  function A.itemAvailable() return false end

  return A
end
