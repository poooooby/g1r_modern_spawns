-- TRAINER TEAMS wiring: the option, the generation cap, the save's seed, the
-- trainer.party hook and the facility wrappers.
--
-- Independent of MODERN SPAWNS (the wild tables): it follows GENERATIONS and
-- the save's seed only. The hook is wrapped only while TRAINER TEAMS is ON,
-- and unwrapped when it goes OFF: on Gen 3 any wrapper at all routes every
-- battle through the engine's mod path, so OFF must leave no wrapper behind.
-- Plans are kept per (seed, cap, data version) and drawn per identity the
-- first time one of its battles starts.

return function(deps)
  local mod, Config, Rng, Runtime, Planner, Items, adapter =
    deps.mod, deps.Config, deps.Rng, deps.Runtime, deps.Planner, deps.Items, deps.adapter
  local facilities = deps.facilities
  local log = mod.log
  local HOOK_PRIORITY = -100
  local ALGO = 4 -- bump when a change would hand existing saves different teams

  local TR = {}
  local unwrap
  local cache = { key = nil }
  local identities -- the cart's trainer data, read once

  local function mode() return Config.trainerTeams(mod) end

  -- The generations in force (a Config.genSet), or nil (OFF, no species at
  -- all, or none of the picked generations registered). MODERN SPAWNS
  -- doesn't matter. Its key is "N" for Gen 1-N, as the old single cap.
  function TR.generations()
    if mode() == "off" then return nil end
    return Runtime.registeredGenerations()
  end

  -- The highest generation in force, or nil.
  function TR.cap()
    local gs = TR.generations()
    return gs and gs.max or nil
  end

  function TR.invalidate() cache = { key = nil } end

  local function state()
    local gs = TR.generations()
    if not gs then return nil end
    local seed = Runtime.seed()
    local key = table.concat({ seed, gs.key, Runtime.dataVersion(), ALGO }, ":")
    if cache.key == key then return cache end
    local pool = Runtime.pool()
    -- cap carries the key into every RNG hash ("N" hashes as the number did)
    local ctx = { pool = pool, cap = gs.key, gens = gs.has, maxGen = gs.max, seed = seed, Rng = Rng,
                  config = Config.TrainerConfig, canShow = adapter.canShow }
    cache = { key = key, ctx = ctx, ix = Planner.index(pool, gs.key, gs.has), plans = {}, facilityMaps = {} }
    return cache
  end
  TR.state = state

  local function identityInfo(identity)
    if not identities then
      local ok, result = pcall(adapter.identities)
      identities = ok and result or {}
      if not ok then log:warn("trainer teams: the trainer data could not be read (%s)", tostring(result)) end
    end
    return identities[identity]
  end

  local function planFor(st, identity, fallback)
    local plan = st.plans[identity]
    if plan then return plan end
    local info = identityInfo(identity) or fallback
    plan = Planner.planIdentity(st.ctx, st.ix, identity, info.appearances, info.gymType,
                                identity == "rival" or info.rival == true,
                                info.team and Planner.TEAM_THEMES[info.team] or nil)
    st.plans[identity] = plan
    return plan
  end

  -- How far into the game a battle is, by its ace's level (Config items):
  -- "early", "mid" or "late".
  local function stageOf(level)
    local rules = Config.TrainerConfig.items
    if level >= rules.late_level then return "late" end
    if level >= rules.mid_level then return "mid" end
    return "early"
  end

  -- Who holds an item in a battle (ON + ITEMS), scaled to how far into the
  -- game it is and how big a battle it is: { [slot] = { role, strong } }.
  -- The Elite Four, champions and the rival's final battle: everyone, any
  -- item. Another major battle (a boss): its ace always, its others by
  -- chance. An ordinary trainer: none early, then one or two. The rival's
  -- first battle: none. Seeded per battle, so a battle always looks the same.
  local function holdersOf(st, battle, ace, aceLevel)
    local rules = Config.TrainerConfig.items
    local stage = stageOf(aceLevel)
    local rng = Rng.new(Rng.hash(st.ctx.seed, st.ctx.cap, "trainers", "items", battle.key, "held"))
    local info = identityInfo(battle.identity)
    local rival = battle.identity == "rival" or battle.rival or (info and info.rival)
    local full = battle.elite == true
    if rival and info and info.firstTop and info.lastTop and info.firstTop < info.lastTop then
      if aceLevel <= info.firstTop then return {} end
      if aceLevel >= info.lastTop then full = true end
    end
    local out = {}
    if full then
      for i in ipairs(battle.rows) do out[i] = { role = i == ace and "ace" or "boss", strong = true } end
      return out
    end
    if battle.boss then
      out[ace] = { role = stage == "early" and "basic" or "ace", strong = stage == "late" }
      for i in ipairs(battle.rows) do
        if i ~= ace and rng:next() < (rules.others[stage] or 0) then
          out[i] = { role = "boss", strong = stage == "late" }
        end
      end
      return out
    end
    -- an ordinary trainer: a few items at most, its strongest Pokemon first;
    -- the ones it already held in the game count
    local want = rules.ordinary[stage] or 0
    local count = math.floor(want)
    if rng:next() < want - count then count = count + 1 end
    local order = {}
    for i in ipairs(battle.rows) do order[#order + 1] = i end
    table.sort(order, function(a, b)
      if battle.rows[a].level ~= battle.rows[b].level then return battle.rows[a].level > battle.rows[b].level end
      return a < b
    end)
    for _, i in ipairs(order) do
      if battle.rows[i].item then count = count - 1 end
    end
    for _, i in ipairs(order) do
      if count <= 0 then break end
      if not battle.rows[i].item then
        out[i] = { role = "basic", strong = false }
        count = count - 1
      end
    end
    return out
  end

  -- ON + ITEMS: one item name (or nil) per slot. The game's own held items
  -- are kept (nil); a battle's highest-level Pokemon is its ace.
  local function itemsFor(st, battle, species)
    if mode() ~= "items" or not adapter.itemAvailable then return nil end
    local ace, aceLevel = nil, -1
    for i, row in ipairs(battle.rows) do
      if row.level >= aceLevel then ace, aceLevel = i, row.level end
    end
    local holders = holdersOf(st, battle, ace, aceLevel)
    -- items of the generations in force, and always the cart's own
    local cartGen = adapter.cartGeneration or 1
    local gens = {}
    for g in pairs(st.ctx.gens) do gens[g] = true end
    for g = 1, cartGen do gens[g] = true end
    local maxGen = math.max(st.ctx.maxGen, cartGen)
    -- no two of an item on one team, by the game's item number where it has one:
    -- two names can be one item (Gen 2's MIRACLEBERRY is Emerald's Lum Berry)
    local function itemKey(name)
      local num = adapter.itemNumber and adapter.itemNumber(name)
      return num or name
    end
    local used, taken, out = {}, {}, {}
    for i, row in ipairs(battle.rows) do
      if row.item then
        used[row.item] = true
        taken[itemKey(row.item)] = true
      end
    end
    local function available(name)
      return not taken[itemKey(name)] and adapter.itemAvailable(name)
    end
    for i, row in ipairs(battle.rows) do
      local holder = holders[i]
      if holder and not row.item then
        local c = st.ix.byId[species[i]]
        if c then
          local canEvolve = #st.ix.next(c.id) > 0
          local name = Items.choose({
            role = holder.role, strong = holder.strong, slot = i,
            mon = { types = c.types, canEvolve = canEvolve,
                    moves = adapter.movesFor and adapter.movesFor(c.id, row.level) or {} },
            stats = adapter.statsOf and adapter.statsOf(c.id) or {},
            maxGen = maxGen, gens = gens, available = available, used = used,
            rng = Rng.new(Rng.hash(st.ctx.seed, st.ctx.cap, "trainers", "items", battle.key, i)),
          })
          if name then
            used[name] = true
            taken[itemKey(name)] = true
            out[i] = name
          end
        end
      end
    end
    return out
  end

  -- The new party for a battle, or nil to leave it as it is.
  function TR.party(class, id, party)
    local st = state()
    if not st then return nil end
    local battle = adapter.read(class, id, party)
    if not battle then return nil end
    local plan = planFor(st, battle.identity,
      { appearances = battle.rows, gymType = battle.gymType, rival = battle.rival, team = battle.team })
    local species = Planner.team(st.ctx, st.ix, plan, battle.rows)
    -- a two-opponent battle: a row of the other trainer follows that trainer's plan
    for i, row in ipairs(battle.rows) do
      if row.identity and row.identity ~= battle.identity then
        local other = planFor(st, row.identity, { appearances = { row } })
        species[i] = Planner.team(st.ctx, st.ix, other, { row })[1]
      end
    end
    return adapter.write(party, battle, species, itemsFor(st, battle, species), st)
  end

  -- the moves a species' held item is chosen by (exports._trainerMovesFor)
  function TR.movesFor(id, level)
    return adapter.movesFor and adapter.movesFor(id, level) or nil
  end

  -- who a battle's trainer is (rematches share one identity), or nil
  function TR.identity(class, id, party)
    local battle = adapter.read(class, id, party)
    return battle and battle.identity or nil
  end

  -- a facility's species map ({ [original] = replacement }), or nil
  function TR.facilitySpecies(name)
    if not (facilities and facilities.species) or not state() then return nil end
    return facilities.species(name)
  end

  local function onParty(nextFn, class, id, party, ...)
    local out = nextFn(class, id, party, ...)
    local ok, replaced = pcall(TR.party, class, id, out)
    if ok and type(replaced) == "table" and #replaced > 0 then return replaced end
    if not ok then
      log:warn("trainer teams: %s %s keeps its own team (%s)", tostring(class), tostring(id),
        tostring(replaced))
    end
    return out
  end

  -- Wrap the hook while ON, unwrap it while OFF; the facilities likewise.
  function TR.sync()
    local on = mode() ~= "off"
    if on and not unwrap then
      unwrap = mod.hooks:wrap("trainer.party", onParty, HOOK_PRIORITY)
    elseif not on and unwrap then
      pcall(unwrap)
      unwrap = nil
    end
    if facilities then pcall(facilities.sync, on) end
  end

  function TR.install()
    TR.sync()
    Runtime.onInvalidate(TR.invalidate)
    mod.events:on("mod.options_changed", function(ev)
      if type(ev) == "table" and ev.mod == mod.id then
        TR.invalidate()
        TR.sync()
      end
    end)
  end

  return TR
end
