# Modern Spawns: developer guide

For mod authors and contributors. Players only need the [README](README.md).

## Tests

Suites run from the gen1recomp root with the mod linked at `mods/modern_spawns`:

```sh
luajit mods/modern_spawns/tests/<name>_test.lua
```

Most need an imported game (Red under `red/`, FireRed under `firered/`, Gold under `gold/`)
and, for Gen 3, `mods/national_dex_gen3`. `tests/rse_test.lua` runs against Ruby, Sapphire
and Emerald directly. Every test, fixture and the data generator are listed by exact path in
`.modkitignore` so none of them ships.

Keep [README.md](README.md) describing the mod as it is now (players read it); what changed
goes in [CHANGELOG.md](CHANGELOG.md).

## API (`mod.exports`)

```lua
local spawns = mod:find("modern_spawns")
if spawns and (spawns.exports.apiVersion or 0) >= 1 and spawns.exports.isActive() then
  local grass = spawns.exports.tableFor("ROUTE_1", "grass")  -- { rate, slots, buckets? }
end
```

`apiVersion` is 2. It goes up only when an existing export changes meaning (2: `isActive()` is
true on GEN 1 and with only the cart's own species, and `maxGeneration()` can answer 1); added
exports don't bump it, so test for a newer one by presence,
`type(exports.chainBonus) == "function"`.

| Export | Returns |
|---|---|
| `isActive()` | whether generated tables are in use: MODERN SPAWNS ON and at least one species registered (the cart's own count) |
| `generation()` | `1` (Red/Blue/Yellow), `2` (Gold/Silver/Crystal) or `3` (FireRed/LeafGreen/Ruby/Sapphire/Emerald): which shapes the table functions return |
| `maxGeneration()` | the generation cap in force, or nil |
| `settings()` | `{ enabled, maxGeneration, spawnMode, legendaries, shinyChain }` as the player set them |
| `spawnMode()` | `"seeded"` (LIMITED), `"map"`, `"random"` or `"complete"`; under RANDOM there is no fixed table, so `tableFor` / `superRodFor` / `explain` return nil |
| `seed()` / `setSeed(text)` / `rerollSeed()` | read or change the loaded save's seed |
| `legendaryHomes()` | `{ [mapId] = { grass = { {id, score, category} }, water = … } }`: where legendaries would appear |
| `tableFor(mapId, terrain)` | the generated grass / indoor / water table (copy) in the running game's own shape, or nil. Gen 1: `{ rate, slots, buckets? }`. Gen 2 grass: `{ map, rates, slots = { MORN, DAY, NITE } }`; Gen 2 water: `{ map, rate, slots }` |
| `superRodFor(mapId)` | the Super Rod catches (copy): Gen 1 `{ { species, level } }`, Gen 2 fish rows `{ { chance, species, level } }`; or nil |
| `poolFor(mapId, terrain)` | COMPLETE only: `{ [slot] = { species ids } }`, what each slot can turn into (its own species first); nil in other modes |
| `locate(speciesId)` | `{ [mapId] = { land/grass/water = true } }`: where a species can be met under the current settings (empty under RANDOM, nil while inactive). What the Gen 3 Pokédex AREA page shows |
| `drawFor(mapId, terrain)` | for a mod that picks species itself, once per pick (visible overworld spawns): `tableFor` under LIMITED / EVERY MAP, a fresh one-off draw under RANDOM |
| `legendaryFor(mapId, terrain)` | the LEGENDARIES roll for such a pick: a hosted, not-yet-owned legendary (1/1024) or mythical (1/2048) id, or nil |
| `chain()` | the current shiny chain `{ species, count }`, or nil |
| `chainSpeciesFor(mapId, terrain)` | for such a pick: the chained species when the chain makes this encounter it (rolled here), else nil |
| `chainBonus(species)` | for an encounter of `species` (an id or the engine's number): `{ shiny = chance 0..1, perfectIvs = 0..3 }`, or nil. The consumer makes it shiny and sets the stats |
| `chainRecord(species, result)` | count a fight that wasn't a real battle (an overworld companion's): `"win"` / `"catch"` extend the chain, `"run"` ends it |
| `explain(mapId, terrain)` | per-slot records: species, replaced, score, reasons, penalties |
| `candidates(opts)` | the candidate pool, filterable by generation, terrain, level range and habitat |
| `profileOf(speciesId)` | one species' spawn profile |
| `invalidate()` | drop cached tables |

Every return value is a copy. The event `mod.modern_spawns.tables_changed` fires whenever
tables are regenerated. Modern Spawns wraps `encounter.roll`, `encounter.fishing`,
`encounter.table` and `encounter.species` as the innermost wrapper (priority -100), so its
tables are what the engine rolls; outer mods can still suppress an encounter or post-process
it through `encounter.species`.

A mod that suppresses step encounters and picks species itself (visible overworld spawns)
bypasses those hooks: it should read `drawFor`, `legendaryFor` and `chainSpeciesFor` per
pick (Wilds of Kanto Revival and Wilds of Hoenn do).

For a mod that can't call anything (a wild-encounter guide reading
`game.data.encounters` / `gen2Encounters` / `gen3Encounters` directly, like Kanto Gear's),
**live sync** writes the generated species into those tables too, restored on OFF. Its gaps:
under RANDOM the live tables hold one snapshot per map visit; under EVERY MAP only visited maps
are synced; and if another mod writes the same tables, the last writer wins.

## How species are chosen

The game's own tables are the skeleton; only data the game lacks is added.

- **From the running game:** each map's rate, slot levels, odds ladder and Super Rod groups;
  the tileset; which species are registered; their dex number, types and base stats; and
  evolution links (the ROM's own, plus the dex mod's for later species).
- **Shipped with the mod:** `data/spawn_profiles.lua`, built from PokéAPI's wild-encounter
  data: each species' usual wild level range, habitats, terrains, rarity and
  legendary/mythical status. Species with no wild data (all of Gen 9) get an estimated
  profile from evolution stage, base stats and types.

Slots that held the same species form a *role*, and each role gets one new species, scored on
level fit (and not below its evolution level), terrain and habitat fit, sharing types with the
species it replaces or the map's theme, rarity against the role's share of the odds, and
penalties for repeats within the map and the previous few maps. Legendaries never enter a
table: each gets up to two home maps (levels 30+, fitting terrain, habitat or theme), at most
three per table, rolled after the game's own encounter. COMPLETE gives each slot a small pool
(its LIMITED species first, up to 6, under 3 on average) so every species under the cap lives
somewhere. Gen 2 replaces a species across morning, day and night at once, keeping night-only
roles nocturnal. On Gen 3 the engine rolls its own table regardless, so the species is swapped
right after the roll, at the rolled level. Tuning numbers live in `SpawnConfig`
([src/config.lua](src/config.lua)); shiny chains are [src/chain.lua](src/chain.lua).

## Regenerating the profile data

```bash
cd pokemon_spawn_generator
python -m pip install requests
python generate_spawn_data.py --lua ../data/spawn_profiles.lua
```

See [pokemon_spawn_generator/README.md](pokemon_spawn_generator/README.md).
