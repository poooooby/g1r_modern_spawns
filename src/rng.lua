-- Deterministic PRNG and string hash for table generation.
--
-- Pure Lua arithmetic on doubles, no bit library and no love.math: the same
-- (seed, map, settings) must produce the same table on every platform and in
-- the headless test runner. Park-Miller "minimal standard" (multiplier 48271,
-- modulus 2^31-1) keeps every intermediate product below 2^53, so it is exact
-- in double precision. Never used for anything gameplay-random at roll time --
-- the engine's own RNG still decides whether and which slot is rolled.

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647 -- 2^31 - 1
local MUL = 48271

local function normalise(seed)
  seed = math.floor(tonumber(seed) or 0) % MOD
  if seed <= 0 then seed = seed + 1234567 end
  return seed
end

-- A stable 31-bit hash of any number of values (strings, numbers, booleans).
function Rng.hash(...)
  local h = 5381
  for i = 1, select("#", ...) do
    local text = tostring((select(i, ...)))
    for j = 1, #text do
      h = (h * 33 + text:byte(j)) % MOD
    end
    -- field separator so ("ab", "c") and ("a", "bc") differ
    h = (h * 33 + 31) % MOD
  end
  return normalise(h)
end

function Rng.new(seed)
  local self = setmetatable({ state = normalise(seed) }, Rng)
  -- the first outputs of a Lehmer generator track the seed closely; burn a few
  for _ = 1, 4 do self:next() end
  return self
end

-- Uniform float in [0, 1).
function Rng:next()
  self.state = (self.state * MUL) % MOD
  return (self.state - 1) / (MOD - 1)
end

-- Uniform integer in [lo, hi].
function Rng:int(lo, hi)
  return lo + math.floor(self:next() * (hi - lo + 1))
end

-- Index into `weights` (a list of non-negative numbers) chosen with
-- probability proportional to its weight; nil when every weight is zero.
function Rng:weighted(weights)
  local total = 0
  for _, w in ipairs(weights) do total = total + w end
  if total <= 0 then return nil end
  local target = self:next() * total
  local running = 0
  for i, w in ipairs(weights) do
    running = running + w
    if target < running then return i end
  end
  return #weights
end

return Rng
