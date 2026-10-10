# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.11.0] - 2026-10-09

### Added

- **SPAWN MODE labels:** SEEDED is now shown as **LIMITED**. The stored
  value is unchanged, so existing saves and settings keep their mode.
- **Pokédex AREA page (FireRed, LeafGreen, Ruby, Sapphire, Emerald)** now
  shows where this mod puts each species: every map's generated table under
  LIMITED, every pool under COMPLETE, the maps generated this session under
  EVERY MAP, and nothing under RANDOM (no fixed tables). The cart's own
  fishing and Rock Smash spots still show. Before this the page always showed
  the cart's original locations.
- **Undiscovered Pokédex entries** (Gen 3, with `national_dex_gen3` 0.7.0+): a species
  you haven't seen can be opened by its number when this mod puts it somewhere, with
  its name, picture and cry hidden, so its AREA page shows where to find it. Not under
  RANDOM or outside GENERATIONS. New export `locate(speciesId)`.
- **AREA page completeness.** Emerald hides "landmark" places (Sky Pillar, Artisan Cave,
  Seafloor Cavern, Altering Cave, Mirage Tower, Desert Underpass) until discovered, and about a
  sixth of placed species lived only there: they now show. On FireRed/LeafGreen, a Sevii map with
  no marker of its own (Six Island's Green Path) uses its island's, and with `national_dex_gen3`
  0.7.0 the page draws the Sevii Islands (over a third of placed species live only there). On the
  seed that showed the gap, every placed species now has a location on all three games.
- **LEGENDARIES ON** (every mode but RANDOM) marks each hosted legendary and
  mythical as seen in the Gen 3 Pokédex, like a roaming legendary after the
  news report, so its AREA page shows its home maps before it is met. Seen
  flags are permanent, as in the cart.

- **COMPLETE spawn mode.** Every species GENERATIONS allows is catchable
  somewhere. Each walking/surfing slot keeps its LIMITED species and also holds
  a small pool (average under 3, at most 6); the game rolls the slot with its
  own odds and level, then the species is drawn from the pool. Leftover
  species are placed where they fit best, hardest to place first. The seed
  decides where each species lives. With LEGENDARIES ON every legendary and
  mythical under the cap gets a home. Built once per save/setting change:
  0.40 s Emerald, 0.57 s FireRed, 0.38 s Red (LIMITED: 0.26 / 0.39 s).
  New export `poolFor(mapId, terrain)`; `spawnMode()` can answer `"complete"`.

### Removed

- **Gold, Silver and Crystal are marked incompatible** (`games` no longer lists
  `gen2`). gen1recomp's Gen 2 species schema gained a strict `dexEntry`
  (commit 722c2fc4), and `national_dex` still sends it Gen 1 fields, so every
  species past #251 is rejected and the mod could only ever offer Gen 1-2
  species there. The Gen 2 adapter and its tests stay in the repo; restore
  `gen2` in `manifest.json` (and the `national_dex` dependency's `games`) once
  `national_dex` registers species past #251 on Gen 2 again.

### Changed

- **Far more variety between seeds, modes and generations.** Early routes kept
  producing the same few species whatever the seed: Emerald's Route 101 gave
  8 distinct species over 200 seeds (Scatterbug in 16% of slots, Gen 5 and
  Gen 7 never), and Crystal's Route 29 gave about 6 (Charmander and Sentret,
  every time, in every mode). Three causes, three fixes:
  - **Plausible basics.** Most modern species have no observed wild level as
    low as an early route's (they are met later by game design, not because
    they are strong), so a level 2-3 slot had only ~27 candidates, 15 of them
    Gen 9. A first-stage species with base stats up to 340 now counts as
    available from level 2 (`SpawnConfig.plausible_basic`), with a small score
    penalty so species with observed data still win a close call. Only the
    lower level bound moves; evolution-level and generation-cap rules are
    unchanged.
  - **Wider, softer draw.** A role was drawn from its best 8/12/16 scorers
    (LIMITED/EVERY MAP/RANDOM) weighted by score gap. It is now a softmax over
    the scorers within a score window of the best (top 24/32/48), so nothing
    clearly worse than the best fit is drawn but many more species get real
    odds. No table gets larger and the scoring cost is unchanged.
  - **Gen 9 is no longer taxed for being estimated.** PokéAPI has no Gen 9
    encounters, so every Gen 9 species is on an estimated profile and took the
    -12 `estimated_profile` penalty, which kept the whole generation out of
    LIMITED (0% of slots). A generation with under 20% observed data is
    exempted.
  Measured, same maps and method: Emerald Route 101 LIMITED 8 -> 57 distinct
  species (top species 18% -> 6%, Gen 9 0% -> 14%), RANDOM 22 -> 81; Crystal
  Route 29 LIMITED 14 -> 50; Red Route 1 LIMITED 9 -> 25. Build time unchanged.
- **Existing saves get different rosters once.** The seed is unchanged, but the
  selection changed, so every game's LIMITED tables differ from 0.10.0's.
  `generator_test.lua`'s pinned fixture was re-pinned (ROUTE_B).
- Gold, Silver and Crystal are still limited to Gen 1-2 species: `national_dex`
  cannot register anything past #251 there. This makes that pool much more
  varied; it cannot add later generations.

## [0.10.0] - 2026-10-08

### Removed

- **1025Dex compatibility** (`src/compat/dex1025.lua`, its test and stub): 1025Dex is a manifest
  conflict now, so Modern Spawns no longer wraps the battle bridge for it or reads its exports.

### Changed

- Live sync logs one line per sync (how many maps it wrote, and whether the table is the engine's
  own), to tell a stale guide from a sync that did not run.

### Added

- **Alternate forms on Gen 3** (national_dex_gen3's, `src/species_pool.lua`):
  - the 11 regional forms that are wild in the real games (Galarian Darumaka,
    Darmanitan, Yamask and Stunfisk; Hisuian Zorua, Zoroark, Lilligant, Braviary, Sliggoo,
    Goodra and Avalugg) are candidates of their own, scored on the runtime estimate from
    their own typing, in their base species' family;
  - the 45 "looks" (Rotom's appliances, Oricorio's styles, Pumpkaboo/Gourgeist sizes,
    Flabebe/Floette/Florges colours, Alcremie creams, east-sea Shellos/Gastrodon, Wormadam
    cloaks, Midnight Lycanroc, white-striped Basculin, female Basculegion, the Antique / Artisan / Masterpiece tea set) are not
    candidates: after a species is chosen as before, the generator swaps it for one of its looks
    (or leaves it) with equal odds, so a species with many looks does not spawn more often
    (`variants` on the candidate; an extra RNG draw only for species that have looks, so Gen 1
    and 2 tables are unchanged).
  - item and fusion forms (Origin, Therian, Crowned, ...), Floette Eternal, Dusk Lycanroc and
    Ursaluna Bloodmoon are never spawned. Gen 1 and 2 still leave every form out.
  - `candidates()` / `profileOf()` add `form`, `baseSpecies` and `variants`.

## [0.9.0] - 2026-10-07

### Added

- **Live sync**: the generated species are now also written directly into
  the running game's own `encounters` / `gen2Encounters` / `gen3Encounters`
  data (and Gen 1's Super Rod groups) — restorable, species only, never
  mechanics — for a mod that reads those tables itself instead of going
  through `encounter.roll`/`encounter.table` or an export. This is for
  Kanto Gear's wild-encounter guide specifically, which reads the cart's
  raw tables directly and can't be changed to call anything (a third-party
  repo). `src/live_sync.lua`; see CLAUDE.md's "Live sync" rule for exactly
  what this touches, when, and the coexistence/RANDOM/EVERY MAP gaps it
  doesn't close, and README "Known limits" for the player-facing version.

### Changed

- This reverses the previous hard rule that generated tables were never
  written into `game.data`. OFF still restores the exact original species
  (backed up before the first write); switching MODERN SPAWNS off or back
  on, or changing the seed or SPAWN MODE, keeps the live tables in step.

## [0.8.1] - 2026-10-07

### Fixed

- The `national_dex_gen3` dependency now names its repo
  (`"github": "poooooby/national_dex_gen3"`), so the launcher can fetch it
  from the manifest alone. No Lua code changed.

## [0.8.0] - 2026-10-05

### Added

- **Ruby, Sapphire and Emerald.** `manifest.json` already targeted
  `games: ["gen3"]`, which the engine expands to every Gen 3 version, and
  `src/adapters/gen3.lua` was already fully generic -- no FireRed-specific
  code needed changing. Verified directly against real imported Ruby,
  Sapphire and Emerald carts: `tests/rse_test.lua` confirms generated grass
  and water tables, the generation cap, OFF, and that Hoenn's own
  legendaries (Kyogre, Groudon, Rayquaza) are correctly recognized as
  LEGENDARIES hosts on each game, the same as Kanto's on FireRed.
  `tests/_helpers.lua`'s `H.gen3Data()` now takes a `game` argument (still
  defaulting to `"firered"`).

## [0.7.1] - 2026-09-26

### Fixed

- The release workflow's own packaging step never read `.modkitignore`, so
  the 0.7.0 release zip shipped `pokemon_spawn_generator/` and `tests/`
  alongside the mod. It now excludes exactly what `modkit pack` would
  (`.modkitignore`'s listed paths, plus any dotfile other than
  `.luarc.json`), matching modkit's own `mod_files()` rule. No Lua code
  changed.

## [0.7.0] - 2026-09-25

### Added

- `drawFor(mapId, terrain)` and `legendaryFor(mapId, terrain)` exports, for
  mods that pick wild species themselves instead of letting the engine roll
  (visible overworld spawns never pass through the encounter hooks).
  `drawFor` is `tableFor` under SEEDED / EVERY MAP and a fresh draw per call
  under RANDOM; `legendaryFor` is the LEGENDARIES roll for one pick.
  Wilds of Kanto Revival uses both, so its visible Pokémon now follow Modern
  Spawns. `apiVersion` stays 1: check for these functions by presence.

## [0.6.0] - 2026-09-24

### Added

- **FireRed and LeafGreen** support.
  - Grass, cave and surf tables are redistributed. The species is swapped
    right after the engine's roll (FireRed ignores a replacement table) and
    handed back as a numeric species slot, at the rolled level.
  - Every mode, the generation cap, legendaries and the seed rows work as on
    the other games. Owned species are read from `session.dex.owned`.
  - Fishing, Rock Smash, and static and scripted encounters stay as the game
    has them; the engine has no hook for them.
  - Species past #386 come from the new `national_dex_gen3` mod, or from
    1025Dex when that's installed.
- **1025Dex coexistence:** while MODERN SPAWNS is ON, the encounters Modern
  Spawns decides skip 1025Dex's WILD GENS. WILD GENS keeps fishing and Rock
  Smash, and everything while MODERN SPAWNS is OFF.

### Changed

- Dependencies are scoped per game: `national_dex` on Red to Crystal,
  `national_dex_gen3` on FireRed and LeafGreen. The mod now declares
  `engine_internals`, used only for the 1025Dex battle-bridge wrapper.

## [0.5.0] - 2026-09-24

### Added

- **Blue and Yellow** support. They share Red's layout; Yellow's eight surf
  tables and four-entry Super Rod groups are redistributed too.
- **Gold, Silver and Crystal** support:
  - Grass and cave tables keep their morning, day and night lists, rates and
    levels. Each species in a map's lists becomes one new species across all
    three times.
  - Night-only roles stay nocturnal: they go to species the game itself only
    shows at night, or to Ghost and Dark types.
  - Surf tables, and the Good and Super Rod on maps that have wild tables,
    are redistributed.
  - The Old Rod, swarms, the Bug Catching Contest and `randomwildmon`
    scripts stay as the game has them. So do Headbutt, Rock Smash and
    roamers, which the engine gives mods no hook for.
  - Legendaries, SPAWN MODE and the seed rows work the same as on Red.
    Caught species are read from Gold's `pokedex.caught`.
- Export `generation()`. `tableFor` and `superRodFor` now answer in the
  running game's own table shape.

### Changed

- Game-specific data and hook handling moved into per-engine adapters
  (`src/adapters/gen1.lua`, `src/adapters/gen2.lua`). Red's SEEDED rosters
  are unchanged.

## [0.4.0] - 2026-09-24

### Changed

- Every setting now lives only in **OPTIONS → MODS → Modern Spawns**. The
  mod adds nothing to the top-level OPTIONS screen.
- **SEED** is a text row in that menu. It shows the loaded save's seed, and
  typing one applies it. Typed at the title screen, it becomes the next NEW
  GAME's seed; CONTINUE keeps that save's own seed. Leaving it empty, or using
  RESET DEFAULTS, never clears a seed.
- **REROLL SEED** is a `-` / `REROLL` row. Stepping to REROLL draws a new
  seed, and the row returns to `-`.

## [0.3.0] - 2026-09-24

### Added

- **LEGENDARIES** option (default OFF). When ON, legendary and mythical
  Pokémon can appear in the wild, very rarely: 1 in 1024 encounters for a
  legendary and 1 in 2048 for a mythical, only on that species' home maps.
  - Homes are chosen from runtime data: the table's levels must fit the
    species, and so must its terrain, habitat or the map's theme. Host maps
    must reach level 30; a species gets up to 2 homes and a table hosts at
    most 3. On Red this puts Zapdos in the Power Plant, Articuno in the
    Seafoam Islands and Mewtwo in Cerulean Cave.
  - A species stops appearing once the save owns it.
  - It works in every SPAWN MODE, and the encounter keeps the level the game
    rolled.
  - Legendaries and mythicals still never enter the encounter tables.
- Exports `legendaryHomes()`. `settings()` now includes `legendaries`.

### Fixed

- Psychic types were ignored by every type-based rule (habitats, map themes,
  shared-type scoring), because the game spells the type `PSYCHIC_TYPE`.
- Legendary species no longer use their misleading PokéAPI "wild" rows
  (Let's Go's wandering birds read as common level 3–56 route Pokémon).
- 0.2.0 reshuffled every SEEDED roster by adding a field to the table RNG
  hash. SEEDED now hashes exactly as 0.1.0 did, and a test pins it. The only
  SEEDED differences from 0.1.0 are tables where the Psychic fix changes a
  pick (for example, Cerulean Cave's Hypno role now favors Psychic types).

## [0.2.0] - 2026-09-24

### Added

- **SPAWN MODE** option: SEEDED (one roster per map for the playthrough, as
  before), EVERY MAP (a map's roster is drawn again each time you enter it)
  and RANDOM (every encounter draws a new species; the game's rate, slot odds
  and level are kept).
- **SEED** row on the OPTION screen: shows the save's seed, and A opens the
  naming screen to type a new one. **REROLL SEED** draws a new random seed.
- Seeds are now short letter codes, since the Gen 1 naming screen has no
  digits. Numeric seeds from 0.1.0 still work, but see 0.3.0: this release
  accidentally reshuffled SEEDED rosters.
- Changing SPAWN MODE never changes the seed; only rerolling or typing one
  does.
- Exports `spawnMode`, `seed`, `setSeed` and `rerollSeed`. `settings()` now
  includes `spawnMode`.

## [0.1.0] - 2026-09-24

### Added

- Full redistribution of Pokémon Red's grass, cave, surf and Super Rod tables
  across Gen 1–9 species. Encounter rate, slot count, slot levels and odds are
  kept.
- **MODERN SPAWNS** (ON/OFF) and **GENERATIONS** (GEN 1 … GEN 1-9) on the
  in-game OPTION screen and in the Mod Manager.
- Rosters seeded per save, so they stay the same for a whole playthrough.
- Legendary and mythical species are never placed in wild tables.
- `data/spawn_profiles.lua`: PokéAPI-derived wild levels, habitats, terrains,
  rarity and special status, keyed by national dex number. Species without
  PokéAPI wild data get profiles estimated from runtime data.
- Framework API on `mod.exports` (`apiVersion = 1`) and the
  `mod.modern_spawns.tables_changed` event.
