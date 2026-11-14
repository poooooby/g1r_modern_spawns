# WoobleSpawns: developer guide

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
| `settings()` | `{ enabled, maxGeneration, spawnMode, legendaries, shinyChain, timeOfDay }` as the player set them (`timeOfDay`: `"off"`, `"prefer"` or `"strict"`) |
| `period()` | `"day"` or `"night"` on the clock TIME OF DAY SPAWNS follows (WoobleDex's Clock Source on Ruby/Sapphire/Emerald, the device's on FireRed/LeafGreen and Red/Blue/Yellow, the cart's on Gold/Silver/Crystal), whatever the option is set to; nil without a clock |
| `spawnMode()` | `"seeded"` (LIMITED), `"map"`, `"random"` or `"complete"`; under RANDOM there is no fixed table, so `tableFor` / `superRodFor` / `explain` return nil |
| `seed()` / `setSeed(text)` / `rerollSeed()` | read or change the loaded save's seed |
| `legendaryHomes()` | `{ [mapId] = { grass = { {id, score, category} }, water = … } }`: where legendaries would appear |
| `tableFor(mapId, terrain, period?)` | the generated grass / indoor / water table (copy) in the running game's own shape, or nil. Gen 1: `{ rate, slots, buckets? }`. Gen 2 grass: `{ map, rates, slots = { MORN, DAY, NITE } }`; Gen 2 water: `{ map, rate, slots }`. With TIME OF DAY SPAWNS on, `period` (`"day"`/`"night"`) picks that roster, by default the one in force now; OFF has one roster and ignores it |
| `superRodFor(mapId)` | the Super Rod catches (copy): Gen 1 `{ { species, level } }`, Gen 2 fish rows `{ { chance, species, level } }`, Gen 3 `{ rate, slots = { { species, minLevel, maxLevel } } }`; or nil |
| `poolFor(mapId, terrain, period?)` | COMPLETE only (terrain `land`/`grass`, `water`, and on Gen 3 `fish.good`/`fish.super`): `{ [slot] = { species ids } }`, what each slot can turn into (its main species first, the cart's own species for the slot last); nil in other modes. With TIME OF DAY SPAWNS on, what it can turn into at `period` (STRICT leaves out species that only come out at the other time), that period's main species first |
| `locate(speciesId)` | `{ [mapId] = { land/grass/water = true } }`: where a species can be met under the current settings (empty under RANDOM, nil while inactive). What the Gen 3 Pokédex AREA page shows |
| `drawFor(mapId, terrain, period?)` | for a mod that picks species itself, once per pick (visible overworld spawns): `tableFor` under LIMITED / EVERY MAP, a fresh one-off draw under RANDOM; `period` as for `tableFor` |
| `legendaryFor(mapId, terrain)` | the LEGENDARIES roll for such a pick: a hosted, not-yet-owned legendary (1/1024) or mythical (1/2048) id once the League is beaten, or nil |
| `chain()` | the current shiny chain `{ species, count }`, or nil |
| `chainSpeciesFor(mapId, terrain)` | for such a pick: the chained species when the chain makes this encounter it (rolled here), else nil |
| `chainBonus(species)` | for an encounter of `species` (an id or the engine's number): `{ shiny = chance 0..1, perfectIvs = 0..3 }`, or nil. The consumer makes it shiny and sets the stats |
| `chainRecord(species, result)` | count a fight that wasn't a real battle (an overworld companion's): `"win"` / `"catch"` extend the chain, `"run"` ends it |
| `explain(mapId, terrain, period?)` | per-slot records: species, replaced, score, reasons, penalties (`period` as for `tableFor`) |
| `candidates(opts)` | the candidate pool, filterable by generation, terrain, level range and habitat |
| `profileOf(speciesId)` | one species' spawn profile (with `candidates`: `timeOfDay` `"day"`/`"night"`/nil, and `timeOfDayOnly` when it only comes out then) |
| `invalidate()` | drop cached tables |

Every return value is a copy. The event `mod.modern_spawns.tables_changed` fires whenever
tables are regenerated, and `mod.modern_spawns.period_changed { period, previous }` when TIME OF
DAY SPAWNS sees the clock turn (a mod holding visible spawns can redraw them). WoobleSpawns wraps `encounter.roll`, `encounter.fishing`,
`encounter.table` and `encounter.species` as the innermost wrapper (priority -100), so its
tables are what the engine rolls; outer mods can still suppress an encounter or post-process
it through `encounter.species` (see "Changing species on top" below).

### Changing species on top (randomizers)

A mod that replaces the species WoobleSpawns chose needs no export: wrap the hooks at any
priority above -100 and edit what `next` returns. `tests/compose_test.lua` holds this contract
on Emerald in every SPAWN MODE.

- `encounter.species(next, encounter, ctx)`: call `next(encounter, ctx)` first, then change the
  result. On Gen 3 its `species` is the engine's numeric slot and `speciesId` the same number
  (the engine's own unhooked result has `species` as a name, e.g. `"ZIGZAGOON"`, so read
  `tonumber(r.speciesId) or tonumber(r.species)`); hand back a numeric `species`. `ctx` has
  `mapId` and `terrain`.
- `encounter.fishing(next, rod, mapId, candidates)`: `next(rod, mapId, candidates)` returns the
  ONE rolled encounter (`{ species, speciesId, level, ... }`), not the list; change that. The
  Old Rod passes through WoobleSpawns untouched.
- Copy the table before changing it, and keep `level` and the other fields.
- Visible spawns don't run these hooks: Wilds of Hoenn applies WoobleSpawns' species and then
  its own `addSpawnFilter` filters, so register one there too.

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
penalties for repeats within the map and the previous few maps. A map's habitats and theme
types come from [src/map_context.lua](src/map_context.lua): its tileset or map type, plus
keyword rules on the map id for named places in every region (Mt. Pyre is ruins + GHOST, the
Lost Cave cave + GHOST). On a themed map (a theme type, or a place habitat such as cave,
forest, ruins, snow, desert, mountain, water or coast) the strict tier only takes species that
share a theme type or a place habitat; a thin tier widens as before. A shared "route" or
"general" tag is only a weak hint (`habitat_generic`), since nearly every species has one.
Legendaries never enter a table: each gets up to two home maps (levels 30+, fitting terrain,
habitat or theme), at most three per table, rolled after the game's own encounter and only once
the save has beaten the League (each adapter's `leagueCleared(game)`: the Hall of Fame on Gen 1
and 2, `FLAG_SYS_GAME_CLEAR` on Gen 3). How wide each mode draws is
`SpawnConfig.selection[mode]`: LIMITED (`seeded`) is the classic mode, the tightest draw plus a
`resemble` bonus per type a replacement shares with the species it replaces; COMPLETE draws
wider, so the two differ on one seed. COMPLETE gives each slot a small pool (its main species
first, up to 6 extras from coverage, plus the cart's own species for that slot) so every
species under the cap lives somewhere and the game's own Pokémon stay where they were; an extra
that misses a themed map's theme tries the maps it fits and plain routes before any other. Gen 2 replaces a species across morning, day and night at once, keeping night-only
roles nocturnal. On Gen 3 the engine rolls its own table regardless, so the species is swapped
right after the roll, at the rolled level.

**TIME OF DAY SPAWNS** (OFF by default). OFF builds exactly what 0.13.x did:

- no extra pass;
- no extra RNG field, so `poolPick` keeps its single `rng:int`;
- no cache-key suffix.

With PREFER or STRICT, every table without a time per slot gets a second, **night** roster.
That is every Gen 1 and Gen 3 table, plus Gen 2's water and rods; Gen 2 grass already has its
MORN/DAY/NITE slots.

- **The night pass** has its own memory (`memory.night`) and appends `"night"` to every RNG
  key, so it never moves a day roster.
- **The day roster** uses the usual keys and memory.
- **Scoring.** Both passes score `tod_match` / `tod_mismatch`. The night pass also scores
  `tod_keep`, which keeps a role's day species unless it is a day one.
- **STRICT** is a hard filter at every tier, like the special filter, for species that only
  come out at one time: a main species must suit every period it is shown in, a COMPLETE pool
  member at least one.
- **COMPLETE pools** are shared by day and night: a role's night pick joins its day seat's
  pool. The coverage pass is period-neutral, so every species stays catchable at some hour.
  Each draw is weighted by `SpawnConfig.time_of_day.off_hours` (3:1 toward the current
  period; 0 for a STRICT species out of its time).
- **The clock** ([src/clock.lua](src/clock.lua)) is WoobleDex's:
  - its `clockSource()` export, else its stored option, else `"game"`;
  - the side-effect-free RTC reading on Ruby/Sapphire/Emerald, the device clock otherwise;
  - night 20:00-04:00, except Gold/Silver/Crystal, which use the encounter's own `daytime`
    (night from 18:00).
- **A turn** is checked in the roll hook before the engine rolls (Gen 3 rolls on the live
  tables), on `map.entered`, `world.tod_changed` and WoobleDex's `clock_source` changing. It
  re-applies live sync and fires `period_changed`.
- **The data** is `data/time_of_day.lua`, kept out of `DATA_VERSION` and every hash (see
  below). Its own version is part of the cache key only while the option is on.

Tuning numbers live in `SpawnConfig`
([src/config.lua](src/config.lua)); shiny chains are [src/chain.lua](src/chain.lua).

## Regenerating the profile data

```bash
cd pokemon_spawn_generator
python -m pip install requests
python generate_spawn_data.py --out <a folder outside the mod> --lua ../data/spawn_profiles.lua
```

Regenerating `spawn_profiles.lua` changes `DATA_VERSION`'s inputs and reshuffles every seed,
so only do it on purpose (CHANGELOG). The day/night data is separate and can be regenerated
alone:

```bash
python generate_spawn_data.py --out <a folder outside the mod> \
  --time-of-day ../data/time_of_day.lua --tod-report <folder>/tod_report.json
```

- **Where the calls come from.**
  - **#1-493:** PokéAPI's time-of-day encounter conditions, which only Gold/Silver/Crystal,
    HeartGold/SoulSilver and Diamond/Pearl/Platinum record. Johto decides for #1-251 and
    Sinnoh for the rest.
  - **Newer species:** [pokemon_spawn_generator/time_of_day_overrides.py](pokemon_spawn_generator/time_of_day_overrides.py),
    our own review of their Pokédex text. The report lists the candidates; leans only. Never
    copy another mod's lists.
  - **A family member** with no evidence follows its family.
- **The report** also lists every difference from the Gold/Silver/Crystal reference
  (`EXPECTED`): "softened" means only → mostly.
- **Keep `--out` outside the mod root.** `.modkitignore` matches exact paths, so a cache
  folder inside it would ship.

See [pokemon_spawn_generator/README.md](pokemon_spawn_generator/README.md).
