# Modern Spawns

Modern Spawns redistributes every wild encounter in Pokémon Red, Blue, Yellow,
FireRed, LeafGreen, Ruby, Sapphire and Emerald across Gen 1–9 species. Each
map keeps the game's own encounter rate, slot levels and odds. Only the species change, and they're chosen
dynamically rather than from hand-written per-map lists. It's for players who
want a modern Pokédex's worth of wild Pokémon in Kanto, Johto and Hoenn, and for mod
authors who want a spawn framework to build on.

## What's new in 0.11.0

- **Much more variety.** Early routes used to offer the same few Pokémon whatever
  the seed. Now each route draws from a far wider mix, including many more Gen 9
  Pokémon. Your saved game's wild Pokémon will change once when you update; your
  seed stays the same.
- **A new spawn mode, COMPLETE.** Every Pokémon in your GENERATIONS range lives
  somewhere in the game, so you can catch the whole Pokédex in one playthrough.
  With LEGENDARIES ON, every legendary and mythical gets a home too.
- **SEEDED is now called LIMITED.** It works exactly as before, and your setting
  is kept.
- **The Pokédex AREA page shows where Pokémon are** (FireRed, LeafGreen, Ruby,
  Sapphire and Emerald). It shows the spots Modern Spawns picked, not the original
  game's, including the Sevii Islands and places you haven't discovered yet.
- **Look up Pokémon you haven't seen yet.** With National Dex Gen 3 0.7.0 or
  later, scroll to any number in the Pokédex and press A. The name and picture
  stay hidden, but the AREA page tells you where to find it.
- **Legendaries show up in the Pokédex early.** With LEGENDARIES ON, each
  legendary with a home is marked as seen, like a roaming legendary after the TV
  report, so you can check where to look before you meet it.
- **Gold, Silver and Crystal aren't supported right now** (see below).

## Requirements

**Gold, Silver and Crystal are not supported right now.** gen1recomp's Gen 2
species schema changed (2026-10-07) and `national_dex` can no longer register
species past #251 there, so the mod would only offer Gen 1-2 species. It is
marked incompatible until `national_dex` is fixed; the Gen 2 code is kept.

- gen1recomp with the game imported.
- A species mod for the game you're playing:
  - **Red, Blue, Yellow:** [`national_dex`](https://github.com/sanjinpepic/gen1recomp-national-dex)
    with its **NATIONAL DEX** option **ON**. That option is what registers
    species #152–1025. With it off, Modern Spawns leaves the original tables
    alone and logs why.
  - **FireRed / LeafGreen / Ruby / Sapphire / Emerald:** `national_dex_gen3`, which registers
    #387–1025 on every Gen 3 game. It ships no battle sprites, so pair it with a sprite mod.

## Options

Every setting lives in **OPTIONS → MODS → Modern Spawns**. The mod adds
nothing to the top-level OPTIONS screen.

| Option | Values | Effect |
|---|---|---|
| MODERN SPAWNS | ON / OFF | OFF uses the game's original tables. |
| GENERATIONS | GEN 1, GEN 1-2 … GEN 1-9 | Limits which generations can spawn. GEN 1 uses the original tables. |
| SPAWN MODE | LIMITED / EVERY MAP / RANDOM / COMPLETE | LIMITED: each map keeps one roster for the save file. EVERY MAP: a map's roster is drawn again on every entry. RANDOM: every encounter draws a new species. COMPLETE: every species GENERATIONS allows lives somewhere, so the whole dex can be caught (see below). |
| LEGENDARIES | OFF / ON | ON: legendaries (1 in 1024 encounters) and mythicals (1 in 2048) can appear on their home maps, until the save owns them. |
| SEED | a code of up to 10 characters | Shows the loaded save's seed; press A to type a new one. Typed at the title screen, it becomes the next NEW GAME's seed. Leaving it empty keeps the seed. |
| REROLL SEED | - / REROLL | Step to REROLL for a new random seed |

Changes take effect on the next encounter; no restart is needed.

The seed belongs to the save and is kept with the next SAVE. Switching SPAWN
MODE never changes it; only REROLL SEED or typing a seed does. The same seed
with the same settings always gives the same LIMITED tables, so a seed can be
shared. In every mode the game's own encounter rate, slot odds and levels are
kept.

## How species are chosen

The game's own tables are the skeleton, and only data the game doesn't have is
added:

- **From the running game:** each map's rate, slot levels, odds ladder and
  Super Rod groups; the map's tileset; which species are registered; their dex
  number, types and base stats; and evolution links (the ROM's own, plus
  `national_dex`'s `evolutionsOf` for species past #151).
- **Shipped with the mod:** `data/spawn_profiles.lua`, built from PokéAPI's
  wild-encounter data. It holds each species' usual wild level range,
  habitats, terrains (grass, cave, water, fishing), rarity, and
  legendary/mythical status. Species PokéAPI has no wild data for (all of
  Gen 9) get a profile estimated from their evolution stage, base stats and
  types.

For each table, slots that held the same species form a *role*, and each role
gets one new species. Candidates are scored on:

- how well their level range fits the slot levels, and whether they'd be
  below their evolution level;
- terrain and habitat fit;
- sharing types with the species they replace, or with the map's theme;
- rarity matching the role's share of the odds;
- penalties for repeats within the map and across the previous few maps.

Legendary and mythical species never enter a table. With **LEGENDARIES ON**,
each one gets up to two *home* maps, picked from runtime data:

- the table's levels must be close to the species' (host maps reach at least
  level 30, so early routes never host one);
- its terrain must fit;
- its habitat or the map's theme must match, and a theme match weighs most.

A table hosts at most three species. After the game rolls an encounter on a
home map, a 1-in-1024 roll (1-in-2048 for a mythical) can turn it into one of
that map's hosts, at the level the game rolled. A species the save already
owns is skipped. On Red this puts Zapdos in the Power Plant, Articuno in the
Seafoam Islands and Mewtwo in Cerulean Cave. The rates and limits are in
`SpawnConfig.legendary`.

Every draw comes from the save's seed. Under LIMITED, a playthrough keeps the same rosters. EVERY MAP and RANDOM
mix a visit or encounter counter into the seed and draw from a wider set of
top candidates, so redraws actually differ. Old Rod and Good Rod catches are
unchanged.

### COMPLETE

Every game has more species than wild slots (Emerald: about 940 species at
GEN 1-9 against 1319 walking and surfing slots), so under COMPLETE each
slot holds a small **pool** instead of one species. The game still rolls the
slot with its own odds and level, and the species is then drawn from that
slot's pool. Each slot keeps its LIMITED species as the first entry of its pool;
every species left over is placed where it fits best (level, terrain, habitat,
type), at most 6 per slot, so a late evolution ends up in a late area. Pools
average under 3 species, which share the slot's odds. The seed decides where
each species lives, so a reroll moves them around, and every seed still
covers the whole dex. With LEGENDARIES ON, every legendary and mythical under
the cap is also given a home (at the usual 1-in-1024 / 1-in-2048).

The whole layout is built once when a save loads or a setting changes: about
0.4-0.6 s on a desktop (LIMITED takes 0.25-0.4 s), and nothing extra per step
or encounter.

### The Pokédex AREA page (Gen 3)

On FireRed, LeafGreen, Ruby, Sapphire and Emerald, the Pokédex AREA page shows
where Modern Spawns puts each species: every map's table under LIMITED, every
pool under COMPLETE, and the maps drawn this session under EVERY MAP. Under
RANDOM it shows nothing, since there are no fixed tables. The game's own
fishing and Rock Smash spots still show. With LEGENDARIES ON (any mode but
RANDOM), every legendary and mythical with a home is marked as seen, like a
roaming legendary after the news report, so its AREA page can be opened
before you meet it. Seen marks stay, as in the original games.

With `national_dex_gen3` 0.7.0 or later, a species you haven't seen yet can be
opened too, as long as Modern Spawns puts it somewhere under the current
settings: scroll to its number and press A. Its name, picture and cry stay
hidden and the Cry and Size pages stay closed, but its AREA page shows where it
lives. The list runs on to the last number that can be opened. Not under
RANDOM, and not for species outside GENERATIONS.

Tuning numbers live in one table, `SpawnConfig` in
[src/config.lua](src/config.lua).

## For mod authors

```lua
local spawns = mod:find("modern_spawns")
if spawns and (spawns.exports.apiVersion or 0) >= 1 and spawns.exports.isActive() then
  local grass = spawns.exports.tableFor("ROUTE_1", "grass")  -- { rate, slots, buckets? }
end
```

| Export | Returns |
|---|---|
| `isActive()` | whether generated tables are in use |
| `generation()` | `1` (Red/Blue/Yellow), `2` (Gold/Silver/Crystal) or `3` (FireRed/LeafGreen): which shapes the table functions return |
| `maxGeneration()` | the generation cap in force, or nil |
| `settings()` | `{ enabled, maxGeneration, spawnMode }` as the player set them |
| `spawnMode()` | `"seeded"`, `"map"`, `"random"` or `"complete"`; under RANDOM there's no fixed table, so `tableFor`/`superRodFor`/`explain` return nil |
| `seed()` / `setSeed(text)` / `rerollSeed()` | read or change the loaded save's seed |
| `legendaryHomes()` | `{ [mapId] = { grass = { {id, score, category} }, water = … } }`, where legendaries would appear |
| `tableFor(mapId, terrain)` | the generated grass / indoor / water table (copy) in the running game's own shape, or nil. Gen 1: `{ rate, slots, buckets? }`. Gen 2 grass: `{ map, rates, slots = { MORN, DAY, NITE } }`; Gen 2 water: `{ map, rate, slots }` |
| `superRodFor(mapId)` | the Super Rod catches (copy): Gen 1 `{ { species, level } }`, Gen 2 fish rows `{ { chance, species, level } }`; or nil |
| `poolFor(mapId, terrain)` | COMPLETE only: `{ [slot] = { species ids } }`, what each slot of `tableFor`'s table can turn into (its own species first); nil in other modes. Since 0.11.0 |
| `locate(speciesId)` | `{ [mapId] = { land/grass/water = true } }`: where a species can be met under the current settings (empty under RANDOM, nil while inactive). What the Gen 3 Pokédex AREA page shows. Since 0.11.0 |
| `drawFor(mapId, terrain)` | for a mod that picks species itself, called once per pick (visible overworld spawns): `tableFor` under LIMITED / EVERY MAP, a fresh one-off draw under RANDOM. Same shape as `tableFor`. Since 0.7.0 |
| `legendaryFor(mapId, terrain)` | the LEGENDARIES roll for such a pick: a hosted, not-yet-owned legendary (1/1024) or mythical (1/2048) species id, or nil. Since 0.7.0 |
| `explain(mapId, terrain)` | per-slot records: species, replaced, score, reasons, penalties |
| `candidates(opts)` | the candidate pool, filterable by generation, terrain, level range and habitat |
| `profileOf(speciesId)` | one species' spawn profile |
| `invalidate()` | drop cached tables |

Every return value is a copy. The event `mod.modern_spawns.tables_changed`
fires whenever tables are regenerated. Modern Spawns wraps `encounter.roll`,
`encounter.fishing` and `encounter.table` as the innermost wrapper, so its
tables are what the engine rolls. Outer mods can still suppress an encounter
or post-process it through `encounter.species`.

A mod that suppresses step encounters and picks species itself (visible
overworld spawns) bypasses those hooks entirely. If it's willing to call
into this mod, it should read `drawFor` (and `legendaryFor`) per pick
instead — Wilds of Kanto Revival does this.

For a mod that can't be changed to call anything (a wild-encounter guide
reading `game.data.encounters`/`gen2Encounters`/`gen3Encounters` directly,
say — this is why Kanto Gear's guide now shows modern species), those
tables themselves carry the generated species too, kept in sync and
restored on OFF — see "Known limits" above for where this can't be fully
faithful (RANDOM, an unvisited EVERY MAP map).

## Regenerating the profile data

```bash
cd pokemon_spawn_generator
python -m pip install requests
python generate_spawn_data.py --lua ../data/spawn_profiles.lua
```

See [pokemon_spawn_generator/README.md](pokemon_spawn_generator/README.md).

## Supported games

| Game | What's redistributed | Left as the game has it |
|---|---|---|
| Red, Blue, Yellow | Grass and cave tables, surf tables, Super Rod groups | Old Rod, Good Rod |
| Gold, Silver, Crystal | Grass and cave tables (all three times of day), surf tables, Good and Super Rod on maps that have wild tables | Old Rod, swarms, Bug Catching Contest, `randomwildmon` scripts, Headbutt, Rock Smash, roaming beasts |
| FireRed, LeafGreen, Ruby, Sapphire, Emerald | Grass and cave tables, surf tables | Fishing, Rock Smash, static and scripted encounters (the engine gives mods no hook for them) |

In Gold, Silver and Crystal, each species in a map's morning, day and night
lists is replaced by one species across all three times. A night-only species
(like Hoothoot) is replaced by one the game itself only shows at night, or a
Ghost or Dark type, so the day/night feel survives. Headbutt, Rock Smash and
roamers can't be changed because the engine gives mods no hook for them.

On every Gen 3 game, the engine rolls from its own table no matter what a mod
hands it. So Modern Spawns swaps the species right after the roll: each
slot the game rolls is mapped to its generated species, at the level the game
rolled. Gen 3 has no map order, so maps are generated in order of their
average wild level. One adapter and one `national_dex_gen3` dependency cover
all five Gen 3 games: Hoenn's map ids, item lists and move-tutor sets differ
from Kanto's, but nothing in either mod is tied to FireRed specifically — see
`national_dex_gen3`'s own README and CLAUDE.md for exactly what differs per
game (chiefly: Ruby/Sapphire never had move tutors at all).

Blue, Silver, LeafGreen, Ruby and Sapphire use the same code paths as Red,
Gold and FireRed/Emerald respectively. Blue, Silver and LeafGreen aren't
imported in the development checkout, so they're covered by the Red, Gold
and FireRed tests; Ruby and Sapphire *are* imported there, and
`tests/rse_test.lua` runs against them (and Emerald) directly, alongside
FireRed's own `gen3_test.lua`.

## Known limits

- Early routes are the thinnest part of the pool: a level 2-5 slot has far fewer
  species with observed wild data than a mid-game one, so the generator also
  admits low-stat first-stage species there. Expect more variety from mid-game
  routes than from the first one or two. 

- On Gen 3, the forms that are wild in the real games spawn (Galarian and Hisuian forms, and
  the colours, sizes and styles of Flabébé, Floette, Florges, Pumpkaboo, Gourgeist, Oricorio,
  Rotom, Alcremie and a few more). Item forms (Origin, Therian, Crowned and so on) and megas
  never do. Gen 1 and 2 spawn no forms.
- On Gold, Silver and Crystal, the preview (`mod.world:effectiveEncounters`)
  shows the DAY list, because the preview has no time of day.
- Under COMPLETE, `tableFor` and the live encounter data show each
  slot's first pool species only; `poolFor` lists the rest. Kanto Gear's
  guide therefore shows one species per slot. Gen 3 fishing has no hook, so
  water species there live on surf tables.
- **Live sync** (writing the generated species into the game's own
  `encounters`/`gen2Encounters`/`gen3Encounters` data, for a mod that reads
  it directly instead of through a hook or export — Kanto Gear's
  wild-encounter guide is why this exists) has two gaps:
  - Under RANDOM, the live tables hold one snapshot per map visit, not the
    full distribution — the same thing is already true of `drawFor`.
  - Under EVERY MAP, only maps the player has actually visited this session
    are synced; an unvisited map still shows its original species to a raw
    reader until the player reaches it.
  - If another mod also writes species directly into these same tables
    (a randomizer mod, say), whichever one writes last wins — this isn't
    arbitrated.
