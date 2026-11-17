-- TRAINER TEAMS in Crystal's Battle Tower.
--
-- The tower draws its opponents from one roster (BattleTower.roster): level
-- groups of ready-made Pokemon. With TRAINER TEAMS on, that roster answers
-- with a copy whose species follow a ONE-TO-ONE map for the save (so the
-- tower's own "no two of a species, no two of an item, nothing from the last
-- two teams" draws pick exactly the rows they always did), each changed row
-- with a moveset built for its new species and no stored stats (Mon.new works
-- them out). Items stay the set's own.
--
-- Engine modules outlive a mod reload, so the wrapper is installed once and
-- re-pointed on every load (BattleTower.__modernSpawnsTrainers); any error, or
-- TRAINER TEAMS OFF, answers the original roster.

local function engine(name)
  local ok, module = pcall(require, name)
  return ok and type(module) == "table" and module or nil
end

return function(deps)
  local Planner, adapter = deps.Planner, deps.adapter
  local F = {}
  local TR, active = nil, false
  local cached = setmetatable({}, { __mode = "k" })

  function F.bind(trainerRuntime) TR = trainerRuntime end
  function F.sync(on) active = on end

  -- the roster with its species remapped, or nil (leave it as it is)
  function F.remap(roster)
    if not (active and TR and type(roster) == "table" and type(roster.groups) == "table") then return nil end
    local st = TR.state()
    if not st then return nil end
    local held = cached[roster]
    if held and held.key == st.key then return held.roster end
    local originals, levelOf = {}, {}
    for _, group in pairs(roster.groups) do
      for _, row in ipairs(group) do
        if type(row) == "table" and type(row.species) == "string" then
          originals[row.species] = true
          levelOf[row.species] = math.max(levelOf[row.species] or 0, tonumber(row.level) or 50)
        end
      end
    end
    local map = Planner.facilityMap(st.ctx, st.ix, "crystal_battle_tower", originals,
                                    function(id) return levelOf[id] end)
    st.facilityMaps.crystal_battle_tower = map
    local copy = {}
    for k, v in pairs(roster) do copy[k] = v end
    copy.groups = {}
    for g, group in pairs(roster.groups) do
      local rows = {}
      for i, row in ipairs(group) do
        local newSpecies = type(row) == "table" and map[row.species]
        if newSpecies and newSpecies ~= row.species then
          local r = {}
          for k, v in pairs(row) do r[k] = v end
          r.species = newSpecies
          r.moves = adapter.builtSet(Planner, newSpecies, tonumber(row.level) or 50)
          r.pp, r.stats, r.maxHp, r.hp, r.experience = nil, nil, nil, nil, nil
          rows[i] = r
        else
          rows[i] = row
        end
      end
      copy.groups[g] = rows
    end
    cached[roster] = { key = st.key, roster = copy }
    return copy
  end

  local BattleTower = engine("src.core.gen2.BattleTower")

  -- facility name -> { [original species] = its replacement }, or nil
  function F.species(name)
    if name ~= "crystal_battle_tower" or not (active and TR and BattleTower) then return nil end
    local st = TR.state()
    if not st then return nil end
    local data = deps.mod.game and deps.mod.game.data
    pcall(BattleTower.roster, data)
    return st.facilityMaps.crystal_battle_tower
  end

  if BattleTower then
    BattleTower.__modernSpawnsTrainers = F.remap
    if not BattleTower.__modernSpawnsTrainersWrapped then
      BattleTower.__modernSpawnsTrainersWrapped = true
      local original = BattleTower.roster
      BattleTower.roster = function(data)
        local roster = original(data)
        local remap = BattleTower.__modernSpawnsTrainers
        if remap then
          local ok, out = pcall(remap, roster)
          if ok and out then return out end
        end
        return roster
      end
    end
  end

  return F
end
