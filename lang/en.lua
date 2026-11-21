-- WoobleSpawns in English: the master list of the WoobNav's words (the LANGUAGE option picks
-- one of these files). The game's own text (Pokémon and place names, categories, Pokédex
-- entries, item names) stays the cart's.
--
-- Another language: copy this file to lang/<code>.lua, set `name`, and change the words on the
-- right. Keep the keys on the left and keep every %s / %d (a name or a number goes there). A
-- word left out shows in English. The file may only hold words: it can't run anything.
return {
  name = "English",
  strings = {
    -- the area list
    ["area.empty"] = "No wild Pokémon here.",
    ["area.random"] = "RANDOM: a new Pokémon every encounter here.",
    ["area.outside"] = "Step outside to scan the area.",
    ["note.own"] = "GAME'S OWN",
    ["note.random"] = "RANDOM",
    ["time.MORN"] = "MORNING",
    ["time.DAY"] = "DAY",
    ["time.NITE"] = "NIGHT",
    ["card.rare"] = "RARE",
    ["card.odds"] = "1 in %d",
    ["level.one"] = "Lv %d",
    ["level.range"] = "Lv %d-%d",

    -- a Pokémon's summary
    ["sum.number"] = "No. %03d",
    ["sum.noNumber"] = "No. ---",
    ["sum.category"] = "%s Pokémon",
    ["sum.height"] = "HT %s",
    ["sum.weight"] = "WT %s",
    ["sum.here"] = "HERE",
    ["sum.notHere"] = "Not met here now",
    ["tab.info"] = "INFO",
    ["tab.stats"] = "STATS",
    ["tab.evolves"] = "EVOLVES",
    ["sum.noEntry"] = "No Pokédex entry.",
    ["sum.noStats"] = "No stats known.",
    ["sum.total"] = "TOTAL %d",
    ["sum.noEvolution"] = "It does not evolve.",
    ["sum.ability"] = "ABILITY %s",
    ["stat.hp"] = "HP",
    ["stat.atk"] = "ATK",
    ["stat.def"] = "DEF",
    ["stat.spa"] = "SP.ATK",
    ["stat.spd"] = "SP.DEF",
    ["stat.spe"] = "SPEED",
    ["stat.spc"] = "SPCL",
    ["evo.level"] = "Lv %d",
    ["evo.trade"] = "Trade",
    ["evo.friendship"] = "Friendship",
    ["evo.item"] = "Item",

    -- the types (pills on the summary)
    ["type.NORMAL"] = "NORMAL",
    ["type.FIGHTING"] = "FIGHTING",
    ["type.FLYING"] = "FLYING",
    ["type.POISON"] = "POISON",
    ["type.GROUND"] = "GROUND",
    ["type.ROCK"] = "ROCK",
    ["type.BUG"] = "BUG",
    ["type.GHOST"] = "GHOST",
    ["type.STEEL"] = "STEEL",
    ["type.FIRE"] = "FIRE",
    ["type.WATER"] = "WATER",
    ["type.GRASS"] = "GRASS",
    ["type.ELECTRIC"] = "ELECTRIC",
    ["type.PSYCHIC"] = "PSYCHIC",
    ["type.ICE"] = "ICE",
    ["type.DRAGON"] = "DRAGON",
    ["type.DARK"] = "DARK",
    ["type.FAIRY"] = "FAIRY",
  },
}
