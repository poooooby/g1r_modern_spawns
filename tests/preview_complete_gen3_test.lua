-- Public encounter.table parity with COMPLETE's pools, including alternate
-- forms. Run from a Recomp checkout with imported Gen 3 data and both mods.
-- Optional: POKEPORT_VERSION, POKEPORT_GBA_CACHE, MODERN_SPAWNS_MOD_PATH,
-- NATIONAL_DEX_GEN3_MOD_PATH. No battle is rolled and no save is written.
local T = require("tests.modkit")
local version = os.getenv("POKEPORT_VERSION") or "firered"
local root = os.getenv("MODERN_SPAWNS_MOD_PATH") or "mods/modern_spawns"
local national = os.getenv("NATIONAL_DEX_GEN3_MOD_PATH") or "mods/national_dex_gen3"
local cacheRoot = os.getenv("POKEPORT_GBA_CACHE") or version .. "/data/generated/gba"
require("src.core.GameVersion").set(version)
require("src.import.gba.versions").select(version)
local Dataset = require("src.core.game3.dataset")
Dataset.cacheRootOverride = cacheRoot
Dataset.mountExtractRoots()
local P = require("src.core.game3.pokemon")
P.install(Dataset.cache())
require("src.core.game3.items_data").install(Dataset.cache())
local maps = Dataset.buildMaps()
local data = { maps = maps, tilesets = {}, gen3Pokemon = P,
  gen3Items = {_byId = assert(loadfile(cacheRoot .. "/items/pack.lua"))().items},
  gen3Moves = {_rom = assert(loadfile(cacheRoot .. "/pokemon/battle_moves.lua"))().moves},
  gen3Encounters = assert(loadfile(cacheRoot .. "/encounters.lua"))() }
local run = T.sdk.loadMods({national, root}, {data=data,generation=3})
assert(#run.errors == 0, "mods load cleanly")
local loader = run.loader
loader.modSave.modern_spawns = {seed="KANTO"}
loader.modOptions.modern_spawns = {enabled="on",max_generation="9",spawn_mode="complete"}
local game = {generation=3,data=data,save={options={}},mods=loader,writeOptions=function() end}
loader.game = game
require("src.mods.Gen3Compat").bind(function() return game end)
loader.events:emit("game.ready", {game=game})
loader.events:emit("save.loaded", {game=game})
local E = require("src.core.game3.encounters")
E._tables, E._loaded = data.gen3Encounters, true
local world = require("src.mods.UnifiedWorld").new(function() return game end,3,version,"preview_test")
local api = loader.exports.modern_spawns
local Json = require("src.link.Json")
local before = Json.encode(data.gen3Encounters)
local rng = require("src.core.game3.rng")
local random = rng.Random
rng.Random = function() error("preview consumed native RNG") end
local checked = 0
for mapId in pairs(maps) do
  for _, method in ipairs({{"land","grass",{20,20,10,10,10,10,5,5,4,4,1,1}},
                            {"water","water",{60,30,5,4,1}}}) do
    local info = assert(world:effectiveEncounters(mapId,method[2]))
    local table_ = api.tableFor(mapId,method[1])
    if table_ and info.chance > 0 then
      local pools, expected = api.poolFor(mapId,method[1]) or {}, {}
      for i, slot in ipairs(table_.slots) do
        local list = pools[i] or {slot.species}
        for _, id in ipairs(list) do
          local variants = (api.profileOf(id) or {}).variants or {}
          local share = method[3][i] / #list / (#variants + 1)
          expected[id] = (expected[id] or 0) + share
          for _, form in ipairs(variants) do expected[form] = (expected[form] or 0) + share end
        end
      end
      local total = 0
      for id, weight in pairs(expected) do
        assert(math.abs((info.dist[id] or 0)-weight)<1e-8,mapId.." preview missing/wrong "..id)
        total = total + weight
      end
      for id in pairs(info.dist) do assert(expected[id],mapId.." unexpected "..id) end
      assert(math.abs(total-100)<1e-8,"conditional weights total 100")
      checked = checked + 1
    end
  end
end
rng.Random = random
assert(before == Json.encode(data.gen3Encounters), "preview modified live slots")
run.release()
print("PASS COMPLETE public preview: "..version..", "..checked.." map/method distributions")
