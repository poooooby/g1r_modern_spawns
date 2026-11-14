-- A stand-in for a species randomizer layered on top of WoobleSpawns
-- (tests/compose_test.lua): wraps encounter.species and encounter.fishing
-- outside it, records what it was handed, and swaps the species for
-- `exports.target` (a numeric Gen 3 slot), keeping every other field.
return function(mod)
  local seen = { species = {}, fishing = {} }
  mod.exports.seen = seen
  mod.exports.target = nil

  local function swap(result)
    if type(result) ~= "table" or not mod.exports.target then return result end
    local out = {}
    for k, v in pairs(result) do out[k] = v end
    out.species = mod.exports.target
    if out.speciesId ~= nil then out.speciesId = mod.exports.target end
    return out
  end

  mod.hooks:wrap("encounter.species", function(nextFn, encounter, ctx)
    local result = nextFn(encounter, ctx)
    seen.species[#seen.species + 1] = result
    return swap(result)
  end, 100)

  mod.hooks:wrap("encounter.fishing", function(nextFn, rod, mapId, candidates, ...)
    local result = nextFn(rod, mapId, candidates, ...)
    seen.fishing[#seen.fishing + 1] = result
    return swap(result)
  end, 100)
end
