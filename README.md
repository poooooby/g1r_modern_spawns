<div align="center">

# WoobleSpawns 🗺️

*A modern Pokédex in the wild. Every route, cave and lake in Kanto, Johto and Hoenn
gets fresh Pokémon from Generations 1 to 9, picked to fit the place.*

</div>

A mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp): Red, Blue, Yellow, Gold,
Silver, Crystal, FireRed, LeafGreen, Ruby, Sapphire and Emerald.

## ✨ Features

### Core Mechanics

- 🌱 **New Pokémon, same game feel:** Every wild encounter table is refilled with species from
  across the generations. Each map keeps the game's own encounter rate, levels and odds; only
  the Pokémon change.
- 🧭 **Pokémon that belong there:** Species are chosen to fit each spot's levels, terrain and
  habitat. Water types by the sea, Ghosts in Pokémon Tower and Mt. Pyre, Electric types in the
  Power Plant and New Mauville, Bugs in the forests, Ground types in the desert, Ice types in
  the frozen caves. Named places in Kanto, Johto, Hoenn and the Sevii Islands each keep their
  character, night owls stay nocturnal in Johto, and late evolutions turn up in late areas.
- 🎲 **Four ways to play:**
  - **LIMITED:** the classic feel. One set roster per map for your whole playthrough, picked to
    fit like the original games: newcomers tend to share the types of the Pokémon they
    replace, so each route and cave keeps its character.
  - **EVERY MAP:** a fresh roster each time you enter a map.
  - **RANDOM:** a new species every encounter.
  - **COMPLETE:** catch them all. Every species in your range lives somewhere, so you can catch
    the whole Pokédex in one run. The game's own Pokémon stay where they always were too (Pikachu in
    Viridian Forest, Zigzagoon on Route 101), alongside the newcomers.
- 🌱 **Seeds you can share:** Each save has its own seed. Type in a friend's seed for the same
  wild Pokémon.

### Rare Finds

- 👑 **Legendaries in the wild** (optional): Once you've entered the Hall of Fame, legendary
  and mythical Pokémon can turn up on a few fitting maps, very rarely (1 in 1024 encounters
  there, 1 in 2048 for a mythical), until you own them. On Gen 3 their Pokédex AREA page shows
  where to look before then.
- ✨ **Shiny chains:** Win or catch the same species again and again. It turns up more often
  (every encounter from a chain of 9), is likelier to be shiny (about 1 in 82 at 100) and gains
  perfect stats (1 / 2 / 3 from a chain of 10 / 25 / 40). Running from it or blacking out ends
  the chain. On Gen 3, [Wilds of Hoenn](https://github.com/poooooby/wilds-of-hoenn) adds the
  shinies and stats.
- 📖 **Pokédex AREA page** (Gen 3): shows where each species lives under your settings. With
  [WoobleDex](https://github.com/poooooby/national_dex_gen3), you can even look up
  where to find Pokémon you haven't seen yet. Legendaries with a home are marked as seen.

## ⚙️ Options

Open **OPTIONS → MODS → WoobleSpawns**. Changes apply from the next encounter.

| Option | Choices | Default | What it does |
|---|---|---|---|
| **MODERN SPAWNS** | ON / OFF | ON | OFF keeps the game's original tables. |
| **GENERATIONS** | GEN 1 … GEN 1-9 | GEN 1-9 | Which generations can appear (up to what's installed). GEN 1 shuffles the Gen 1 Pokémon. |
| **SPAWN MODE** | LIMITED / EVERY MAP / RANDOM / COMPLETE | COMPLETE | How rosters are drawn (see above). |
| **LEGENDARIES** | OFF / ON | OFF | Rare legendaries and mythicals on their home maps, after the League. |
| **SHINY CHAINS** | ON / OFF | ON | Build chains by beating one species in a row. OFF pauses it; your chain is kept. |
| **SEED** | up to 10 letters | your save's | Type a seed to share or replay a world. |
| **REROLL SEED** | - / REROLL | - | Draw a new random seed for this save. |

## 💾 Installation

1. Download the latest release from the
   [Releases](https://github.com/poooooby/g1r_modern_spawns/releases) page.
2. Import it with the Gen1Recomp Mod Manager, or drop it in your mods folder.
3. That's it: on its own, WoobleSpawns mixes up your game's own Pokémon (Red, Blue and
   Yellow's 151, Gold, Silver and Crystal's 251, the Gen 3 games' 386). For newer Pokémon, add
   the species mod for your game:
   - **Red, Blue, Yellow:** [National Dex](https://github.com/sanjinpepic/gen1recomp-national-dex),
     with its **NATIONAL DEX** option ON.
   - **FireRed, LeafGreen, Ruby, Sapphire, Emerald:**
     [WoobleDex](https://github.com/poooooby/national_dex_gen3), plus
     [WoobleSpritePack](https://github.com/poooooby/g9-battle-sprites-gen3) for battle art.

## 🔗 Works With

- [Wilds of Hoenn](https://github.com/poooooby/wilds-of-hoenn) and
  [Wilds of Kanto Revival](https://github.com/poooooby/wilds-of-kanto-gen-3): their visible
  overworld Pokémon use these tables, legendaries and shiny chains too.
- Wild-encounter guides such as Kanto Gear's show the new species.

## 📌 Good to Know

- 🎣 The Good and Super Rods catch new Pokémon too (water species only, at the game's own
  levels and odds). The Old Rod keeps the game's own catches everywhere, and Rock Smash does on
  Gen 3.
  Gold, Silver and Crystal also keep swarms, the Bug-Catching Contest, Headbutt and the roaming
  beasts.
- Early routes have the fewest suitable species, so variety grows as you go.
- On Gen 3, forms that are wild in the real games appear (Galarian and Hisuian forms, Flabébé's
  colours, Pumpkaboo's sizes and more); megas and item forms never do.

## 🪪 Credits

- Wild level, habitat and rarity data: [PokéAPI](https://pokeapi.co/).
- Shiny chains: inspired by **TTiN** and **Untamed Tohjo**, used with permission.

---

Release history: [CHANGELOG.md](CHANGELOG.md). Building on WoobleSpawns or working on it? See
[DEVELOPMENT.md](DEVELOPMENT.md).
