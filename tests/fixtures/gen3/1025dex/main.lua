-- Test stub for 1025Dex's WILD GENS: like the real mod, it patches
-- src.core.game3.battle_bridge's Bridge.start and replaces every wild foe
-- unless the battle's opts carry __completeDexExact. The replacement is a
-- recognisable marker (species 999).
return function(mod)
  local Bridge = require("src.core.game3.battle_bridge")
  local original = Bridge.start
  Bridge.start = function(owner, game, foe, opts)
    if opts and opts.wild and not opts.__completeDexExact then
      foe = { species = 999, speciesId = 999, level = foe and foe.level }
    end
    return original(owner, game, foe, opts)
  end
  mod.exports.apiVersion = 9
end
