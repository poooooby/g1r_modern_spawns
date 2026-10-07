# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

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
