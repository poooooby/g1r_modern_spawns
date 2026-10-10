-- Shiny chains: beat or catch one species again and again and it is met more
-- often, is more likely to be shiny and has better stats. The idea comes from
-- TTiN and Untamed Tohjo (used with permission); this is our own take on it.
--
--   chain       one species and a count (1..MAX), saved with the game. A wild
--               battle won or caught adds one when it is the same species and
--               starts a new chain at 1 when it is not; running from the
--               chained species or blacking out ends it.
--   more of it  when the chained species can be met where an encounter
--               happens, the encounter becomes it with chance
--               1 / (10 - min(count, 9)): 1 in 8 at 2, every time from 9.
--   shiny       1 - (8191/8192)^count: what `count` separate 1/8192 rolls
--               would give, as one chance.
--   stats       IV_FLOOR perfect stats (applied by the game-family mod).
--
-- Pure: the save store and the RNG are passed in. Species are this mod's ids
-- ("PIDGEY"); runtime.lua converts engine numbers before they get here.

local Chain = {}

Chain.MAX = 100
Chain.SPECIES_KEY, Chain.COUNT_KEY = "chain/species", "chain/count"
-- { count reached, perfect stats }, highest first
Chain.IV_FLOOR = { { 40, 3 }, { 25, 2 }, { 10, 1 } }

--- `store` = { get(key), set(key, value) } (mod.save).
function Chain.new(store)
  local self = setmetatable({ store = store }, { __index = Chain })
  self:load()
  return self
end

--- Re-read the saved chain (a save loaded, a checkpoint restored).
function Chain:load()
  local species = self.store and self.store.get(Chain.SPECIES_KEY)
  local count = tonumber(self.store and self.store.get(Chain.COUNT_KEY)) or 0
  if type(species) ~= "string" or species == "" or count < 1 then species, count = nil, 0 end
  self.species, self.count = species, math.min(Chain.MAX, math.floor(count))
end

function Chain:_save()
  if not self.store then return end
  self.store.set(Chain.SPECIES_KEY, self.species or "")
  self.store.set(Chain.COUNT_KEY, self.count)
end

function Chain:clear()
  if self.species == nil and self.count == 0 then return end
  self.species, self.count = nil, 0
  self:_save()
end

--- A wild battle against `species` ended with `result` (the engine's word:
--- "win", "catch" / "caught", "run", ...).
function Chain:record(species, result)
  if type(species) ~= "string" or species == "" then return end
  if result == "win" or result == "catch" or result == "caught" then
    if species == self.species then
      self.count = math.min(Chain.MAX, self.count + 1)
    else
      self.species, self.count = species, 1
    end
    self:_save()
  elseif result == "run" and species == self.species then
    self:clear()
  end
end

--- Chance that an encounter where the chained species can be met becomes it.
function Chain.forceChance(count)
  if (count or 0) < 2 then return 0 end
  return 1 / (10 - math.min(count, 9))
end

--- The chained species when this encounter becomes it, else nil. `canMeet`
--- is true when that species can be met here; `rng()` is a 0..1 draw.
function Chain:forced(canMeet, rng)
  if not (self.species and canMeet) then return nil end
  if rng() < Chain.forceChance(self.count) then return self.species end
  return nil
end

--- What an encounter of `species` gets from the chain: { shiny = chance,
--- perfectIvs = n }, or nil when it is not the chained species.
function Chain:bonus(species)
  if not (self.species and species == self.species and self.count > 0) then return nil end
  local perfect = 0
  for _, step in ipairs(Chain.IV_FLOOR) do
    if self.count >= step[1] then perfect = step[2] break end
  end
  return { shiny = 1 - (8191 / 8192) ^ self.count, perfectIvs = perfect, count = self.count }
end

return Chain
