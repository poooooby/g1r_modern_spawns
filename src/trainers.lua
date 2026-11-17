-- TRAINER TEAMS planner (pure: never touches the engine).
--
-- A trainer IDENTITY (the rival across every fight, a gym leader and their
-- rematches, an Elite Four member's rounds) maps each of its original evolution
-- FAMILIES to one new family, drawn once per save from the seed; a battle then
-- shows each family at the stage its level allows. So the rival's Pidgey line
-- is, say, the Starly line in every fight -- Starly at 9, Staravia at 20 --
-- and a gym's every Pokemon keeps the gym's type.
--
-- The end-game facilities (Battle Frontier, Trainer Hill/Tower, Battle Towers)
-- draw from pools with their own "no two of one species" rules, so a facility
-- gets a ONE-TO-ONE species map (facilityMap): the facility's own draws then
-- land on exactly the same sets as the original game, only the species (and
-- moves, buildSet) differ.
--
-- ctx = { pool (species_pool.lua: list/byId), cap (1..9), seed, Rng,
--         config (Config.TrainerConfig), canShow(id, level)? }
-- Legendary and mythical species, and forms, are never picked.

local Trainers = {}

local function sortedKeys(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- Starter lines, by their first stage's national dex number (Bulbasaur ..
-- Quaxly): a starter line is replaced by a starter line where one fits.
Trainers.STARTERS = {}
for _, dex in ipairs({ 1, 4, 7, 152, 155, 158, 252, 255, 258, 387, 390, 393, 495, 498, 501,
                       650, 653, 656, 722, 725, 728, 810, 813, 816, 906, 909, 912 }) do
  Trainers.STARTERS[dex] = true
end

-- --------------------------------------------------------------- families

-- The family index over the candidate pool: each species' root, its children
-- (sorted), and which species may be shown under `cap`.
function Trainers.index(pool, cap)
  local byId = pool.byId
  local children, root = {}, {}
  for _, c in ipairs(pool.list) do
    if c.parent and byId[c.parent] then
      children[c.parent] = children[c.parent] or {}
      table.insert(children[c.parent], c.id)
    end
  end
  for _, list in pairs(children) do table.sort(list) end
  local function rootOf(id)
    local seen = 0
    while byId[id] and byId[id].parent and byId[byId[id].parent] and seen < 8 do
      id, seen = byId[id].parent, seen + 1
    end
    return id
  end
  local roots = {}
  for _, c in ipairs(pool.list) do
    root[c.id] = rootOf(c.id)
    roots[root[c.id]] = true
  end
  local function allowed(id)
    local c = byId[id]
    return c ~= nil and c.gen <= cap and not c.special and not (c.form or c.baseSpecies)
  end
  -- a family is usable when any member may be shown
  local usable = {}
  for _, c in ipairs(pool.list) do
    if allowed(c.id) then usable[root[c.id]] = true end
  end
  return { byId = byId, children = children, root = root, allowed = allowed,
           roots = sortedKeys(roots), usable = usable }
end

local function typesOf(c)
  return c and c.types or {}
end

local function sharedTypes(a, b)
  local n = 0
  for t in pairs(a) do if b[t] then n = n + 1 end end
  return n
end

-- The stage a family shows at `level`, never below `minStage` (the stage of
-- the Pokemon it replaces): evolutions by level at their level, the others
-- at config stage2_level / stage3_level. `branch(nodeId, n)` picks among
-- several children (Eevee, Wurmple) the same way every time. nil when the
-- family has nothing allowed.
function Trainers.stageFor(ix, config, rootId, level, minStage, branch)
  local byId = ix.byId
  local cur = rootId
  -- a root above the cap (Pichu under GEN 1): start at its first allowed descendant
  local guard = 0
  while cur and not ix.allowed(cur) and guard < 4 do
    local kids = {}
    for _, k in ipairs(ix.children[cur] or {}) do kids[#kids + 1] = k end
    if #kids == 0 then return nil end
    cur = kids[#kids == 1 and 1 or branch(cur, #kids, kids)]
    guard = guard + 1
  end
  if not cur or not ix.allowed(cur) then return nil end
  minStage = minStage or 1
  for _ = 1, 4 do
    local kids = {}
    for _, k in ipairs(ix.children[cur] or {}) do
      if ix.allowed(k) then kids[#kids + 1] = k end
    end
    if #kids == 0 then break end
    local child = byId[kids[#kids == 1 and 1 or branch(cur, #kids, kids)]]
    local gate = child.evolveLevel
      or ((child.stage or 2) <= 2 and config.stage2_level or config.stage3_level)
    local stage = byId[cur].stage or 1
    if level >= gate or stage < minStage then
      cur = child.id
    else
      break
    end
  end
  return cur
end

local function softmaxPick(scored, top, temperature, rng)
  table.sort(scored, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.id < b.id
  end)
  local weights, best = {}, scored[1].score
  for i = 1, math.min(#scored, top) do
    weights[i] = math.exp((scored[i].score - best) / temperature)
  end
  return scored[rng:weighted(weights) or 1]
end

-- ----------------------------------------------------------- identities

-- One identity's family map: { [original root] = new root }.
--   appearances: { { species = id, level = n }, ... } over every battle of
--                this identity (so the map never depends on fight order)
--   gymType:     a type every Pokemon shown must have (gym leaders, Elite Four)
function Trainers.planIdentity(ctx, ix, identity, appearances, gymType)
  local config, Rng = ctx.config, ctx.Rng
  local byRoot = {}
  for _, a in ipairs(appearances) do
    local c = ix.byId[a.species]
    if c then
      local r = ix.root[c.id]
      byRoot[r] = byRoot[r] or {}
      table.insert(byRoot[r], { level = a.level, stage = c.stage or 1, species = c.id })
    end
  end
  -- a branching family takes one branch per identity; a gym's, one of its type
  -- where there is one (Karen's Eevee is an Umbreon)
  local function branchFor(nodeId, n, kids)
    local rng = Rng.new(Rng.hash(ctx.seed, ctx.cap, "trainers", identity, "branch", nodeId))
    if gymType and kids then
      local fitting = {}
      for i, k in ipairs(kids) do
        if ix.byId[k] and ix.byId[k].types[gymType] then fitting[#fitting + 1] = i end
      end
      if #fitting > 0 then return fitting[rng:int(1, #fitting)] end
    end
    return rng:int(1, n)
  end

  local map, used = {}, {}
  for _, original in ipairs(sortedKeys(byRoot)) do
    local apps = byRoot[original]
    local originalTypes = {}
    for _, a in ipairs(apps) do
      for t in pairs(typesOf(ix.byId[a.species])) do originalTypes[t] = true end
    end
    local starter = Trainers.STARTERS[ix.byId[original] and ix.byId[original].dex or -1]
    local tiers = { {}, {}, {} }
    for _, family in ipairs(ix.roots) do
      -- a gym may keep an original family of its type when too few others
      -- have it (Kanto alone has one Ghost line); anyone else always changes
      local keep = family == original
      if (not keep or gymType) and ix.usable[family] and not used[family] then
        local ok, gymOk, bstGap, shownTypes = true, true, 0, {}
        for _, a in ipairs(apps) do
          local id = Trainers.stageFor(ix, config, family, a.level, a.stage, branchFor)
          if not id or (ctx.canShow and not ctx.canShow(id, a.level)) then ok = false break end
          local c = ix.byId[id]
          for t in pairs(c.types) do shownTypes[t] = true end
          if gymType and not c.types[gymType] then gymOk = false end
          bstGap = bstGap + math.abs((c.bst or 0) - (ix.byId[a.species].bst or 0))
        end
        if ok then
          local shared = sharedTypes(shownTypes, originalTypes)
          local score = shared * config.type_weight + (bstGap / #apps) * config.bst_per_point
          if starter and Trainers.STARTERS[ix.byId[family].dex or -1] then
            score = score + config.starter
          end
          local entry = { id = family, score = score + (keep and config.keep_penalty or 0) }
          if gymType then
            if gymOk then table.insert(tiers[1], entry) end
          elseif shared > 0 then
            table.insert(tiers[1], entry)
          end
          if not keep then
            if shared > 0 then table.insert(tiers[2], entry) end
            table.insert(tiers[3], entry)
          end
        end
      end
    end
    local pick
    for _, tier in ipairs(tiers) do
      if #tier > 0 then
        local rng = Rng.new(Rng.hash(ctx.seed, ctx.cap, "trainers", identity, original))
        pick = softmaxPick(tier, config.top, config.temperature, rng).id
        break
      end
    end
    pick = pick or original
    map[original] = pick
    used[pick] = true
  end
  return { map = map, branch = branchFor }
end

-- A battle's new species for an identity's plan: rows { { species, level } }
-- -> { new id or the original }.
function Trainers.team(ctx, ix, plan, rows)
  local out = {}
  for i, row in ipairs(rows) do
    local c = ix.byId[row.species]
    local newId
    if c then
      local family = plan.map[ix.root[c.id]]
      if family then
        newId = Trainers.stageFor(ix, ctx.config, family, row.level, c.stage or 1, plan.branch)
      end
    end
    out[i] = newId or row.species
  end
  return out
end

-- ----------------------------------------------------------- facilities

-- A ONE-TO-ONE map for one facility's species: { [original] = new }. Every
-- original gets a distinct species, so the facility's "no two of a species"
-- draws behave exactly as they do with the original pool. Replacements are
-- drawn only from species OUTSIDE the facility's own, so an original that
-- finds nothing left (a low GENERATIONS cap) keeps itself without ever
-- colliding: one-to-one by construction. `levelOf(id)` is the level the
-- species is shown at (canShow checks it).
function Trainers.facilityMap(ctx, ix, name, originals, levelOf)
  local rules, Rng = ctx.config.facility, ctx.Rng
  local list = {}
  for id in pairs(originals) do list[#list + 1] = id end
  table.sort(list)
  local targets = {}
  for _, c in ipairs(ctx.pool.list) do
    if ix.allowed(c.id) and not originals[c.id] then targets[#targets + 1] = c end
  end
  local used, map, shown = {}, {}, {}
  -- canShow per (species, level), asked once each (it scans a learnset)
  local function canShow(id, level)
    if not ctx.canShow then return true end
    local key = id .. "@" .. level
    local v = shown[key]
    if v == nil then
      v = ctx.canShow(id, level) and true or false
      shown[key] = v
    end
    return v
  end
  for _, original in ipairs(list) do
    local o = ix.byId[original]
    local level = levelOf and levelOf(original) or 50
    local scored = {}
    if o then
      local oFinal = not ix.children[o.id]
      for _, c in ipairs(targets) do
        if not used[c.id] and canShow(c.id, level) then
          local score = sharedTypes(c.types, o.types) * rules.type_weight
            + math.abs((c.bst or 0) - (o.bst or 0)) * rules.bst_per_point
          if oFinal and not ix.children[c.id] then score = score + rules.final end
          scored[#scored + 1] = { id = c.id, score = score }
        end
      end
    end
    local pick = original
    if #scored > 0 then
      local rng = Rng.new(Rng.hash(ctx.seed, ctx.cap, "trainers", "facility", name, original))
      pick = softmaxPick(scored, rules.top, rules.temperature, rng).id
      used[pick] = true
    end
    map[original] = pick
  end
  return map
end

-- ------------------------------------------------------------- movesets

-- Status moves a built set may carry (one at most), by engine move name.
Trainers.STATUS_MOVES = {}
for _, name in ipairs({ "TOXIC", "THUNDER_WAVE", "WILL_O_WISP", "SLEEP_POWDER", "SPORE",
    "HYPNOSIS", "STUN_SPORE", "SWORDS_DANCE", "CALM_MIND", "DRAGON_DANCE", "BULK_UP",
    "NASTY_PLOT", "AGILITY", "RECOVER", "SOFTBOILED", "MILK_DRINK", "SLACK_OFF", "ROOST",
    "MOONLIGHT", "SYNTHESIS", "MORNING_SUN", "REST", "CONFUSE_RAY", "LEECH_SEED",
    "AMNESIA", "BARRIER", "IRON_DEFENSE", "SUBSTITUTE", "PROTECT", "DOUBLE_TEAM" }) do
  Trainers.STATUS_MOVES[name] = true
end
local SKIP = { SELFDESTRUCT = true, SELF_DESTRUCT = true, EXPLOSION = true, SOLAR_BEAM = true,
               SOLARBEAM = true, SKY_ATTACK = true, RAZOR_WIND = true, SKULL_BASH = true,
               DIG = true, FLY = true, DIVE = true, BOUNCE = true, HYPER_BEAM = true,
               FOCUS_PUNCH = true, DREAM_EATER = true, SNORE = true }

-- Four moves for a species at `level` from its own level-up moves: its best
-- same-type attacks first (one per type), one attack of another type, one
-- status move, then the next best, then its other moves. learnset: { { level, move } }; info(move)
-- -> { name, type, power, accuracy } or nil. Returns { moves } (move ids as
-- the learnset gives them), nil when nothing is learnable.
function Trainers.buildSet(learnset, level, types, info)
  local seen, attacks, status, others = {}, {}, {}, {}
  for _, row in ipairs(learnset or {}) do
    local move = row.move
    if (row.level or 1) <= level and move ~= nil and not seen[move] then
      seen[move] = true
      local m = info(move)
      if m and not SKIP[m.name or ""] then
        local power = tonumber(m.power) or 0
        if power > 1 then
          local value = power * ((tonumber(m.accuracy) or 100) / 100)
          if types[m.type] then value = value * 1.5 end
          attacks[#attacks + 1] = { move = move, value = value, type = m.type, stab = types[m.type] == true }
        elseif Trainers.STATUS_MOVES[m.name or ""] then
          status[#status + 1] = { move = move, name = m.name }
        else
          others[#others + 1] = { move = move, level = row.level or 1 }
        end
      end
    end
  end
  if #attacks == 0 and #status == 0 and #others == 0 then return nil end
  table.sort(attacks, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return tostring(a.move) < tostring(b.move)
  end)
  table.sort(status, function(a, b) return tostring(a.move) < tostring(b.move) end)
  local out, taken, coveredTypes = {}, {}, {}
  local function take(entry)
    if entry and not taken[entry.move] and #out < 4 then
      taken[entry.move] = true
      out[#out + 1] = entry.move
      if entry.type then coveredTypes[entry.type] = true end
      return true
    end
    return false
  end
  -- the best same-type attack of each of its types
  for _, a in ipairs(attacks) do
    if a.stab and not coveredTypes[a.type] then take(a) end
  end
  -- one attack of a type it does not cover yet
  for _, a in ipairs(attacks) do
    if not coveredTypes[a.type] then take(a) break end
  end
  take(status[1])
  for _, a in ipairs(attacks) do take(a) end
  for _, s in ipairs(status) do take(s) end
  -- nothing better (Ditto, Togetic): its other moves, the latest learned first
  table.sort(others, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return tostring(a.move) < tostring(b.move)
  end)
  for _, o in ipairs(others) do take(o) end
  return out
end

return Trainers
