-- Standalone adapter regression; no imported game or running engine needed.
-- MODERN_SPAWNS_MOD_PATH may point at a checkout outside mods/modern_spawns.
local root = os.getenv("MODERN_SPAWNS_MOD_PATH") or "mods/modern_spawns"
local adapter = assert(loadfile(root .. "/src/adapters/gen2.lua"))()(
  { get = function() return {} end }, {}, {})
local table_ = { slots = { MORN = {}, DAY = {}, NITE = {} } }
for _, period in ipairs({ "MORN", "DAY", "NITE" }) do
  for i = 1, 7 do table_.slots[period][i] = { species = period } end
end
for _, period in ipairs({ "MORN", "DAY", "NITE" }) do
  assert(adapter.distribution(table_, "grass", { daytime = period })[period] == 100)
  assert(adapter.distribution(table_, "grass", { opts = { daytime = period } })[period] == 100)
end
assert(adapter.distribution(table_, "grass", { daytime = "DARK" }).NITE == 100)
assert(adapter.distribution(table_, "grass").DAY == 100)
print("PASS Gen 2 preview time-of-day selection")
