-- Test stub for national_dex on a Gen 2 boot with NATIONAL DEX ON: a few
-- species past #251 registered in Gold's record shape (split special,
-- levelMoves, `into` evolutions, picSize), the way src/gen2shape.lua does.
-- Art paths borrow a cart sprite's; nothing here is ever drawn.
return function(mod)
  local art = mod.content.pokemon:get("PIDGEY")
  local function species(id, dex, types, hp, atk, def, spe, spa, spd, evolutions)
    return {
      id = id, name = id, dex = dex, types = types,
      baseStats = { hp = hp, attack = atk, defense = def, speed = spe,
                    specialAttack = spa, specialDefense = spd },
      catchRate = 190, baseExp = 50, growthRate = "GROWTH_MEDIUM_FAST",
      levelMoves = { { level = 1, move = "TACKLE" } },
      evolutions = evolutions or {},
      spriteFront = art.spriteFront, spriteBack = art.spriteBack, picSize = 5,
    }
  end
  local roster = {
    species("STARLY", 396, { "NORMAL", "FLYING" }, 40, 55, 30, 60, 30, 30,
            { { method = "EVOLVE_LEVEL", level = 14, into = "STARAVIA" } }),
    species("STARAVIA", 397, { "NORMAL", "FLYING" }, 55, 75, 50, 80, 40, 40),
    species("SHINX", 403, { "ELECTRIC" }, 45, 65, 34, 45, 40, 34),
    species("ROGGENROLA", 524, { "ROCK" }, 55, 75, 85, 15, 25, 25),
    species("LECHONK", 915, { "NORMAL" }, 54, 45, 40, 35, 35, 45),
    species("WIGLETT", 960, { "WATER" }, 10, 55, 25, 95, 35, 25),
    species("FINNEON", 456, { "WATER" }, 49, 49, 56, 66, 49, 61),
  }
  for _, record in ipairs(roster) do
    mod.content.pokemon:register(record.id, record)
  end
  mod.exports.apiVersion = 9
  mod.exports.evolutionsOf = function() return nil end
end
