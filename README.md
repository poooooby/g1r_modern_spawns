<div align="center">

# WoobleSpawns 🗺️

*A modern Pokédex in the wild. Every route, cave and lake in Kanto, Johto and Hoenn
gets fresh Pokémon from Generations 1 to 9, picked to fit the place.*

</div>

WoobleSpawns is a mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) that fills the
wild with Pokémon from across the whole series. Step into the grass on Route 1 in Red, Route 29
in Crystal or Route 101 in Emerald and you'll meet Pokémon those games never had. They still
make sense where you find them: Water types by the sea, Ghosts in Pokémon Tower and Mt. Pyre,
Bugs in the forests, Ice types in the frozen caves.

The rest is the game you know. Every map keeps its original encounter rate, levels and odds;
only the Pokémon change.

It plays on **Red, Blue, Yellow, Gold, Silver, Crystal, FireRed, LeafGreen, Ruby, Sapphire and
Emerald**.

## 🎯 Why play with it

- 🔁 **A fresh run of a game you know by heart.** Every save gets its own seed, so every
  playthrough meets different Pokémon. Share your seed and a friend gets the same world.
- 📚 **Catch them all in the region you grew up in.** By default every first-stage Pokémon in
  your range lives somewhere in the wild, and none of them is buried behind 1-in-500 odds.
- 🎛️ **Make it your own.** Choose which generations appear, how often the wild changes, and
  whether to add day and night rosters, modern trainer teams or legendaries.

## ✨ What's inside

### 🌿 Wild Pokémon that fit the place

Every species is picked for the map's levels, terrain and habitat, and late evolutions wait in
late areas. Choose how the wild behaves: **COMPLETE** puts every first stage in the wild at a
fair chance, **LIMITED** keeps one classic-feeling roster per map, **EVERY MAP** reshuffles each
time you walk in, and **RANDOM** rolls a new Pokémon every encounter. Allow every generation, or
pick any mix you like.

➡️ [Spawn modes, generations, seeds and what stays the same](docs/wild-pokemon.md)

### 🌙 Day and night

Turn on time-of-day spawns and Hoothoot, Gastly and Murkrow come out after dark while Pidgey and
Ledyba keep to the daytime. Lean the odds towards each Pokémon's own hour, or keep them strictly
to it, like Gold, Silver and Crystal.

➡️ [How day and night work](docs/day-and-night.md)

### 🥊 Modern trainer teams

Trainers, Gym Leaders, the Elite Four and your rival can field Pokémon from the generations you
allow. They keep their types and their levels. Your rival's starter is one yours can beat, and
the battle facilities join in too. Add held items that grow with your journey, so early battles
stay fair.

➡️ [Trainer teams, your rival, the battle facilities and held items](docs/trainer-teams.md)

### 👑 Rare finds

After the Hall of Fame, legendaries and mythicals can turn up on fitting maps, very rarely.
Battle the same species again and again to build a shiny chain: more of it, better shiny odds,
better stats.

➡️ [Legendaries and shiny chains](docs/rare-finds.md)

### 📟 WoobNav

With [Kanto Gear](https://github.com/AverageConsumer/kanto-gear), get the WOOBNAV app from its
Silph Store. It shows every wild Pokémon on your map with its real odds and levels, plus a
summary for each one, in light or dark mode.

➡️ [Using the WoobNav](docs/woobnav.md)

## 💾 Getting started

1. Download the latest release from the
   [Releases](https://github.com/poooooby/g1r_modern_spawns/releases) page.
2. Import it with the Gen1Recomp Mod Manager, or drop it in your mods folder.
3. Play. On its own, WoobleSpawns mixes up your game's own Pokémon: 151 in Red, Blue and
   Yellow, 251 in Gold, Silver and Crystal, and 386 in the Gen 3 games. For the newer
   generations, add the species mod for your game:
   - **Red, Blue, Yellow:** [National Dex](https://github.com/sanjinpepic/gen1recomp-national-dex),
     with its **NATIONAL DEX** option ON.
   - **FireRed, LeafGreen, Ruby, Sapphire, Emerald:**
     [WoobleDex](https://github.com/poooooby/national_dex_gen3), plus
     [WoobleSpritePack](https://github.com/poooooby/g9-battle-sprites-gen3) for battle art.

## ⚙️ Options

Open **OPTIONS → WOOBLESPAWNS**, the shortcut at the bottom of the game's own option list (or
**OPTIONS → MODS → WoobleSpawns**). Changes apply from the next encounter or battle.

| Option | Choices | Default | What it does |
|---|---|---|---|
| **MODERN SPAWNS** | ON / OFF | ON | OFF keeps the game's original wild Pokémon. |
| **GENERATIONS** | GEN 1 … GEN 1-9 / CUSTOM | GEN 1-9 | Which generations can appear, wild and on trainers' teams. CUSTOM lets you switch each one on or off. |
| **SPAWN MODE** | LIMITED / EVERY MAP / RANDOM / COMPLETE | COMPLETE | How often the wild changes. |
| **TIME OF DAY SPAWNS** | OFF / PREFER / STRICT | OFF | Day and night rosters. |
| **LEGENDARIES** | OFF / ON | OFF | Rare legendaries and mythicals after the Hall of Fame. |
| **SHINY CHAINS** | ON / OFF | ON | OFF pauses your chain and keeps it. |
| **TRAINER TEAMS** | OFF / ON / ON + ITEMS | OFF | Modern Pokémon for trainers; ON + ITEMS adds held items. |
| **SEED** | up to 10 letters | your save's | Type a seed to share or replay a world. |
| **REROLL SEED** | - / REROLL | - | Draw a new random seed for this save. |

## 🔗 Works With

- [Wilds of Hoenn](https://github.com/poooooby/wilds-of-hoenn) and
  [Wilds of Kanto Revival](https://github.com/poooooby/wilds-of-kanto-gen-3): their visible
  overworld Pokémon use WoobleSpawns' Pokémon, legendaries and shiny chains.
- [Kanto Gear](https://github.com/AverageConsumer/kanto-gear): the WOOBNAV app, and its own
  wild-encounter guide shows the Pokémon WoobleSpawns picked.
- [WoobleDex](https://github.com/poooooby/national_dex_gen3): newer Pokémon on Gen 3, the
  Pokédex AREA page for Pokémon you haven't seen, and working held items for trainer teams.

## 🪪 Credits

- Wild level, habitat and rarity data, and which Pokémon come out by day or at night:
  [PokéAPI](https://pokeapi.co/).
- Shiny chains: inspired by **TTiN** and **Untamed Tohjo**, used with permission.
- WoobNav: Kanto Gear's look and its pixel fonts by **AverageConsumer** (MIT); the fonts are
  BobsGame nD by Robert Matthew Pelloni (WTFPL) and scientifica by Akshay Oppiliappan (OFL 1.1).

---

Release history: [CHANGELOG.md](CHANGELOG.md). Building on WoobleSpawns or working on it? See
[DEVELOPMENT.md](DEVELOPMENT.md).
