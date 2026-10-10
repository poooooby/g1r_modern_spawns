-- Standalone: luajit mods/modern_spawns/tests/chain_test.lua (from the gen1recomp
-- root). The rules of src/chain.lua on their own, then -- when Pokemon FireRed is
-- imported under firered/ and mods/national_dex_gen3 is installed -- the chain end to
-- end: wild battles counted from the engine's events, the chained species swapped
-- into the encounters this mod rolls, and the exports a consumer uses.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Chain = H.module("src/chain.lua")

local function store()
  local t = {}
  return { get = function(k) return t[k] end, set = function(k, v) t[k] = v end, t = t }
end

-- ------- counting
do
  local s = store()
  local c = Chain.new(s)
  T.eq(c.species, nil, "a new save has no chain")
  c:record("PIDGEY", "win")
  T.check(c.species == "PIDGEY" and c.count == 1, "a win starts a chain at 1")
  c:record("PIDGEY", "caught")
  c:record("PIDGEY", "catch")
  T.eq(c.count, 3, "wins and catches of the same species add one each")
  c:record("RATTATA", "win")
  T.check(c.species == "RATTATA" and c.count == 1, "another species starts a new chain")
  c:record("PIDGEY", "run")
  T.eq(c.count, 1, "running from another species leaves the chain alone")
  c:record("RATTATA", "run")
  T.eq(c.species, nil, "running from the chained species ends it")
  for _ = 1, 150 do c:record("ZUBAT", "win") end
  T.eq(c.count, Chain.MAX, "the count stops at " .. Chain.MAX)
  T.check(s.t[Chain.SPECIES_KEY] == "ZUBAT" and s.t[Chain.COUNT_KEY] == Chain.MAX, "it is kept in the save")
  local again = Chain.new(s)
  T.check(again.species == "ZUBAT" and again.count == Chain.MAX, "...and read back")
  c:clear()
  T.check(c.species == nil and s.t[Chain.SPECIES_KEY] == "", "clear ends it (blacking out)")
  c:record(nil, "win")
  T.eq(c.species, nil, "an unknown species is ignored")
end

-- ------- more of it, shinier, better stats
do
  T.eq(Chain.forceChance(1), 0, "a chain of 1 changes nothing yet")
  T.eq(Chain.forceChance(2), 1 / 8, "at 2: 1 in 8")
  T.eq(Chain.forceChance(5), 1 / 5, "at 5: 1 in 5")
  T.eq(Chain.forceChance(9), 1, "from 9: every time")
  T.eq(Chain.forceChance(60), 1, "...and after")
  local c = Chain.new(store())
  for _ = 1, 9 do c:record("ODDISH", "win") end
  T.eq(c:forced(true, function() return 0.99 end), "ODDISH", "at 9 an encounter where it lives becomes it")
  T.eq(c:forced(false, function() return 0 end), nil, "...never where it cannot be met")
  local b = c:bonus("ODDISH")
  T.check(b and math.abs(b.shiny - (1 - (8191 / 8192) ^ 9)) < 1e-12, "shiny chance = 1 - (8191/8192)^9")
  T.eq(b.perfectIvs, 0, "no perfect stats below 10")
  T.eq(c:bonus("PIDGEY"), nil, "another species gets nothing")
  for _ = 1, 1 do c:record("ODDISH", "win") end
  T.eq(c:bonus("ODDISH").perfectIvs, 1, "1 perfect stat from 10")
  for _ = 1, 15 do c:record("ODDISH", "win") end
  T.eq(c:bonus("ODDISH").perfectIvs, 2, "2 from 25")
  for _ = 1, 15 do c:record("ODDISH", "win") end
  T.eq(c:bonus("ODDISH").perfectIvs, 3, "3 from 40")
  for _ = 1, 60 do c:record("ODDISH", "win") end
  local top = c:bonus("ODDISH")
  T.check(top.shiny > 1 / 90 and top.shiny < 1 / 75, "about 1 in 82 at 100 (" .. top.shiny .. ")")
end

-- ------- end to end on FireRed
local okData, data = pcall(H.gen3Data)
local ndex = io.open("mods/national_dex_gen3/manifest.json", "rb")
if ndex then ndex:close() end
if not (okData and type(data) == "table" and ndex) then
  print("skip: the end-to-end part needs FireRed imported and mods/national_dex_gen3")
else
  local Runtime = require("src.mods.Runtime")
  local P = data.gen3Pokemon
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" }, { data = data, generation = 3 })
  T.eq(#run.errors, 0, "loads clean on FireRed (" .. tostring(run.errors[1]) .. ")")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "KANTO" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  H.manager(loader)
  local api = loader.exports.modern_spawns
  T.check(type(api.chainBonus) == "function" and type(api.chainSpeciesFor) == "function"
    and type(api.chainRecord) == "function", "the chain exports are there")

  local mapId = "FR_ROUTE_1"
  local land = data.gen3Encounters[mapId].land
  local function encounter(slot, rng)
    return Runtime.call("encounter.species", function(e) return e end,
      { species = P.keyName(slot.species), speciesId = slot.species, level = slot.minLevel },
      { mapId = mapId, terrain = "land", rng = function() return rng or 4321 end })
  end
  -- the species this mod puts in Route 1's first land slot, as the engine's number
  local chained = encounter(land.slots[1]).species
  T.eq(type(chained), "number", "a Route 1 species (" .. tostring(chained) .. ")")

  local function battle(speciesId, result)
    loader.events:emit("battle.started", { kind = "wild", speciesId = speciesId })
    loader.events:emit("battle.ended", { result = result })
  end
  battle(chained, "win")
  T.eq(api.chain() and api.chain().count, 1, "a wild battle won starts the chain")
  battle(chained, "caught")
  T.eq(api.chain().count, 2, "...a catch adds one")
  loader.events:emit("battle.started", { kind = "trainer", speciesId = chained })
  loader.events:emit("battle.ended", { result = "win" })
  T.eq(api.chain().count, 2, "a trainer battle does not count")
  for _ = 1, 7 do battle(chained, "win") end
  T.eq(api.chain().count, 9, "nine in a row")

  -- every encounter on Route 1 becomes it now, whatever slot the game rolled
  local all = true
  for _, slot in ipairs(land.slots) do
    if encounter(slot).species ~= chained then all = false end
  end
  T.check(all, "at 9 every Route 1 encounter is the chained species")
  T.eq(api.chainSpeciesFor(mapId, "grass") ~= nil, true, "a visible spawn there is too")
  T.eq(api.chainSpeciesFor("FR_PALLET_TOWN", "grass"), nil, "...not where it cannot be met")
  local b = api.chainBonus(chained)
  T.check(b and b.shiny > 0 and b.perfectIvs == 0, "its bonus: a shiny chance, no perfect stats yet")
  T.eq(api.chainBonus(chained + 1), nil, "another species: none")
  api.chainRecord(chained, "win")
  T.eq(api.chainBonus(chained).perfectIvs, 1, "an overworld win counts (10: one perfect stat)")

  loader.events:emit("save.loaded", {})
  T.eq(api.chain().count, 10, "the chain survives a reload")
  battle(chained, "run")
  T.eq(api.chain(), nil, "running from it ends the chain")
  battle(chained, "win")
  loader.events:emit("world.blacked_out", {})
  T.eq(api.chain(), nil, "blacking out ends it")

  -- SHINY CHAINS off: nothing is counted or changed, and the chain is kept
  for _ = 1, 9 do battle(chained, "win") end
  T.eq(api.chain().count, 9, "a new chain of nine")
  loader.modOptions.modern_spawns.shiny_chain = "off"
  T.eq(api.settings().shinyChain, false, "settings() reports SHINY CHAINS off")
  battle(chained, "win")
  api.chainRecord(chained, "win")
  T.eq(api.chain().count, 9, "SHINY CHAINS off: nothing is counted")
  T.eq(api.chainBonus(chained), nil, "...no bonus")
  T.eq(api.chainSpeciesFor(mapId, "grass"), nil, "...no forced species on a visible spawn")
  local plain = 0
  for _, slot in ipairs(land.slots) do
    if encounter(slot).species == chained then plain = plain + 1 end
  end
  T.check(plain < #land.slots, "...and step encounters are the roster's own again")
  loader.modOptions.modern_spawns.shiny_chain = "on"
  T.check(api.chainBonus(chained) ~= nil and api.chain().count == 9, "back ON: the kept chain works again")
  battle(chained, "win")
  T.eq(api.chain().count, 10, "...and counts again")

  loader.modOptions.modern_spawns.enabled = "off"
  battle(chained, "win")
  T.eq(api.chainBonus(chained), nil, "MODERN SPAWNS off: no bonus")
  T.eq(api.chainSpeciesFor(mapId, "grass"), nil, "...and no forced species")
  run.release()
end

T.finish("modern_spawns chain")
