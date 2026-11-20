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

`apiVersion` is 3. It goes up only when an existing export changes meaning (2: `isActive()` is
true on GEN 1 and with only the cart's own species, and `maxGeneration()` can answer 1; 3:
GENERATIONS can be any set, so `maxGeneration()` is only the highest generation in force); added
exports don't bump it, so test for a newer one by presence,
`type(exports.chainBonus) == "function"`.

| Export | Returns |
|---|---|
| `isActive()` | whether generated tables are in use: MODERN SPAWNS ON and at least one species registered (the cart's own count) |
| `generation()` | `1` (Red/Blue/Yellow), `2` (Gold/Silver/Crystal) or `3` (FireRed/LeafGreen/Ruby/Sapphire/Emerald): which shapes the table functions return |
| `maxGeneration()` | the highest generation in force, or nil |
| `generations()` | the generations in force, ascending (`{ 1, 3, 6 }` under CUSTOM), or nil while inactive |
| `settings()` | `{ enabled, maxGeneration, generations, spawnMode, legendaries, shinyChain, timeOfDay, trainerTeams }` as the player set them (`timeOfDay`: `"off"`, `"prefer"` or `"strict"`; `trainerTeams`: `"off"`, `"on"` or `"items"`) |
| `period()` | `"day"` or `"night"` on the clock TIME OF DAY SPAWNS follows (WoobleDex's Clock Source on Ruby/Sapphire/Emerald, the device's on FireRed/LeafGreen and Red/Blue/Yellow, the cart's on Gold/Silver/Crystal), whatever the option is set to; nil without a clock |
| `spawnMode()` | `"seeded"` (LIMITED), `"map"`, `"random"` or `"complete"`; under RANDOM there is no fixed table, so `tableFor` / `superRodFor` / `explain` return nil |
| `seed()` / `setSeed(text)` / `rerollSeed()` | read or change the loaded save's seed |
| `legendaryHomes()` | `{ [mapId] = { grass = { {id, score, category} }, water = … } }`: where legendaries would appear |
| `tableFor(mapId, terrain, period?)` | the generated grass / indoor / water table (copy) in the running game's own shape, or nil. Gen 1: `{ rate, slots, buckets? }`. Gen 2 grass: `{ map, rates, slots = { MORN, DAY, NITE } }`; Gen 2 water: `{ map, rate, slots }`. With TIME OF DAY SPAWNS on, `period` (`"day"`/`"night"`) picks that roster, by default the one in force now; OFF has one roster and ignores it |
| `superRodFor(mapId)` | the Super Rod catches (copy): Gen 1 `{ { species, level } }`, Gen 2 fish rows `{ { chance, species, level } }`, Gen 3 `{ rate, slots = { { species, minLevel, maxLevel } } }`; or nil |
| `poolFor(mapId, terrain, period?)` | COMPLETE only (terrain `land`/`grass`, `water`, and on Gen 3 `fish.good`/`fish.super`): `{ [slot] = { species ids } }`, what each slot can turn into (its main species first, the cart's own species for the slot last where it keeps one of its homes); nil in other modes. With TIME OF DAY SPAWNS on, what it can turn into at `period` (STRICT leaves out species that only come out at the other time), that period's main species first |
| `encounters(mapId?, opts?)` | every species on a map (default: the player's) with its odds, method by method: `{ mapId, name, active, random, mode, period, time, sections = { { method, kind, time?, rate, mons = { { id, chance, minLevel, maxLevel, pooled } } } }, rare = { { id, category, method, odds } } }`. `method` is `grass`/`cave`/`surf`/`old`/`good`/`super`/`rock`; `chance` is percent of that method's encounters (the cart's slot odds; COMPLETE's pools split as the `encounter.species` hook draws them, TIME OF DAY SPAWNS weights included; looks folded into their base); `pooled` when only a pool supplies it. `opts.period` `"day"`/`"night"` (default now); `opts.time` on Gen 2 grass `"MORN"`/`"DAY"`/`"NITE"`/`"all"` (default now). Answers while inactive too, from the game's own tables (`active` false); under RANDOM (`random` true) only the game's own sections (the Old Rod, Gen 1's Good Rod, Gen 3's Rock Smash). `rare`: legendaries hosted there once the League is beaten and not owned (`odds` = 1 in that many). Read only. Since 0.18.0 |
| `currentMap()` | the player's map id (the last `map.entered`, else the engine's position), as the other functions take it. Since 0.18.0 |
| `areaName(mapId)` | the place's name as the game shows it (Town Map, landmark, map section). Since 0.18.0 |
| `locate(speciesId)` | `{ [mapId] = { land/grass/water = true } }`: where a species can be met under the current settings (empty under RANDOM, nil while inactive). What the Gen 3 Pokédex AREA page shows |
| `drawFor(mapId, terrain, period?)` | for a mod that picks species itself, once per pick (visible overworld spawns): `tableFor` under LIMITED / EVERY MAP, a fresh one-off draw under RANDOM; `period` as for `tableFor` |
| `legendaryFor(mapId, terrain)` | the LEGENDARIES roll for such a pick: a hosted, not-yet-owned legendary (1/1024) or mythical (1/2048) id once the League is beaten, or nil |
| `chain()` | the current shiny chain `{ species, count }`, or nil |
| `chainSpeciesFor(mapId, terrain)` | for such a pick: the chained species when the chain makes this encounter it (rolled here), else nil |
| `chainBonus(species)` | for an encounter of `species` (an id or the engine's number): `{ shiny = chance 0..1, perfectIvs = 0..3 }`, or nil. The consumer makes it shiny and sets the stats |
| `chainRecord(species, result)` | count a fight that wasn't a real battle (an overworld companion's): `"win"` / `"catch"` extend the chain, `"run"` ends it |
| `explain(mapId, terrain, period?)` | per-slot records: species, replaced, score, reasons, penalties (`period` as for `tableFor`) |
| `candidates(opts)` | the candidate pool, filterable by generation (`maxGeneration`, or `generations` = a list), terrain, level range and habitat |
| `profileOf(speciesId)` | one species' spawn profile (with `candidates`: `timeOfDay` `"day"`/`"night"`/nil, `timeOfDayOnly` when it only comes out then, and `evolvesFrom`, the species it evolves from) |
| `invalidate()` | drop cached tables |
| `trainerTeams()` | TRAINER TEAMS: `{ mode, maxGeneration, generations, active }`; `active` while it is not OFF and species are registered (independent of MODERN SPAWNS) |
| `trainerTeamFor(class, id, party)` | with the `trainer.party` hook's own arguments for the running game: a copy of the team that battle fields, or nil when TRAINER TEAMS leaves it alone |
| `trainerIdentity(class, id, party)` | who that battle's trainer is (`"rival"`, `"LEADER:ROXANNE"`, `"FALKNER:FALKNER"`, ...): rematches and rounds share one identity and so one family map; nil when left alone |
| `facilitySpecies(name)` | a battle facility's one-to-one species map for this save, `{ [original id] = new id }`, or nil (OFF, or no such facility on this cart). Names: `crystal_battle_tower`, `emerald_frontier` (every Frontier facility, the Battle Tents, Pyramid and Pike wild Pokémon), `trainer_hill`, `rs_battle_tower`, `frlg_trainer_tower` |

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

- **Generations.** `Config.generations(mod)` is the player's set: Gen 1 through N for a
  numeric GENERATIONS, or the `gen_1` … `gen_9` toggles under CUSTOM (shown only then, by
  `visible_if`). `Runtime.registeredGenerations()` intersects it with the generations that
  have registered species and wraps it in `Config.genSet`: `{ has, list, max, key }`. The
  generator and the trainer planner test `gens[c.gen]`. `key` enters every RNG hash and cache
  key: `"N"` for Gen 1-N, exactly the old single cap, so those settings never drift, and the
  list (`"1,3,6"`) otherwise. An empty set is inactive (the game's own tables). A pure ctx
  with a numeric `maxGen` and no `gens` means Gen 1 through it (the fixture tests).

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
first, then extras from coverage, then the cart's own species for that slot), as big as keeps
every member at `SpawnConfig.complete.min_share` (5%) of the table's encounters or more (a 40%
role holds 8; at most `max_pool`). A role under 5% (Gen 3's 4% and 1% slots, Gen 2's 4% and 1%,
Gen 1's 11/256 and 3/256) never draws a species of its own: `mergeSmallRoles` hands its slots to
the table's biggest role out at the same times (Gen 2 grass: one host for all its times when
one exists, else slot by slot), so those slots carry the host's species and pool; the slot odds
and levels stay the cart's. With TIME OF DAY SPAWNS the 3:1 lean is floored (`Rates.floored`,
used by `poolPick` and `Rates.section` alike): no member that may come out drops under 5% of the
table, and when a pool cannot keep everyone there, the other period's primary steps aside. Coverage seats only species
the player cannot evolve into (`evolved_by_evolving`: no non-special parent under the cap), so
every first stage lives somewhere and the rest come from evolving; a main species in a role
under 5% doesn't count as placed. The cart's own species go back into at most `original_homes`
(3) of their roles, the biggest first, and an evolved one not at all. COMPLETE's primaries take
`selection.complete.stage_penalty` per stage past the first, `mid_stage_penalty` more for one
that evolves further (a final second stage wins over a middle one), and `repeat_penalty` per seat
the species already holds; a role under 5% takes a first stage only (`small_role_first_stage`, a
filter in `eligible`). With TIME OF DAY SPAWNS, a role with room for one species (under twice
`min_share`) keeps its day pick at night (`keptByNight`), unless that pick is day-only under
STRICT. An extra that misses a
themed map's theme tries the maps it fits and plain routes before any other. Gen 2 replaces a species across morning, day and night at once, keeping night-only
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

## WoobNav (Kanto Gear app)

`src/woobnav/` registers a Silph Store app through Kanto Gear's module hook
(`mod:find("kanto_gear").exports.modules`, `api == 1`: `register{ id, label, category,
description, icon, accent, available, shown, open }`). Without the Gear nothing registers and no
hook is installed. While the app is open (`shown()` true) the Gear stands down entirely, so the
WoobNav draws and takes input itself:

| File | What |
|---|---|
| `init.lua` | state, the model (`exports.encounters` -> six-a-page cards; a species' HERE rows at each time of day), input actions, events, the registration |
| `gear.lua` | the Store spec: words, 24x24 pal/rows icon, translations |
| `view.lua` | the two screens on 240x216 (Kanto Gear's bottom screen) and their hit-testing (pure) |
| `art.lua` | Kanto Gear's Pokegear palette in its light and dark variants (`A.setDark` swaps `A.C` in place), header plate, windows and buttons; its HGSS pixel fonts (`assets/fonts`); Pokémon pictures (Gen 1/2 coloured on the CPU, Gen 3 `frontPic`), trimmed to their opaque part |
| `info.lua` | the summary page from the game's own Pokédex data (the sources WoobOS reads) |
| `display.lua` | where it shows, following the Gear's DISPLAY MODE: second display (gate at `render.compose` 900, async readback push), handheld (the game to the second display), combined / fullscreen split (Gen 1/2 `render.viewport` capture + `render.window`; Gen 3 `Playfield.cutout` + `render.hud`); touches from `pollTouch`, `input.pointer`, Gen 3 `TouchControls` and a desktop mouse poll. No input layer: buttons stay with the game |
| `layout.lua`, `gate.lua`, `surface.lua`, `host.lua` | geometry, the second-display gate, the canvas, the engine seams; condensed from NaviPlay (MIT, same author), engine wraps keyed `__woobnav*` so they chain with NaviPlay's |

The theme button (top right, `View.hit` -> `"theme"`) flips `Art.setDark`; the choice is kept per
playthrough like Kanto Gear's Home: `mod.save` key `woobnav_dark`, plus `mod.storage`
`woobnav/theme` written at once and read on `save.loaded` / `save.created` /
`checkpoint.restored` (never at load: a storage read can name the playthrough).

`exports._woobnav` is a test seam (not API). `tests/woobnav_test.lua` covers the spec, the layout,
the gate, registering with the real Gear (Crystal) and the whole tap flow;
`tests/drivers/woobnav_probe.lua` shoots it in the running game (combined and fullscreen; a
stand-in Store hook where the Gear is switched off on the machine):

```sh
SHOT_DIR=<dir> POKEPORT_GAME=crystal POKEPORT_VERSION=crystal WOOBNAV_MAP=ROUTE_29   POKEPORT_DRIVER=mods/modern_spawns/tests/drivers/woobnav_probe.lua love .
```

## Trainer teams

TRAINER TEAMS (OFF / ON / ON + ITEMS, default OFF) lives apart from the wild tables:
[src/trainers.lua](src/trainers.lua) (pure planner), [src/trainer_items.lua](src/trainer_items.lua)
(item catalog), [src/trainer_runtime.lua](src/trainer_runtime.lua) (option, cache, hook),
`src/adapters/trainers_gen<N>.lua` (each game's trainer data and party shape) and
`src/facilities_gen<N>.lua` (battle facilities). It follows GENERATIONS and the save's seed,
not MODERN SPAWNS, and never touches the wild generator's RNG keys or memory: wild output is
identical with it ON or OFF.

- **The hook.** `trainer.party` is wrapped at priority -100 only while the option is not OFF,
  and unwrapped when it goes OFF (on Gen 3 any wrapper reroutes every battle through the
  engine's mod path). Story trainers only: Gen 2's Battle Tower call (member id 1), link
  battles, Gen 3's trainer ids 0, 1024 and nil pass through.
- **Identity and families.** A trainer's rematches share an identity (the rival is one across
  every class it fights under). Each original evolution family of an identity maps to one new
  family, drawn with `Rng.hash(seed, cap, "trainers", identity, root)`; the shown stage follows
  the level (non-level evolutions at Lv 25 / 35) and is never below the original's. Gym
  Leaders and the Elite Four are typed (`GYM_TYPES` per adapter); a gym may keep an original
  family at a penalty when the cart has too few of its type. Scoring: shared types
  (`type_weight`) plus `bst_per_point` per point of base stat total away from the original,
  where a typed boss measures from the original + `gym_bst_lift` (60), so it favours the
  stronger families of its type (`TrainerConfig`, `src/config.lua`).
- **Generations** apply to trainers as to wild spawns: `TR.generations()` is
  `Runtime.registeredGenerations()` (a `Config.genSet`). `Trainers.index(pool, key, gens)`
  allows `gens[c.gen]`; `ix.next(id)` steps through a stage left out only for its generation
  (GEN 2 + 4: Happiny -> Blissey), which never happens for Gen 1-N. Items take `gens` (the
  picks plus the cart's own generations) in place of `maxGen`.
- **The rival's starter** (`planIdentity`'s `rival` flag: identity `"rival"`, or May / Brendan
  on Ruby/Sapphire/Emerald via `info.rival`). The original rival's starter beats the player's,
  so its line is replaced by a starter line the player's starter beats (`Trainers.BEATS`
  twice: Fire -> Water, Water -> Grass, Grass -> Fire), with no shown type in
  `Trainers.RESISTS` of the player's type, at exactly the original's stage in every fight
  (`plan.exact`, `stageFor`'s `maxStage`). Its starter lines are planned before its other lines.
  Falls back to the usual tiers (still stage-capped) when nothing fits.
- **Moves.** A Pokémon the game gave custom moves gets a built set (`buildSet`): the best
  same-type attack of each of its types, one coverage attack, one listed status move, then the
  rest, all from its own level-up moves at that level.
- **Items** (ON + ITEMS): an item is offered only when its generation is at most
  `max(cap, the cart's generation)`, it exists, and its held effect runs (the cart's own, or
  WoobleDex's `_held` / `_heldModern`). Who holds an item scales with progress
  (`trainer_runtime.lua` `holdersOf`, numbers in `TrainerConfig.items`): the battle's stage is
  its ace's level (early < `mid_level` 20 <= mid < `late_level` 35 <= late). Elite Four and
  champions (adapter `elite`) and the rival's final battle (top level = the identity's
  `lastTop`): every Pokémon, `strong`. The rival's first battle (`firstTop`): none. Another boss:
  its ace always (`basic` early, `ace` mid, `ace` + `strong` late), each other with
  `others[stage]`. Ordinary trainers: `ordinary[stage]` items per team (fraction = chance of one
  more), the strongest first, `basic` only, the game's own items counting. `basic` = type
  booster or Berry; `strong` gates the competitive rows of `Items.ACE`. No item twice on a team,
  told apart by `adapter.itemNumber` where the game has one. The game's own held items are kept. Choice Band / Specs read each move's `category` from the adapter: with WoobleDex's
  MOVE SPLIT on, the move's own class (Gen 3: its hub `Types.__ndxSplit.categoryOf(num)`, nil
  while off; Gen 2: its `move_split` option and `moveById(id).damageClass`), else the split by
  type. `exports._trainerMovesFor(id, level)` is the test seam
  (`tests/trainers_move_split_test.lua`; WoobleDex installs the hub on `game.ready`).
- **Facilities.** Each facility gets one one-to-one species map per save
  (`Planner.facilityMap`: replacements come only from species outside the facility's own, so
  two sets never collapse into one species). The facilities' own "no repeated species / item"
  draws therefore pick the same sets ON as OFF, and cannot hang. Wrapped engine functions,
  installed once and re-pointed on reload, answering the engine's own result on OFF or any
  error: Crystal `BattleTower.roster`; Emerald `D.pack` (`mons`, `brains`, `tents`),
  `Pyramid.generateWildMon`, `Pike.tryGenerateWildMon` and `Hill.trainer`; Ruby/Sapphire's
  tower `T.pack`; FireRed/LeafGreen `Tower.buildEnemyParty`. Unown stays itself in the Frontier
  (the Factory's draws skip it by species). `tests/facilities_gen3_test.lua` and
  `tests/trainers_gen2_test.lua` pin the same-draws property.

Bump `ALGO` in `src/trainer_runtime.lua` when a change would hand existing saves different
teams, and say so in the CHANGELOG.

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
