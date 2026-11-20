-- WoobNav in Kanto Gear's Silph Store: the spec for the Gear's third-party module hook
-- (kanto_gear exports.modules.register, api 1). Everything here is the WoobNav's own: the icon
-- (the Gear's 24x24 pal/rows pixel format; `o` is the Gear's outline), the words and their
-- translations; `open` and `shown` come from src/woobnav/init.lua.

local function available(ctx)
  return ctx ~= nil and (ctx.gen3 == true or ctx.generation == 1 or ctx.generation == 2 or ctx.generation == 3)
end

return function(deps)
  return {
    id = "woobnav",
    label = "WOOBNAV",
    category = "TOOLS",
    description = {
      "EVERY WILD POKEMON HERE.",
      "ODDS, LEVELS AND DEX INFO.",
      "POWERED BY WOOBLESPAWNS.",
    },
    -- a handheld scanner: a radar ring with its sweep and two blips on a green screen, a red
    -- casing, two buttons (every mark kept inside the screen)
    icon = { pal = {
      a = "e04838", b = "a82818", c = "f47c64",
      g = "1d3b2e", h = "2f8c76", l = "c4f5a6", m = "6fd08a",
      s = "cdd6d0", t = "6a7a72", w = "ffffff", y = "f8c048",
    }, rows = {
      "........................",
      "....oooooooooooooooo....",
      "...occcccccccccccccco...",
      "...oaoooooooooooooobo...",
      "...oaoggggggggggggobo...",
      "...oaoggghhhhhhgggobo...",
      "...oaogghhgggghmggobo...",
      "...oaoghhygggmlhhgobo...",
      "...oaoghggggmlgghgobo...",
      "...oaoghgggllggghgobo...",
      "...oaoghgggmgggghgobo...",
      "...oaoghggggggwghgobo...",
      "...oaoghhgggggghhgobo...",
      "...oaogghhgggghhggobo...",
      "...oaoggghhhhhhgggobo...",
      "...oaoggggggggggggobo...",
      "...oaoooooooooooooobo...",
      "...oaaaaaaaaaaaaaaabo...",
      "...oaaasssaaaatttaabo...",
      "...oaaasssaaaatttaabo...",
      "...oaaaaaaaaaaaaaaabo...",
      "...obbbbbbbbbbbbbbbbo...",
      "....oooooooooooooooo....",
      "........................",
    } },
    accent = "green",
    available = available,
    shown = deps.shown,
    open = deps.open,
    translations = {
      de = {
        ["WOOBNAV"] = "WOOBNAV",
        ["TOOLS"] = "WERKZEUGE",
        ["EVERY WILD POKEMON HERE."] = "Alle wilden Pokémon hier.",
        ["ODDS, LEVELS AND DEX INFO."] = "Chancen, Level und Pokédex-Infos.",
        ["POWERED BY WOOBLESPAWNS."] = "Eine WoobleSpawns-App.",
      },
      es = {
        ["WOOBNAV"] = "WOOBNAV",
        ["TOOLS"] = "HERRAMIENTAS",
        ["EVERY WILD POKEMON HERE."] = "Todos los Pokémon salvajes de aquí.",
        ["ODDS, LEVELS AND DEX INFO."] = "Probabilidades, niveles y datos de la Pokédex.",
        ["POWERED BY WOOBLESPAWNS."] = "Una aplicación de WoobleSpawns.",
      },
      fr = {
        ["WOOBNAV"] = "WOOBNAV",
        ["TOOLS"] = "OUTILS",
        ["EVERY WILD POKEMON HERE."] = "Tous les Pokémon sauvages d'ici.",
        ["ODDS, LEVELS AND DEX INFO."] = "Chances, niveaux et infos du Pokédex.",
        ["POWERED BY WOOBLESPAWNS."] = "Une application WoobleSpawns.",
      },
      it = {
        ["WOOBNAV"] = "WOOBNAV",
        ["TOOLS"] = "STRUMENTI",
        ["EVERY WILD POKEMON HERE."] = "Tutti i Pokémon selvatici qui.",
        ["ODDS, LEVELS AND DEX INFO."] = "Probabilità, livelli e dati del Pokédex.",
        ["POWERED BY WOOBLESPAWNS."] = "Un'app di WoobleSpawns.",
      },
      ja = {
        ["WOOBNAV"] = "WOOBNAV",
        ["TOOLS"] = "ツール",
        ["EVERY WILD POKEMON HERE."] = "ここに いる やせいの ポケモン。",
        ["ODDS, LEVELS AND DEX INFO."] = "でる かくりつ・レベル・ずかん。",
        ["POWERED BY WOOBLESPAWNS."] = "WoobleSpawns提供のアプリ。",
      },
    },
  }
end
