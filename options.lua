-- Mod Manager option schema for modern_spawns.
--
-- Declared in manifest.json's "options_schema", so the manager can render
-- these rows while the mod is disabled. main.lua hands this SAME file to
-- mod.options:define() at load time (one copy, read twice), which is what
-- gives mod.options:get() its defaults. These rows are the mod's ONLY
-- settings UI (OPTIONS -> MODS -> WoobleSpawns); nothing is added to the
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
      { "CUSTOM", "custom" },
    },
    description = "Which generations wild Pokemon (and, with TRAINER TEAMS, trainers' Pokemon) may come from. GEN 1-N: Gen 1 through N. CUSTOM: any mix (Gen 3-8, or Gen 1, 3 and 6), picked with the GEN 1 .. GEN 9 rows that appear below it. With only the game's own Pokemon (no species mod), GEN 1 shuffles Red/Blue/Yellow's 151, Gold/Silver/Crystal mix their 251 and the Gen 3 games their 386. A species mod adds more: national_dex (Red/Blue/Yellow), national_dex_gen3 (FireRed to Emerald). MODERN SPAWNS OFF gives the original tables.",
  },
  -- CUSTOM's picks: shown only while GENERATIONS is CUSTOM (the Manager has no
  -- checkbox list; visible_if keeps them in the schema and stored options)
  {
    key = "gen_1", label = "GEN 1 (KANTO)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 1 (Kanto) appear.",
  },
  {
    key = "gen_2", label = "GEN 2 (JOHTO)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 2 (Johto) appear.",
  },
  {
    key = "gen_3", label = "GEN 3 (HOENN)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 3 (Hoenn) appear.",
  },
  {
    key = "gen_4", label = "GEN 4 (SINNOH)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 4 (Sinnoh) appear.",
  },
  {
    key = "gen_5", label = "GEN 5 (UNOVA)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 5 (Unova) appear.",
  },
  {
    key = "gen_6", label = "GEN 6 (KALOS)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 6 (Kalos) appear.",
  },
  {
    key = "gen_7", label = "GEN 7 (ALOLA)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 7 (Alola) appear.",
  },
  {
    key = "gen_8", label = "GEN 8 (GALAR)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 8 (Galar) appear.",
  },
  {
    key = "gen_9", label = "GEN 9 (PALDEA)", type = "toggle", default = true,
    visible_if = { key = "max_generation", equals = "custom" },
    description = "CUSTOM GENERATIONS: ON lets Pokemon from Gen 9 (Paldea) appear.",
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
    key = "time_of_day",
    label = "TIME OF DAY SPAWNS",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "PREFER", "prefer" }, { "STRICT", "strict" } },
    description = "OFF: the same Pokemon day and night. PREFER: every map has a day and a night roster; night Pokemon (Hoothoot, Gastly, Murkrow...) are more common at night and rarer by day, day Pokemon (Pidgey, Ledyba, Sunkern...) the other way round, and nothing is ruled out. STRICT: like Gold/Silver/Crystal, Pokemon that only come out at night appear only at night and day-only ones only by day; COMPLETE still lets you catch every Pokemon at some time. Night is 8 PM to 4 AM on WoobleDex's Clock Source (In-game or Device); FireRed, LeafGreen, Red, Blue and Yellow use the device clock, Gold, Silver and Crystal their own clock (night from 6 PM).",
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
    key = "trainer_teams",
    label = "TRAINER TEAMS",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" }, { "ON + ITEMS", "items" } },
    description = "ON: trainers, gym leaders, the Elite Four, the rival and the end-game facilities field Pokemon from the generations GENERATIONS allows, chosen to fit their original teams. A gym keeps its type, and the rival's Pokemon stay the same lines from fight to fight, evolving as they level up. Levels and team sizes are the game's own. ON + ITEMS: they also hold fitting items, more as the game goes on: nothing new in the rival's first battle or from ordinary trainers early on, a Berry or booster on an early Gym Leader's strongest Pokemon, competitive items from about Lv 35, and items on every Pokemon of the Elite Four, the Champion and the rival's last battle (Gold/Silver/Crystal and the Gen 3 games; newer items like Life Orb or Eviolite need WoobleDex and a GENERATIONS range that includes them). Works whether MODERN SPAWNS is on or off, from the save's seed. OFF: the game's own teams.",
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
