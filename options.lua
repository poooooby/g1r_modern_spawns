-- Mod Manager option schema for modern_spawns.
--
-- Declared in manifest.json's "options_schema", so the manager can render
-- these rows while the mod is disabled. main.lua hands this SAME file to
-- mod.options:define() at load time (one copy, read twice), which is what
-- gives mod.options:get() its defaults. These rows are the mod's ONLY
-- settings UI (OPTIONS -> MODS -> Modern Spawns); nothing is added to the
-- top-level OPTION screen.
return {
  {
    key = "enabled",
    label = "MODERN SPAWNS",
    type = "choice",
    default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    description = "ON: every wild encounter table is redistributed across the species GENERATIONS allows. The game's own rates, slot levels and odds are kept; only the species change. OFF: the game's original tables.",
  },
  {
    key = "max_generation",
    label = "GENERATIONS",
    type = "choice",
    default = "9",
    choices = {
      { "GEN 1", "1" }, { "GEN 1-2", "2" }, { "GEN 1-3", "3" },
      { "GEN 1-4", "4" }, { "GEN 1-5", "5" }, { "GEN 1-6", "6" },
      { "GEN 1-7", "7" }, { "GEN 1-8", "8" }, { "GEN 1-9", "9" },
    },
    description = "Which generations wild Pokemon may come from. With only the game's own Pokemon (no species mod), GEN 1 shuffles Red/Blue/Yellow's 151, Gold/Silver/Crystal mix their 251 and the Gen 3 games their 386. A species mod adds more: national_dex (Red/Blue/Yellow), national_dex_gen3 (FireRed to Emerald). MODERN SPAWNS OFF gives the original tables.",
  },
  {
    key = "spawn_mode",
    label = "SPAWN MODE",
    type = "choice",
    default = "complete",
    choices = { { "LIMITED", "seeded" }, { "EVERY MAP", "map" }, { "RANDOM", "random" },
                { "COMPLETE", "complete" } },
    description = "LIMITED: each map keeps one roster for the whole playthrough. EVERY MAP: a map's roster is drawn again each time you enter it. RANDOM: every encounter draws a new species (still suited to the level and terrain). COMPLETE: every species GENERATIONS allows lives somewhere, so the whole dex can be caught; each slot holds a few species that share its odds. All four use the save's seed, which only changes when you reroll it or type one below.",
  },
  {
    key = "legendaries",
    label = "LEGENDARIES",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" } },
    description = "ON: legendary and mythical Pokemon can appear in the wild, only on a few maps that suit them (level, terrain, habitat), and very rarely: 1 in 1024 encounters there for a legendary, 1 in 2048 for a mythical. Each one stops appearing once you own it. Except under RANDOM, every one is marked as seen in the Pokedex (like a roaming legendary after the news report) so its AREA page shows where to look. OFF: never in the wild.",
  },
  {
    key = "shiny_chain",
    label = "SHINY CHAINS",
    type = "choice",
    default = "on",
    choices = { { "ON", "on" }, { "OFF", "off" } },
    description = "ON: win or catch the same species again and again to build a chain. The longer it gets, the more often that species appears (every encounter from 9 in a row), the likelier it is to be shiny, and from 10 / 25 / 40 it has 1 / 2 / 3 perfect stats. Running from it or blacking out ends the chain. Shinies and stats need a mod that applies them (Wilds of Hoenn). OFF: nothing is counted or changed; a chain you had is kept for later.",
  },
  {
    -- Mirrors the loaded save's seed (src/runtime.lua keeps it in sync);
    -- typing one here sets that save's seed, or the next NEW GAME's when
    -- typed from the title screen. Empty never clears a seed.
    key = "seed",
    label = "SEED",
    type = "text",
    maxLen = 10,
    default = "",
    description = "The seed every spawn draw comes from, one per save. Press A to type a new one (letters, up to 10). The same seed and settings always give the same LIMITED and COMPLETE tables, so seeds can be shared. It is kept with your next SAVE.",
  },
  {
    -- An action, not a setting: stepping to REROLL draws a new seed, and the
    -- row snaps back to "-" (the manager has no button row type).
    key = "reroll_seed",
    label = "REROLL SEED",
    type = "choice",
    default = "idle",
    choices = { { "-", "idle" }, { "REROLL", "reroll" } },
    description = "Step right to REROLL to draw a new random seed for this save. Changing SPAWN MODE never changes the seed; only this or typing a SEED does.",
  },
}
