-- TRAINER TEAMS in the Gen 3 battle facilities:
--   * Emerald's Battle Frontier and Battle Tents: the `mons`, `brains` and
--     `tents` packs every facility reads (D.pack), and the Battle Pyramid's
--     and Battle Pike's wild Pokemon;
--   * Emerald's Trainer Hill (Hill.trainer);
--   * Ruby and Sapphire's Battle Tower (its pack's mons50 / mons100);
--   * FireRed and LeafGreen's Trainer Tower (Tower.buildEnemyParty).
--
-- Each facility gets a ONE-TO-ONE species map for the save (Planner.facilityMap),
-- so its own "no two of a species, no two of an item" draws pick exactly the
-- sets they always did: the Dome's brackets, the Factory's rentals, hints and
-- swaps and the battles all agree, and nothing can hang. A changed set keeps
-- its item, nature, EVs and IVs and gets a moveset built from its new
-- species' level-up moves; Pyramid and Pike Pokemon keep up to two of their
-- status moves (their floors' themes). Left alone: record-mixed players,
-- apprentices, secret bases, e-Reader trainers and link battles.
--
-- Engine modules outlive a mod reload, so each wrapper is installed once and
-- re-pointed on every load; any error, or TRAINER TEAMS OFF, answers the
-- engine's own result.

local SET_LEVEL = 100 -- facility sets are level-free: the species' whole level-up list

local function engine(name)
  local ok, module = pcall(require, name)
  return ok and type(module) == "table" and module or nil
end

local function shallow(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

return function(deps)
  local Planner, adapter = deps.Planner, deps.adapter
  local F = {}
  local TR, active = nil, false

  function F.bind(trainerRuntime) TR = trainerRuntime end
  function F.sync(on) active = on end

  local function state()
    if active and TR then return TR.state() end
    return nil
  end

  local function versionKey()
    local GameVersion = engine("src.core.GameVersion")
    local ok, v = pcall(function() return GameVersion.get() end)
    return ok and tostring(v) or "?"
  end

  -- facility name -> { bySlot = { [slot] = { slot, id } }, sets = {} }, per
  -- save state and cart. collect(add) hands every species slot to add();
  -- `keep` lists slots the engine's own draws single out (they stay as they
  -- are, and nothing becomes them).
  local function facilityMap(st, name, collect, keep)
    local key = name .. ":" .. versionKey()
    local held = st.facilityMaps[key]
    if held then return held end
    local slots = {}
    for slot in pairs(keep or {}) do slots[slot] = true end
    collect(function(slot)
      slot = tonumber(slot)
      if slot and slot > 0 then slots[slot] = true end
    end)
    local originals = {}
    for slot in pairs(slots) do
      local id = adapter.speciesIdOf(slot)
      if id then originals[id] = true end
    end
    local idMap = Planner.facilityMap(st.ctx, st.ix, name, originals, function() return SET_LEVEL end)
    local m = { bySlot = {}, sets = {}, ids = idMap }
    for slot in pairs(keep or {}) do
      local id = adapter.speciesIdOf(slot)
      if id then idMap[id] = id end
    end
    for from, to in pairs(idMap) do
      if to ~= from then
        local fromSlot, toSlot = adapter.slotOf(from), adapter.slotOf(to)
        if fromSlot and toSlot then m.bySlot[fromSlot] = { slot = toSlot, id = to } end
      end
    end
    st.facilityMaps[key] = m
    return m
  end
  F.facilityMap = facilityMap

  local function setFor(m, id)
    local s = m.sets[id]
    if s == nil then
      s = adapter.builtSet(Planner, id, SET_LEVEL) or false
      m.sets[id] = s
    end
    return s or nil
  end

  local function copyList(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
  end

  -- a set row with its species swapped and its moves built, or nil (unchanged)
  local function remapSet(m, row)
    local to = type(row) == "table" and m.bySlot[tonumber(row.species) or -1]
    if not to then return nil end
    local r = shallow(row)
    r.species = to.slot
    local moves = setFor(m, to.id)
    if moves and #moves > 0 then r.moves = copyList(moves) end
    return r, to
  end

  local function remapList(m, list)
    local out = {}
    for k, row in pairs(list or {}) do out[k] = remapSet(m, row) or row end
    return out
  end

  -- one remapped copy per engine table and save state
  local copies = setmetatable({}, { __mode = "k" })
  local function cachedCopy(original, st, build)
    local held = copies[original]
    if held and held.key == st.key then return held.copy end
    local copy = build()
    copies[original] = { key = st.key, copy = copy }
    return copy
  end

  local function rows(list, add)
    for _, row in pairs(list or {}) do
      if type(row) == "table" then add(row.species) end
    end
  end

  -- up to two of the old status moves (a Pyramid floor's or Pike room's
  -- theme), then the built set
  local function keepStatus(old, built)
    local out, seen = {}, {}
    for _, mv in ipairs(old or {}) do
      local info = adapter.moveInfo(mv)
      if info and (tonumber(info.power) or 0) == 0 and #out < 2 and not seen[mv] then
        out[#out + 1], seen[mv] = mv, true
      end
    end
    for _, mv in ipairs(built or {}) do
      if #out < 4 and not seen[mv] then out[#out + 1], seen[mv] = mv, true end
    end
    return out
  end

  local function abilityFor(slot, abilityNum)
    local Pokemon = engine("src.core.game3.pokemon")
    local ok, pair = pcall(function() return Pokemon.abilities(slot) end)
    pair = ok and type(pair) == "table" and pair or {}
    local num = (tonumber(pair[2]) or 0) ~= 0 and (tonumber(abilityNum) or 0) % 2 or 0
    return num, pair[num + 1] or pair[1] or 0
  end

  -- ------------------------------------------------------------ installing

  -- Wrap module[name] once per engine module; `after(result, ...args)`
  -- answers a replacement or nil. Re-pointed on every load.
  local function wrapOnce(module, name, after)
    if not module or type(module[name]) ~= "function" and not module["__modernSpawnsOriginal_" .. name] then
      return
    end
    local slot, orig = "__modernSpawnsTrainers_" .. name, "__modernSpawnsOriginal_" .. name
    module[slot] = after
    if module[orig] then return end
    module[orig] = module[name]
    module[name] = function(...)
      local out = module[orig](...)
      local fn = module[slot]
      if fn then
        local ok, new = pcall(fn, out, ...)
        if ok and new ~= nil then return new end
      end
      return out
    end
  end

  -- ------------------------------------------------------------ Emerald Frontier

  local D = engine("src.core.game3.rse.frontier.trainers")
  local Pyramid = engine("src.core.game3.rse.frontier.pyramid")
  local Pike = engine("src.core.game3.rse.frontier.pike")

  -- the Factory never draws an Unown set
  local function unownSlot()
    local ok, slot = pcall(function() return D.constants():require("species", "SPECIES_UNOWN") end)
    return ok and tonumber(slot) or 201
  end

  local function frontierMap(st)
    return facilityMap(st, "emerald_frontier", function(add)
      local pack = D and (D.__modernSpawnsOriginal_pack or D.pack)
      pcall(function() rows(pack("mons").mons, add) end)
      pcall(function()
        for _, symbols in pairs(pack("brains").mons or {}) do
          for _, list in pairs(symbols) do rows(list, add) end
        end
      end)
      pcall(function()
        for _, tent in pairs(pack("tents")) do
          if type(tent) == "table" then rows(tent.mons, add) end
        end
      end)
      pcall(function()
        local man = Pyramid.manifest()
        for _, key in ipairs({ "wildMons50", "wildMonsOpen" }) do
          for _, round in pairs(man[key] or {}) do rows(round, add) end
        end
      end)
      pcall(function()
        for _, lists in pairs(Pike.manifest().wildMons or {}) do
          for _, header in pairs(lists) do rows(header, add) end
        end
      end)
    end, { [unownSlot()] = true })
  end
  F.frontierMap = function()
    local st = state()
    return st and frontierMap(st) or nil
  end

  local PACKS = { mons = true, brains = true, tents = true }
  function F.remapPack(pack, name)
    if not PACKS[name] or type(pack) ~= "table" then return nil end
    local st = state()
    if not st then return nil end
    return cachedCopy(pack, st, function()
      local m = frontierMap(st)
      local copy = shallow(pack)
      if name == "mons" then
        copy.mons = remapList(m, pack.mons)
      elseif name == "brains" then
        copy.mons = {}
        for facility, symbols in pairs(pack.mons or {}) do
          local s = {}
          for symbol, list in pairs(symbols) do s[symbol] = remapList(m, list) end
          copy.mons[facility] = s
        end
      else
        for k, tent in pairs(pack) do
          if type(tent) == "table" and type(tent.mons) == "table" then
            local t = shallow(tent)
            t.mons = remapList(m, tent.mons)
            copy[k] = t
          end
        end
      end
      return copy
    end)
  end

  -- a wild Pokemon of the Pyramid ({ species, moves, personality, ability... })
  function F.pyramidWild(enc)
    local st = state()
    if not (st and type(enc) == "table") then return nil end
    local m = frontierMap(st)
    local to = m.bySlot[tonumber(enc.species) or -1]
    if not to then return nil end
    local out = shallow(enc)
    out.species = to.slot
    out.moves = keepStatus(enc.moves, setFor(m, to.id))
    out.abilityNum, out.ability = abilityFor(to.slot, tonumber(enc.personality) or 0)
    return out
  end

  -- a wild Pokemon of the Pike (the encounter, with level, moves and ability)
  function F.pikeWild(enc)
    local st = state()
    if not (st and type(enc) == "table") then return nil end
    local m = frontierMap(st)
    local to = m.bySlot[tonumber(enc.species) or -1]
    if not to then return nil end
    local out = shallow(enc)
    out.species = to.slot
    out.moves = keepStatus(enc.moves, setFor(m, to.id))
    out.abilityNum, out.ability = abilityFor(to.slot, enc.abilityNum)
    return out
  end

  if D then wrapOnce(D, "pack", function(pack, name) return F.remapPack(pack, name) end) end
  if Pyramid then wrapOnce(Pyramid, "generateWildMon", function(enc) return F.pyramidWild(enc) end) end
  if Pike then wrapOnce(Pike, "tryGenerateWildMon", function(enc) return F.pikeWild(enc) end) end

  -- ------------------------------------------------------------ Trainer Hill

  local Hill = engine("src.core.game3.rse.trainer_hill")

  local function hillMap(st)
    return facilityMap(st, "trainer_hill", function(add)
      pcall(function()
        for _, challenge in pairs(Hill.manifest().challenges or {}) do
          for _, floor in pairs(challenge.floors or {}) do
            for _, trainer in pairs(floor.trainers or {}) do rows(trainer.mons, add) end
          end
        end
      end)
    end)
  end

  function F.hillTrainer(trainer)
    if type(trainer) ~= "table" or type(trainer.mons) ~= "table" then return nil end
    local st = state()
    if not st then return nil end
    return cachedCopy(trainer, st, function()
      local m = hillMap(st)
      local copy = shallow(trainer)
      copy.mons = {}
      for k, mon in pairs(trainer.mons) do
        local r = remapSet(m, mon)
        if r then r.nickname = "" end -- its new species' own name
        copy.mons[k] = r or mon
      end
      return copy
    end)
  end

  if Hill then wrapOnce(Hill, "trainer", function(t) return F.hillTrainer(t) end) end

  -- ------------------------------------------------------------ Ruby / Sapphire Battle Tower

  local RsTower = engine("src.core.game3.rse.battle_tower_rs")

  function F.rsTowerPack(pack)
    if type(pack) ~= "table" or type(pack.mons50) ~= "table" and type(pack.mons100) ~= "table" then return nil end
    local st = state()
    if not st then return nil end
    return cachedCopy(pack, st, function()
      local m = facilityMap(st, "rs_battle_tower", function(add)
        rows(pack.mons50, add)
        rows(pack.mons100, add)
      end)
      local copy = shallow(pack)
      if pack.mons50 then copy.mons50 = remapList(m, pack.mons50) end
      if pack.mons100 then copy.mons100 = remapList(m, pack.mons100) end
      return copy
    end)
  end

  if RsTower then wrapOnce(RsTower, "pack", function(pack) return F.rsTowerPack(pack) end) end

  -- ------------------------------------------------------------ FireRed / LeafGreen Trainer Tower

  local Tower = engine("src.core.game3.trainer_tower")

  local function towerMap(st)
    return facilityMap(st, "frlg_trainer_tower", function(add)
      pcall(function()
        local pack = Tower.pack()
        for _, floors in pairs(type(pack) == "table" and pack.floors or {}) do
          for _, floor in pairs(floors) do
            for _, trainer in pairs(type(floor) == "table" and floor.trainers or {}) do
              rows(trainer.mons, add)
            end
          end
        end
      end)
    end)
  end

  -- the tower's built enemy party (fresh tables each time; e-Reader trainers
  -- go through Tower.ereaderFoe and stay as printed on their cards)
  function F.towerParty(mons)
    if type(mons) ~= "table" then return nil end
    local st = state()
    if not st then return nil end
    local m = towerMap(st)
    local out = {}
    for i, mon in ipairs(mons) do
      local r, to = remapSet(m, mon)
      if r then
        r.nickname = nil
        r.abilityNum = (abilityFor(to.slot, mon.abilityNum))
      end
      out[i] = r or mon
    end
    return out
  end

  if Tower then wrapOnce(Tower, "buildEnemyParty", function(mons) return F.towerParty(mons) end) end

  -- ------------------------------------------------------------ the maps, for the API

  -- facility name -> { [original species] = its replacement }, or nil
  F.NAMES = { "emerald_frontier", "trainer_hill", "rs_battle_tower", "frlg_trainer_tower" }
  function F.species(name)
    local st = state()
    if not st then return nil end
    local m
    if name == "emerald_frontier" and D then
      m = frontierMap(st)
    elseif name == "trainer_hill" and Hill then
      m = hillMap(st)
    elseif name == "frlg_trainer_tower" and Tower then
      m = towerMap(st)
    elseif name == "rs_battle_tower" and RsTower then
      pcall(RsTower.pack)
      m = st.facilityMaps["rs_battle_tower:" .. versionKey()]
    end
    if not (m and next(m.bySlot)) then return nil end -- nothing to remap: no such facility
    return m.ids
  end

  return F
end
