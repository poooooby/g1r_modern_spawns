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
  local ALGO = 3 -- bump when a change would hand existing saves different teams

  local TR = {}
  local unwrap
  local cache = { key = nil }
  local identities -- the cart's trainer data, read once

  local function mode() return Config.trainerTeams(mod) end

  -- The generation cap in force, or nil (OFF, or no species at all).
  function TR.cap()
    if mode() == "off" then return nil end
    local pool = Runtime.pool()
    if not pool or #pool.list == 0 then return nil end
    return math.min(Config.maxGeneration(mod), Runtime.poolMaxGeneration())
  end

  function TR.invalidate() cache = { key = nil } end

  local function state()
    local cap = TR.cap()
    if not cap then return nil end
    local seed = Runtime.seed()
    local key = table.concat({ seed, cap, Runtime.dataVersion(), ALGO }, ":")
    if cache.key == key then return cache end
    local pool = Runtime.pool()
    local ctx = { pool = pool, cap = cap, seed = seed, Rng = Rng, config = Config.TrainerConfig,
                  canShow = adapter.canShow }
    cache = { key = key, ctx = ctx, ix = Planner.index(pool, cap), plans = {}, facilityMaps = {} }
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
                                identity == "rival" or info.rival == true)
    st.plans[identity] = plan
    return plan
  end

  -- ON + ITEMS: one item name (or nil) per slot. The game's own held items
  -- are kept (nil); a boss's highest-level Pokemon is its ace.
  local function itemsFor(st, battle, species)
    if mode() ~= "items" or not adapter.itemAvailable then return nil end
    local ace, aceLevel = nil, -1
    for i, row in ipairs(battle.rows) do
      if row.level >= aceLevel then ace, aceLevel = i, row.level end
    end
    local maxGen = math.max(st.ctx.cap, adapter.cartGeneration or 1)
    local used, out = {}, {}
    for i, row in ipairs(battle.rows) do
      if row.item then used[row.item] = true end
    end
    for i, row in ipairs(battle.rows) do
      if not row.item then
        local c = st.ix.byId[species[i]]
        if c then
          local canEvolve = false
          for _, child in ipairs(st.ix.children[c.id] or {}) do
            if st.ix.allowed(child) then canEvolve = true break end
          end
          local role = battle.boss and (i == ace and "ace" or "boss") or "ordinary"
          local name = Items.choose({
            role = role, slot = i,
            mon = { types = c.types, canEvolve = canEvolve,
                    moves = adapter.movesFor and adapter.movesFor(c.id, row.level) or {} },
            stats = adapter.statsOf and adapter.statsOf(c.id) or {},
            maxGen = maxGen, available = adapter.itemAvailable, used = used,
            rng = Rng.new(Rng.hash(st.ctx.seed, st.ctx.cap, "trainers", "items", battle.key, i)),
            chance = Config.TrainerConfig.ordinary_item_chance,
          })
          if name then
            used[name] = true
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
      { appearances = battle.rows, gymType = battle.gymType, rival = battle.rival })
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
