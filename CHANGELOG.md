# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [Unreleased]

### Fixed

- COMPLETE encounter previews now include every species in each slot's pool and its
  registered alternate forms, weighted by the slot's odds and both selection stages.
  This updates the public `encounter.table` guide data without adding encounter slots,
  changing live tables or consuming encounter randomness.
- Gen 2 encounter previews respect the requested time of day, with DAY as the default.

## [0.13.2] - 2026-10-21

### Fixed

- **Legendaries appear on Gen 3 after the League.** 0.13.0's League check read the game-clear
  flag by name from the save snapshot, where the game never stores it, so on FireRed, LeafGreen,
  Ruby, Sapphire and Emerald a cleared save never unlocked them. It now reads the flag the way
  the game does (the live flag store, by each version's own flag number). Gen 1 and 2 were not
  affected.
- The Gen 3 surfing check behind a roll with no terrain (Emerald's rules) and the flag check
  reached engine modules through `package.loaded`, which the mod sandbox does not provide; they
  use the sandbox's `require` now.

## [0.13.1] - 2026-10-20

### Added

- **Fishing on FireRed, LeafGreen, Ruby, Sapphire and Emerald.** gen1recomp now lets mods hook
  Gen 3 fishing, so the Good and Super Rods get new species like every other table: water species
  only, at the game's own levels and odds. The Old Rod keeps the game's own catches, as on Gen 1
  and 2. In COMPLETE each rod slot also keeps the game's own fish and holds extras, so water
  species have more homes; every species is still catchable.
- Adding fishing did not move any walking or surfing roster: LIMITED's land and surf tables are
  identical to 0.13.0's (checked on FireRed and Emerald). COMPLETE's extras spread over the new
  rod slots, so its pools change.
- `tableFor` / `poolFor` answer `"fish.good"` and `"fish.super"` on Gen 3 (`"fish"` means the
  Super Rod), and `superRodFor` answers there too.

## [0.13.0] - 2026-10-20

### Changed

- **Places keep their character.** Hoenn's and the Sevii Islands' named places have themes of
  their own (they all read as plain routes before): Mt. Pyre and the Lost Cave draw Ghosts,
  New Mauville Electric and Steel types, Petalburg Woods and Berry Forest Bugs and Grass types,
  Route 111's desert Ground types, Shoal Cave and Icefall Cave Ice types, plus Granite Cave,
  Meteor Falls, Fiery Path, Jagged Pass, Mt. Ember, Sky Pillar, Tanoby and more. Gen 3 towns and
  sea routes read as towns and sea.
- **Fit comes before variety.** On a themed map (a theme type, or a cave, forest, ruins, snow,
  desert, mountain, water or coast habitat) the first-choice candidates must share the theme; a
  shared "route" tag no longer counts as a habitat match (nearly every species has one), and
  the map's theme type weighs twice as much. Measured over Emerald and FireRed seeds, themed
  places went from mixed rosters (Mt. Pyre: Shellos and Spritzee; New Mauville: Arcanine) to
  85-100% on theme, with the variety checks still met.
- **Indoor and look-alike places are read correctly** (FireRed/LeafGreen, Ruby/Sapphire/Emerald):
  Pokémon Tower, the Pokémon Mansion, the Power Plant, Mt. Pyre's floors and the S.S. Anne no
  longer count as grassy routes, and New Mauville, Sky Pillar and the Abandoned Ship no longer
  count as caves (the game flags them underground). Route 112 is a mountain route. An audit
  confirmed every wild map in all five Gen 3 games gets generated tables.
- **LIMITED is the classic mode.** It draws from a tighter shortlist (best 12 within 20 points,
  was 24 within 30) and favours a newcomer that shares the types of the Pokémon it replaces, so a
  route keeps its original character. Two seeds now share about 12-15% of their LIMITED
  species (5% before). EVERY MAP, RANDOM and COMPLETE keep their wider draw, so LIMITED and
  COMPLETE no longer share their main species on one seed. The variety checks for LIMITED now
  bar any newcomer from dominating a route, and cap how much of it the game's own species win
  back (35% of Route 101, 50% of Crystal's Route 29, where only Gen 1-2 species exist).
- **COMPLETE's extra species respect themes.** A species that misses a themed map's theme goes
  to a map it fits or a plain route first (it could land in Mt. Pyre or Artisan Cave before:
  3.3% of extras on themed Emerald maps, now 0%). Every species is still catchable: checked on
  Emerald, FireRed, Red (with and without National Dex) and Crystal, every GENERATIONS setting,
  regional forms counted one by one.
- **This reshuffles existing LIMITED and COMPLETE rosters** on every game (the pinned fixture in
  the generator test moved), so a save's wild Pokémon change once after updating.
- **Legendaries wait for the League.** With LEGENDARIES ON, legendaries and mythicals appear
  only once the save has entered the Hall of Fame (Gen 1 and 2) or set the game-clear flag
  (Gen 3). Their homes still show on the Pokédex AREA page before then.

### Added

- **COMPLETE keeps the original Pokémon.** Each slot's pool also holds the species the game
  itself had there (when it's under the GENERATIONS cap), so Viridian Forest's Pikachu or
  Route 101's Zigzagoon stay catchable where they always were, alongside the newcomers.

## [0.12.0] - 2026-10-10

### Added

- **Regional forms of the original Pokemon** (National Dex Gen 3 0.8): the Alolan, Galarian,
  Hisuian and Paldean forms are wild candidates of their own, like the Galarian and Hisuian forms
  of the newer species. The legendary Galarian birds and Hisuian Typhlosion (a starter) are left
  out. Hisuian Qwilfish is now wild too.
- A regional form counts in the generation of its region (Alola 7, Galar and Hisui 8, Paldea 9),
  not its base species', so a Gen 1-3 or Gen 1 cap leaves it out.

- **Shiny chains.** Win or catch the same species again and again and the chain grows:
  - It turns up more often wherever it can be met: 1 in 8 encounters at 2, every encounter
    from 9. This works for step encounters and, through `chainSpeciesFor`, for a consumer's
    visible spawns.
  - It's more likely to be shiny (`1 - (8191/8192)^count`, about 1 in 82 at 100).
  - It gets 1 / 2 / 3 perfect stats from 10 / 25 / 40.
  - Running from it or blacking out ends the chain. It's kept with the save and works while
    MODERN SPAWNS and the new SHINY CHAINS option (default ON) are on. With SHINY CHAINS off,
    nothing is counted or changed, and a chain in progress is kept for later.
  - New exports: `chain`, `chainSpeciesFor`, `chainBonus`, `chainRecord`. The shiny and the
    stats are applied by the game-family mod (Wilds of Hoenn on Gen 3).

  Inspired by TTiN and Untamed Tohjo, used with permission.

- **Works with no species mod at all.** `national_dex` and `national_dex_gen3` are now optional:
  with only the game's own Pokémon, Red/Blue/Yellow shuffle their 151 and Emerald (and the other
  Gen 3 games) mix their 386. A species mod still widens the pool.
- **GEN 1 shuffles Gen 1** instead of meaning "the original tables". MODERN SPAWNS OFF is the way
  back to the original tables.
- **COMPLETE is the default SPAWN MODE**, so every species in range is catchable out of the box.
  A mode already chosen in the Mod Manager is kept; a save that never chose one starts in
  COMPLETE. Checked: Red with no species mod puts all 146 non-legendary species somewhere, and
  Emerald all 365.
- `mod.exports.apiVersion` is 2: `isActive()` is now true on GEN 1 and with only the cart's
  species, and `maxGeneration()` can answer 1.

- **Gold, Silver and Crystal are supported again**, on their own 251 Pokémon. `national_dex`
  can no longer add species past #251 on Gen 2 (gen1recomp's Gen 2 schema change), which is
  why 0.11.0 marked them incompatible; with no species mod required they work again, mixing
  Gen 1-2.

### Changed

- Gen 2 grass tables whose every slot held one species (Ruins of Alph's Unown) split by slot
  position, as Gen 3 one-species tables do, keeping each species the same morning, day and
  night.

## [0.11.1] - 2026-10-10

### Changed

- **Tables that held only one species now get several.** A table whose every slot held the
  same Pokémon (Sootopolis City's surf table is five Magikarp, Route 19's all Tentacool) used
  to become a single species, which could even be the original one again. Each slot now gets
  its own species, at the cart's own odds per slot. In every mode: on one test seed
  Sootopolis surfing went from 1 species to 5 in LIMITED, 43 in EVERY MAP, 73 in RANDOM and
  8 in COMPLETE. LIMITED rosters change once on existing saves (the seed is kept), on these
  maps and, through the rolling history, on the maps after them.
- When a roll could have come from several such slots, one is picked by the cart's odds, so
  each slot's Pokémon appears as often as its slot does.

### Fixed

- **FireRed, LeafGreen, Ruby, Sapphire and Emerald: wild Pokémon stuck on the same few
  species** (mostly Charmander), in every mode. Live sync wrote Modern Spawns' species names
  into the game's own encounter tables, where the cart stores a species *number*, and the
  game rolls from those tables. Each roll then had no real species and fell back to the
  wrong one. Live sync now writes the number, as the cart does.
- **RANDOM and COMPLETE did not redraw per encounter on Gen 3.** With the game's tables
  synced, a roll no longer matched the cart's original table, so the per-encounter draw
  (RANDOM) and the slot's pool (COMPLETE) were skipped. A roll is now matched against the
  synced table too.
- The same fix lets Wilds of Hoenn's visible spawns and Kanto Gear's wild-encounter guide
  read those tables correctly.
- **Surfing kept the original game's Pokémon** (for example only Magikarp in Sootopolis City)
  when the game reported a surfing step without saying it was on water: Modern Spawns looked
  for the roll in the land table, found nothing, and left it alone. A surfing roll is now
  read as a water roll, and a roll that matches neither table is logged once per map.
- New for those reports: one log line per map when a roll matches no slot, naming the map,
  the rolled Pokémon and its terrain.

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
