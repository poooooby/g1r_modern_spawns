-- Test stub for national_dex with its NATIONAL DEX option OFF (the real
-- mod's default): installed and loaded, but no species past #151 exist.
return function(mod)
  mod.exports.apiVersion = 9
  mod.exports.evolutionsOf = function() return nil end
end
