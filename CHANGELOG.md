# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.20.1] - 2026-11-22

### Fixed

- **TRAINER TEAMS: Team Magma and Team Aqua keep their element** (user report: the Magma
  leaders fielded Water types). A trainer outside the Gyms only had to share one type with
  each original Pokémon, so Maxie's Mightyena (Dark) could become a Sharpedo (Water/Dark) and
  Tabitha's Golbat a Toxapex. Every grunt, admin and leader of Team Magma now shows Fire or
  Ground types and never a Water one; Team Aqua shows Water types and never a Fire one
  (`Trainers.TEAM_THEMES`, from the trainer class; a branching family takes a branch of the
  theme too). Sharing a type with the original still ranks a family first within the theme
  (Mightyena becomes a Houndoom). Verified over 12 seeds on Emerald and Ruby at GEN 1, 1-3 and
  1-9: no Pokémon off theme.

Existing saves get new Magma and Aqua teams (`ALGO` 4). Every other trainer's team is
byte-identical (diffed every Emerald, Ruby and FireRed trainer before and after; Red and
Crystal digests unchanged; FireRed's only changes are its unused Hoenn placeholder entries),
and wild output is unchanged.

## [0.20.0] - 2026-11-20

### Added

- **LANGUAGE** option (user request: "a language option matching WoobOS"): the WoobNav in
  English, Deutsch, Español, Français, Italiano, 日本語 or Português (BR), WoobOS's and Kanto
  Gear's seven languages. Its words live in `lang/*.lua`, one data file per language, with
  English filling anything a file leaves out. The game's own text (Pokémon and place names,
  categories, Pokédex entries) stays as it is. Japanese draws kana from Fusion Pixel 8px, the
  face Kanto Gear uses, at the WoobNav fonts' own size.
- The WoobNav's Kanto Gear Store tile in Brazilian Portuguese (it follows Kanto Gear's language).

Switching LANGUAGE changes no spawn: wild and trainer output are unchanged, and no table is
redrawn (EVERY MAP keeps its rosters).

## [0.19.0] - 2026-11-20

The stable release of the 0.18.x betas, with no further changes. Coming from 0.17.0:

- **WoobNav**, a DexNav-style Kanto Gear app (0.18.0): every wild Pokémon on your map, its
  odds, levels and how it's met, and a summary page per species.
- WoobNav steps aside in battles so Kanto Gear's battle controls take over, and comes back after
  (0.18.1).
- WoobNav night mode: a moon/sun button switches light and dark, kept with your save (0.18.2).
- **COMPLETE: no Pokémon on any map under a 5% chance**, TIME OF DAY SPAWNS or not (0.18.2).
  This reshuffles COMPLETE rosters on saves from 0.17.0 or earlier; LIMITED, EVERY MAP, RANDOM
  and trainer teams are unchanged.
- `exports.encounters`, `exports.currentMap` and `exports.areaName`: the odds per map, for other
  mods (0.18.0).

## [0.18.2] - 2026-11-20

### Changed

- **COMPLETE: no Pokémon on any map under a 5% chance** (user report: the WoobNav showed 1%
  surfing and fishing catches on Route 111 and 3-4% walking ones). 0.16.0 only made sure each
  species had 5% or more *somewhere*. Two things still showed lower on a map:
  - The game's smallest slots (Gen 3's 4% and 1% slots on land, water and the Super Rod;
    Gen 2's 4% and 1%; Gen 1's two rarest) each held a species of their own. Such a slot now
    carries the species and pool of the biggest slot out at the same times, so it adds to a
    Pokémon you already meet at 5% or more. The slot odds and levels are still the game's.
  - TIME OF DAY SPAWNS leans a pool 3:1 towards the Pokémon out at this hour, which could
    leave the others at 2-4%. The lean now stops at 5%: nobody that may come out drops
    under it.

  **This reshuffles COMPLETE rosters on existing saves** (COMPLETE's pinned fixture moved from
  5e880f5a to c09f243f). LIMITED, EVERY MAP and RANDOM rosters and trainer teams are unchanged.
  Every species is still catchable somewhere. Checked on every map of Red, Crystal, FireRed
  and Emerald, with TIME OF DAY SPAWNS off, PREFER and STRICT.

### Added

- **WoobNav night mode** (user request). A button in the top-right corner of both WoobNav pages
  switches between light and dark: a moon in light mode, a sun in dark mode. Dark mode uses
  Kanto Gear's own dark Pokégear colours. The choice is kept with the save, the same way Kanto
  Gear keeps its Home screen.

## [0.18.1] - 2026-11-20

### Changed

- **WoobNav steps aside for battles** (user request, as NaviPlay's apps do). While a battle runs
  it reports itself not shown, so Kanto Gear takes the screen back for its battle controls. It
  stays open underneath and returns on its own when the battle ends, its list refreshed.
  Battles are detected by the Gen 3 engine's battle module, or a battle screen on the Gen 1/2
  game's screen stack.

## [0.18.0] - 2026-11-20

### Added

- **WOOBNAV, a DexNav-style Kanto Gear app** (user request). With Kanto Gear installed, a WOOBNAV tile joins
  its Silph Store. It shows every wild Pokémon on the player's current map at Kanto Gear's
  bottom-screen size (240x216), in its pixel style and with its fonts:
  - six cards a page (sprite, name, chance, levels, how it's met), with page buttons and swipes;
  - COMPLETE's pooled species listed with the share each one gets of its slot, not just the
    first species in each slot;
  - a summary per species (number, types, category, height and weight, Pokédex entry, base
    stats, evolution line, Gen 3 abilities, where it's met on the map at each time of day);
  - a back button in the top-left corner that returns to the list, then to Kanto Gear.

  It follows Kanto Gear's DISPLAY MODE (second screen, handheld, combined screen, fullscreen; phone
  as combined). It is driven by touch or mouse only, so the buttons stay with the game. Without
  Kanto Gear nothing registers and no hook is installed. It reads the tables and never changes a
  roll: wild and trainer output is byte-identical (golden probe on Red, Crystal, FireRed and
  Emerald).
- **API: per-map odds.** `encounters(mapId?, { period?, time? })` lists every species on a map,
  method by method, with its chance in percent, its levels and whether a COMPLETE pool supplies
  it. Odds use the game's own slot odds, and COMPLETE's pools are split as the encounter hook
  draws them (TIME OF DAY SPAWNS weights included). Legendaries waiting there are listed under
  `rare`. Unlike the other functions, it also answers while inactive, from the game's own tables.
  - `currentMap()` gives the player's map; `areaName(mapId)` gives its place name.
  - These are additions only, so apiVersion stays 3.
  - WoobOS's Pokédex can read these instead of working out its own percentages.

## [0.17.0] - 2026-11-19

### Added

- **CUSTOM GENERATIONS.** GENERATIONS gains a last choice, CUSTOM, which shows a GEN 1 (KANTO)
  … GEN 9 (PALDEA) switch for each generation right under it (hidden again for any other
  choice). Pick any mix: Gen 3-8, or Gen 1, 3 and 6. It covers wild Pokémon in every SPAWN MODE,
  COMPLETE's catch-them-all guarantee (every species of the picked generations is catchable or
  evolves from one that is), legendary homes, TRAINER TEAMS and its held items (only items of
  the picked generations, plus the game's own). Every switch starts ON, so CUSTOM begins as
  GEN 1-9.
  - Trainers step through a left-out stage: with Gen 2 and 4 only, a Happiny grows straight
    into Blissey (Chansey is Gen 1).
  - Every switch off, or only generations no species mod adds: the game's original tables.
- **API:** `generations()` (the generations in force, ascending), `settings().generations`,
  `trainerTeams().generations`, `tables_changed`'s `generations`, `candidates({ generations })`.

### Changed

- **TRAINER TEAMS' held items (ON + ITEMS) grow with the journey** instead of every boss Pokémon
  holding one from the first Gym (user request: fair for a regular player, and sensible for the
  world). By how far into the game a battle is (its strongest Pokémon's level):
  - the rival's first battle: nothing new;
  - ordinary trainers: nothing before Lv 20, then one item half the time, from Lv 35 one or
    two; a Berry or a type booster only (they used to have a 1-in-5 chance per Pokémon of
    either, from the start);
  - Gym Leaders, the rival and team bosses: the strongest Pokémon always holds something (a
    Berry or its type booster before Lv 20, also Leftovers / Black Sludge before Lv 35,
    competitive items such as Life Orb, Choice items, Focus Sash, Eviolite and Assault Vest
    after); each of the others 40% of the time mid-game, 70% late;
  - the Elite Four, champions and the rival's final battle: every Pokémon, any item.
  Measured over every story trainer on Crystal and Emerald (`trainers_items_test`). Teams and
  wild Pokémon are unchanged.
- **Fixed: a team could hold two of one item** when two names are one item (Gold's
  MIRACLEBERRY is the Lum Berry: Emerald's Drake held two). Items are now told apart by the
  game's item number.
- **TRAINER TEAMS' held items follow WoobleDex's Move Split.** With Move Split on (Gold, Silver,
  Crystal and the Gen 3 games), Choice Band and Choice Specs are handed out by each move's own
  physical / special class, as the battles then work it out: a Gengar with Shadow Ball and
  Sludge Bomb is a special attacker, a Houndoom with Crunch and Fire Punch a physical one. With
  Move Split off (or without WoobleDex), the game's own split by type, unchanged.
- **API: `apiVersion` 3.** `maxGeneration()` is the highest generation in force, no longer
  "every generation up to it"; read `generations()` for the set.
- GEN 1 … GEN 1-9 are unchanged, byte for byte: wild tables in every mode and TIME OF DAY
  SPAWNS, trainer teams and items (measured on Red, Crystal, FireRed and Emerald at GEN 1, 3
  and 9). CUSTOM with every switch ON is GEN 1-9 exactly.

## [0.16.1] - 2026-11-19

### Changed

- **TRAINER TEAMS: your rival's starter loses to yours.** In the original games the rival takes
  the starter that beats yours, which was harsh once modern starters arrive knowing their own
  type's attack. The rival's starter line now becomes a starter line YOUR starter beats: pick
  Bulbasaur and the rival leads with a Water line, Charmander a Grass line, Squirtle a Fire
  line. No stage of it resists your starter's type (Empoleon's Steel would shrug off Grass, so
  Piplup's line is never the pick against Bulbasaur). Covers Red, Blue, Gold, Silver, Crystal,
  FireRed and LeafGreen's rival and May and Brendan on Ruby, Sapphire and Emerald (Yellow's
  Eevee is no starter and is left as it was). At GEN 1, Red's three starters trade places.
- **The rival's starter evolves when the original does.** In every fight it shows the same
  stage as the rival's original starter (a first stage while the original is still a
  Charmander, a final stage when it is a Charizard), instead of evolving on its own line's
  levels.
- **Reshuffles existing saves' rival teams once** (the rival's other lines can change too:
  its starter is now picked first). Other trainers, the facilities and every wild table are
  unchanged.

## [0.16.0] - 2026-11-18

### Changed

- **COMPLETE: no wild Pokémon is buried under 1-in-500 odds.** Every species you can find in
  the wild has at least a 5% chance per encounter somewhere (Emerald at GEN 1-9: 0 species under
  5%, down from 447; 76 were under 1%). Measured on Emerald (two seeds), FireRed and Red.
  - **A slot's pool is sized by its odds.** A 40% slot shares among up to 8 species, a 1% slot
    holds just its main species.
  - **Evolved Pokémon are left to evolving.** Every first-stage Pokémon still lives in the wild;
    a species that evolves from one you can catch gets no home of its own, and the main species
    lean toward first stages. Of the evolved ones left, final forms (Raichu, Persian) come before
    middle stages (Ivysaur, Pidgeotto), and a slot too rare to give anyone 5% always holds a
    first stage. Emerald at GEN 1-9: 81 evolved species in the wild, down from 493 (middle
    stages: 17, down from 116).
  - **Fewer repeats.** The game's own Pokémon keep up to 3 of their old homes instead of every
    one (Tentacool was in 80 tables, now 10), and a main species already placed elsewhere is
    picked less often.
  - **With TIME OF DAY SPAWNS,** a slot with room for one species keeps the same one day and
    night (a day-only one under STRICT still gets a night partner), so the 5% holds at every
    hour: measured with PREFER and STRICT on Red, Crystal, FireRed and Emerald.
  - **Reshuffles existing COMPLETE saves' wild Pokémon once** (same seed, new rosters). LIMITED,
    EVERY MAP and RANDOM are unchanged, byte for byte.
- **API:** `profileOf` / `candidates` entries carry `evolvesFrom`, the species one evolves from.

## [0.15.1] - 2026-11-17

### Added

- **A WOOBLESPAWNS shortcut on the OPTION screen.** One row at the bottom of the game's own
  option list (Red/Blue/Yellow, Gold/Silver/Crystal, FireRed/LeafGreen, Ruby/Sapphire/Emerald)
  opens WoobleSpawns' settings page in the Mod Manager; B returns to OPTION. The settings
  themselves still live on that page.

## [0.15.0] - 2026-11-17

### Added

- **TRAINER TEAMS** (OFF / ON / ON + ITEMS, default OFF). Trainers, Gym Leaders, the Elite
  Four, champions and the rival field Pokémon from the generations GENERATIONS allows, chosen
  to fit their original teams:
  - **Gyms and the Elite Four keep their type.** Brock, Falkner and Roxanne stay Rock, Flying
    and Rock; Phoebe and Agatha stay Ghost. Where a cart has too few lines of a type (Karen
    with Crystal's own 251), one may keep its original Pokémon.
  - **Gyms and the Elite Four lean stronger.** Their picks aim a little above each original
    Pokémon's base stat total, so they favour the stronger lines of their type without
    jumping a tier (Brock's Lv 12 Pokémon stay unevolved). Over 20 seeds on Red, their
    Pokémon average 488 against the originals' 444. Other trainers stay close to their
    originals' strength.
  - **One line per Pokémon, per trainer.** Each original evolution line maps to one new line
    for every fight of that trainer. The rival's lines carry across every fight, including
    FireRed's champion battle, and evolve as their levels rise (non-level evolutions at
    Lv 25 / 35, never below the original's stage).
  - **Levels and team sizes are the game's own.** Legendary and mythical Pokémon never join a
    team.
  - **Movesets.** A Pokémon the game gave custom moves gets a set built from its new species'
    level-up moves: its best same-type attacks, one coverage move and one status move.
  - **Battle facilities.** Each facility uses one one-to-one species map per save, so its own
    draws pick the same sets as before and stay consistent (the Dome's brackets, the
    Factory's rentals, hints and swaps). Each set keeps its item, nature, EVs and IVs and gets
    a built moveset. Covered:
    - Crystal's Battle Tower;
    - Emerald's Battle Frontier (all seven facilities), the Battle Tents, and the Pyramid's
      and Pike's wild Pokémon (which keep up to two of their status moves);
    - Trainer Hill;
    - Ruby and Sapphire's Battle Tower;
    - FireRed and LeafGreen's Trainer Tower.
  - **Left alone:** other players' teams (record mixing, secret bases), e-Reader trainers and
    link battles.
- **ON + ITEMS: held items.**
  - **Bosses** (Gym Leaders, the Elite Four, champions, the rival, team leaders): the
    highest-level Pokémon gets an ace item (Leftovers, or a newer one that suits it better),
    the rest a type booster or a Berry.
  - **Other trainers:** about a 1 in 5 chance of a Berry or type booster.
  - **Kept:** the game's own held items.
  - **Gated by generation:** an item is handed out only when it exists in the running game,
    has a working held effect (the cart's own, or WoobleDex's newer items) and its generation
    is within GENERATIONS (the cart's own items always are). Life Orb, Choice Specs and Scarf,
    Focus Sash and Black Sludge need GEN 4, Eviolite GEN 5, Assault Vest GEN 6. Each goes to a
    Pokémon it suits: Black Sludge only to Poison types, Eviolite only to one that can still
    evolve within the range.
  - **Red, Blue and Yellow** have no trainer items, so ON + ITEMS plays like ON there.
- **API (additive; `apiVersion` stays 2):**
  - `settings().trainerTeams`;
  - `trainerTeams()` → `{ mode, maxGeneration, active }`;
  - `trainerTeamFor(class, id, party)` and `trainerIdentity(class, id, party)`;
  - `facilitySpecies(name)`.

### Unchanged

- **Wild Pokémon.** TRAINER TEAMS never touches the wild tables' RNG or memory; every wild
  table, pool and draw is identical with it OFF, ON or ON + ITEMS. This was checked against
  the recorded 0.14.0 digests.
- **OFF, the default,** leaves every battle and facility exactly as the game builds it. On
  Gen 3 no `trainer.party` wrapper is installed at all.

## [0.14.0] - 2026-11-13

### Added

- **TIME OF DAY SPAWNS** (OFF / PREFER / STRICT, default OFF). Every map gets a day roster and a
  night roster:
  - Hoothoot, Gastly, Murkrow and the other night species come out after dark.
  - Pidgey, Ledyba, Sunkern and the other day species keep to the daytime.
  - **PREFER** weights them toward their own time: about 4x as common in their own roster in
    LIMITED, and about 2x as likely in a COMPLETE draw. Nothing is ruled out.
  - **STRICT** keeps the species that only come out at night (or by day) to that time, like
    Gold/Silver/Crystal. COMPLETE still makes every species catchable at some hour.
  - The night roster keeps a slot's day species out after dark unless it is a day species, so a
    route reads as the same place at night.
- **The clock.** Night is 8 PM to 4 AM, the same clock WoobleDex uses:
  - **Ruby, Sapphire and Emerald** follow WoobleDex's Clock Source: In-game (the cart's clock)
    or Device.
  - **FireRed, LeafGreen, Red, Blue and Yellow** use the device clock.
  - **Gold, Silver and Crystal** use their own clock, whose night starts at 6 PM, matching the
    game's own night slots.
  - When the clock turns, the tables the game and other mods read (live sync) switch roster.
- **`data/time_of_day.lua`**, which says which species keep to the day or the night:
  - **#1-493:** PokéAPI's encounter conditions from the games with a clock (Gold/Silver/Crystal,
    HeartGold/SoulSilver, Diamond/Pearl/Platinum). 26 species are night-only or day-only, and
    about 160 lean one way.
  - **Newer species** lean the way their own Pokédex entries describe, after our own review
    (`pokemon_spawn_generator/time_of_day_overrides.py`).
  - **A family member** with no evidence of its own follows its family (Gengar after Gastly and
    Haunter).
  - **The pipeline** writes it with `generate_spawn_data.py --time-of-day`; `spawn_profiles.lua`
    is untouched.
- **API (additive; `apiVersion` stays 2):**
  - `settings().timeOfDay` and `period()` ("day"/"night" on the clock);
  - an optional `period` argument on `tableFor`, `drawFor`, `poolFor` and `explain`;
  - `timeOfDay` / `timeOfDayOnly` on `candidates()` and `profileOf()`;
  - the event `mod.modern_spawns.period_changed { period, previous }`.

### Unchanged

- **OFF, the default, leaves every table, pool, draw and seed exactly as in 0.13.x.** This was
  checked against digests recorded before the change, on Red, Crystal, FireRed and Emerald in
  LIMITED, COMPLETE and RANDOM.
- Existing saves only see new rosters once TIME OF DAY SPAWNS is turned on.

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
