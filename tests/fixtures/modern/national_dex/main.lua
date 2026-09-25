-- Test stub for national_dex with its NATIONAL DEX option ON: registers a
-- few species past #151 the way the real mod does (mod.content.pokemon
-- register, evolutions left empty) and publishes evolutionsOf. Art paths
-- borrow a cart sprite's; nothing here is ever drawn.
return function(mod)
  local art = mod.content.pokemon:get("PIDGEY")
  local function species(id, dex, types, hp, atk, def, spe, spc)
    return {
      id = id, name = id, dex = dex, types = types,
      baseStats = { hp = hp, attack = atk, defense = def, speed = spe, special = spc },
      catchRate = 190, baseExp = 50, growthRate = "MEDIUM_FAST",
      level1Moves = { "TACKLE" }, learnset = {}, evolutions = {},
      spriteFront = art.spriteFront, spriteBack = art.spriteBack, frontSize = 5,
    }
  end
  local roster = {
    species("SENTRET", 161, { "NORMAL" }, 35, 46, 34, 20, 40),
    species("FURRET", 162, { "NORMAL" }, 85, 76, 64, 90, 50),
    species("HOOTHOOT", 163, { "NORMAL", "FLYING" }, 60, 30, 30, 50, 46),
    species("MAREEP", 179, { "ELECTRIC" }, 55, 40, 40, 35, 55),
    species("MARILL", 183, { "WATER" }, 70, 20, 50, 40, 20),
    species("RAIKOU", 243, { "ELECTRIC" }, 90, 85, 75, 115, 115),
    species("STARLY", 396, { "NORMAL", "FLYING" }, 40, 55, 30, 60, 30),
    species("SHINX", 403, { "ELECTRIC" }, 45, 65, 34, 45, 30),
    species("LECHONK", 915, { "NORMAL" }, 54, 45, 40, 35, 35),
    species("WIGLETT", 960, { "WATER" }, 10, 55, 25, 95, 35),
  }
  for _, record in ipairs(roster) do
    mod.content.pokemon:register(record.id, record)
  end
  mod.content.constants:patch("dexSize", 960)

  mod.exports.apiVersion = 9
  mod.exports.evolutionsOf = function(id)
    if id == "SENTRET" then
      return { chainId = 70, evolvesInto = { { id = "FURRET" } } }
    end
    if id == "FURRET" then
      return { chainId = 70, evolvesFrom = { id = "SENTRET",
               methods = { { level = 15, trigger = "level-up" } } } }
    end
    return nil
  end
end
