-- How likely each species is on one map, method by method (exports.encounters,
-- the WoobNav). Pure: no engine, no RNG, no generator memory.
--
-- A slot's share of its table is its weight over the table's total weight
-- (the cart's own odds: Gen 1's /256 ladder, Gen 2's 30/30/20/10/5/4/1 and
-- 60/30/10 and fish rows, Gen 3's land/water/rod odds). Under COMPLETE that
-- share is split over the slot's pool exactly as the runtime draws from it
-- (runtime.lua poolPick): evenly, or by `weightOf` with TIME OF DAY SPAWNS on,
-- each member then raised to `floor` percent of the section where the pool's
-- share allows it (Rates.floored); when no member may come out, the slot's own
-- species keeps it. A look (Rotom's appliances) counts as its base species.
--
--   Rates.section({ slots, weights, indices?, pools?, weightOf?, floor?, baseOf? })
--     slots    generated (or the cart's) slots { species, level, maxLevel?, minLevel? }
--     weights  each slot's odds (same index)
--     indices  the slots of this section (default: all); a pool is looked up
--              by the slot's own index, so Gen 2's MORN/DAY/NITE blocks of one
--              flat table each read their own pools
--     pools    { [index] = { species ids } } (COMPLETE) or nil
--     weightOf fn(id) -> weight of a pool member (nil: every member alike)
--     floor    percent: with weightOf, no member that may come out gets less
--              than this of the section while its pool's share leaves room
--     spareOf  fn(index) -> the other time of day's primary at that slot: it
--              steps aside when the pool cannot keep everyone at `floor`
--     baseOf   fn(id) -> its base species when `id` is a look, else nil
--   -> { { id, chance (0-100), minLevel, maxLevel, pooled }, ... } most likely first
--
--   Rates.floored(weights, f, spare?) -> weights with every positive one at
--              least `f` (a fraction) of their sum; when that cannot hold for
--              all, the `spare` indices drop out first, then all are equal
--   Rates.text(chance) -> "35%", "<1%"

local Rates = {}

-- TIME OF DAY SPAWNS leans a pool 3:1 towards the species out at this hour.
-- COMPLETE sizes a pool so an even split keeps everyone at its minimum share,
-- and this keeps the lean from pushing anyone under it: each positive weight
-- is raised to `f` of the total and the rest share what is left by their own
-- weights. The weights come back unchanged when nobody is under `f`. When
-- `f` cannot hold for all of them, the `spare` ones (the other time of day's
-- primary: a small slot holds its day pick and its night pick) step aside
-- while someone else may still come out, and what is left is made equal.
function Rates.floored(ws, f, spare)
  if not f or f <= 0 then return ws end
  if spare and #spare > 0 then
    local n = 0
    for _, w in ipairs(ws) do if w > 0 then n = n + 1 end end
    if f * n > 1 + 1e-9 then
      local trimmed, left = {}, 0
      for i, w in ipairs(ws) do trimmed[i] = w end
      for _, i in ipairs(spare) do trimmed[i] = 0 end
      for _, w in ipairs(trimmed) do if w > 0 then left = left + 1 end end
      if left > 0 then return Rates.floored(trimmed, f) end
    end
  end
  local n, sum = 0, 0
  for _, w in ipairs(ws) do
    if w > 0 then n = n + 1; sum = sum + w end
  end
  if n == 0 then return ws end
  local low = false
  for _, w in ipairs(ws) do
    if w > 0 and w / sum < f - 1e-12 then low = true break end
  end
  if not low then return ws end
  local out = {}
  if f * n >= 1 - 1e-12 then
    for i, w in ipairs(ws) do out[i] = w > 0 and 1 or 0 end
    return out
  end
  local fixed = {}
  while true do
    local free, freeSum = 1, 0
    for i, w in ipairs(ws) do
      if w > 0 then
        if fixed[i] then free = free - f else freeSum = freeSum + w end
      end
    end
    local changed = false
    for i, w in ipairs(ws) do
      if w > 0 and not fixed[i] and w / freeSum * free < f - 1e-12 then
        fixed[i], changed = true, true
      end
    end
    if not changed then
      for i, w in ipairs(ws) do
        out[i] = w <= 0 and 0 or (fixed[i] and f or w / freeSum * free)
      end
      return out
    end
  end
end

local function levels(slot)
  local lo = tonumber(slot.minLevel or slot.level) or 0
  local hi = tonumber(slot.maxLevel or slot.level or slot.minLevel) or lo
  if hi < lo then lo, hi = hi, lo end
  return lo, hi
end

function Rates.section(args)
  local slots, weights = args.slots or {}, args.weights or {}
  local indices = args.indices
  if not indices then
    indices = {}
    for i = 1, #slots do indices[i] = i end
  end
  local total = 0
  for _, i in ipairs(indices) do
    if slots[i] then total = total + math.max(0, tonumber(weights[i]) or 0) end
  end
  local byId, out = {}, {}
  local function add(id, chance, slot, pooled)
    if id == nil or chance <= 0 then return end
    if args.baseOf then id = args.baseOf(id) or id end
    local lo, hi = levels(slot)
    local row = byId[id]
    if not row then
      row = { id = id, chance = 0, minLevel = lo, maxLevel = hi, pooled = pooled }
      byId[id] = row
      out[#out + 1] = row
    else
      row.minLevel, row.maxLevel = math.min(row.minLevel, lo), math.max(row.maxLevel, hi)
      -- a species that is some slot's own species is not "pooled" there
      row.pooled = row.pooled and pooled
    end
    row.chance = row.chance + chance
  end
  if total <= 0 then return out end
  for _, i in ipairs(indices) do
    local slot = slots[i]
    local w = slot and math.max(0, tonumber(weights[i]) or 0) or 0
    if w > 0 then
      local share = w * 100 / total
      local list = args.pools and args.pools[i]
      if type(list) == "table" and #list > 0 then
        local ws, sum = {}, 0
        for j, id in ipairs(list) do
          ws[j] = args.weightOf and math.max(0, tonumber(args.weightOf(id)) or 0) or 1
        end
        if args.weightOf and args.floor then
          -- the pool's share of this section: every slot here drawing from it
          local mine = 0
          for _, k in ipairs(indices) do
            if args.pools[k] == list and slots[k] then mine = mine + math.max(0, tonumber(weights[k]) or 0) end
          end
          local spare
          local other = args.spareOf and args.spareOf(i)
          if other ~= nil and other ~= slot.species then
            spare = {}
            for j, id in ipairs(list) do if id == other then spare[#spare + 1] = j end end
          end
          if mine > 0 then ws = Rates.floored(ws, args.floor * total / (100 * mine), spare) end
        end
        for j = 1, #list do sum = sum + ws[j] end
        if sum > 0 then
          for j, id in ipairs(list) do
            add(id, share * ws[j] / sum, slot, id ~= slot.species)
          end
        else
          add(slot.species, share, slot, false)
        end
      else
        add(slot.species, share, slot, false)
      end
    end
  end
  table.sort(out, function(a, b)
    if a.chance ~= b.chance then return a.chance > b.chance end
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

-- A chance as a person reads it: whole percent, "<1%" under one.
function Rates.text(chance)
  chance = tonumber(chance) or 0
  if chance > 0 and chance < 1 then return "<1%" end
  return ("%d%%"):format(math.min(100, math.floor(chance + 0.5)))
end

return Rates
