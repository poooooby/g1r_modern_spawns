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
    description = "Which generations wild Pokemon may come from. GEN 1 keeps the game's original tables. Species past #151 need national_dex with its NATIONAL DEX option ON; without them the original tables are kept.",
  },
  {
    key = "spawn_mode",
    label = "SPAWN MODE",
    type = "choice",
    default = "seeded",
    choices = { { "SEEDED", "seeded" }, { "EVERY MAP", "map" }, { "RANDOM", "random" } },
    description = "SEEDED: each map keeps one roster for the whole playthrough. EVERY MAP: a map's roster is drawn again each time you enter it. RANDOM: every encounter draws a new species (still suited to the level and terrain). All three use the save's seed, which only changes when you reroll it or type one below.",
  },
  {
    key = "legendaries",
    label = "LEGENDARIES",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" } },
    description = "ON: legendary and mythical Pokemon can appear in the wild, only on a few maps that suit them (level, terrain, habitat), and very rarely: 1 in 1024 encounters there for a legendary, 1 in 2048 for a mythical. Each one stops appearing once you own it. OFF: never in the wild.",
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
    description = "The seed every spawn draw comes from, one per save. Press A to type a new one (letters, up to 10). The same seed and settings always give the same SEEDED tables, so seeds can be shared. It is kept with your next SAVE.",
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
