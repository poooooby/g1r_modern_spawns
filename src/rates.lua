-- How likely each species is on one map, method by method (exports.encounters,
-- the WoobNav). Pure: no engine, no RNG, no generator memory.
--
-- A slot's share of its table is its weight over the table's total weight
-- (the cart's own odds: Gen 1's /256 ladder, Gen 2's 30/30/20/10/5/4/1 and
-- 60/30/10 and fish rows, Gen 3's land/water/rod odds). Under COMPLETE that
-- share is split over the slot's pool exactly as the runtime draws from it
-- (runtime.lua poolPick): evenly, or by `weightOf` with TIME OF DAY SPAWNS on;
-- when no member may come out, the slot's own species keeps it. A look
-- (Rotom's appliances) counts as its base species.
--
--   Rates.section({ slots, weights, indices?, pools?, weightOf?, baseOf? })
--     slots    generated (or the cart's) slots { species, level, maxLevel?, minLevel? }
--     weights  each slot's odds (same index)
--     indices  the slots of this section (default: all); a pool is looked up
--              by the slot's own index, so Gen 2's MORN/DAY/NITE blocks of one
--              flat table each read their own pools
--     pools    { [index] = { species ids } } (COMPLETE) or nil
--     weightOf fn(id) -> weight of a pool member (nil: every member alike)
--     baseOf   fn(id) -> its base species when `id` is a look, else nil
--   -> { { id, chance (0-100), minLevel, maxLevel, pooled }, ... } most likely first
--
--   Rates.text(chance) -> "35%", "<1%"

local Rates = {}

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
          sum = sum + ws[j]
        end
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
