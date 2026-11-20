-- WoobNav: a species' summary page, from the game's own Pokedex data (the same sources WoobOS's
-- Pokedex reads): number, name, types, category, height and weight, the Pokedex's words, base
-- stats, abilities (Gen 3), its evolution line, and whether it is seen / caught. Read only;
-- every field may be missing (a species a mod registered without one).
--
--   Info = makeInfo({ mod, profileOf = fn(id) -> exports.profileOf(id) | nil })
--   Info.page(id) -> { id, name, dex, types = { names }, category, height, weight, text,
--                      stats = { { label, value } }, total, abilities = { names },
--                      line = { { id, name, how } }, seen, caught }

return function(deps)
  local mod, profileOf = deps.mod, deps.profileOf
  local floor = math.floor
  local generation = tonumber(mod.generation) or 1

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end
  local function data() return mod.game and mod.game.data end
  local function record(id)
    local ok, rec = pcall(function() return mod.content.pokemon:get(id) end)
    return ok and type(rec) == "table" and rec or nil
  end

  local KEEP = { HP = true, PP = true, TM = true, HM = true }
  local function unshout(text)
    return (text:gsub("[%a\195\169]+", function(w)
      if #w < 2 or w:find("%l") or KEEP[w] then return w end
      return w:sub(1, 1) .. w:sub(2):lower()
    end))
  end
  local function paragraph(text)
    if type(text) ~= "string" then return "" end
    -- a word the game broke across two lines ("pro-\ntects") is one word again
    text = text:gsub("(%a)%-%s*<NEXT>%s*(%l)", "%1%2"):gsub("(%a)%-[\r\n\f]+%s*(%l)", "%1%2")
    text = text:gsub("<NEXT>", " "):gsub("<LF>", " "):gsub("{[^}]*}", ""):gsub("[\r\n\f\v]+", " "):gsub("%s+", " ")
    return unshout((text:gsub("^%s+", ""):gsub("%s+$", "")))
  end
  local function titled(s)
    s = tostring(s or ""):gsub("_", " ")
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end

  -- inches -> "0.7 m", tenths of a pound -> "6.9 kg"
  local function heightOfInches(inches)
    inches = tonumber(inches) or 0
    return ("%.1f m  %d'%02d\""):format(inches * 0.0254, floor(inches / 12), inches % 12)
  end
  local function weightOfTenths(tenths)
    tenths = tonumber(tenths) or 0
    return ("%.1f kg  %.1f lbs"):format(tenths * 0.045359, tenths / 10)
  end
  local function heightOfDm(dm)
    dm = tonumber(dm) or 0
    local inches = floor(dm * 3.937 + 0.5)
    return ("%.1f m  %d'%02d\""):format(dm / 10, floor(inches / 12), inches % 12)
  end
  local function weightOfHg(hg)
    hg = tonumber(hg) or 0
    return ("%.1f kg  %.1f lbs"):format(hg / 10, hg * 0.220462)
  end

  local function typeName(t)
    if type(t) == "number" then
      local Types = engine("src.core.game3.battle.types")
      local ok, name = pcall(Types and Types.name or error, t)
      t = ok and name or tostring(t)
    end
    t = tostring(t):gsub("^TYPE_", ""):gsub("_TYPE$", ""):upper()
    return t
  end

  local function gen3Family()
    local Version = engine("src.core.GameVersion")
    local ok, ed = pcall(Version and Version.get or error)
    ed = ok and ed or ""
    return (ed == "ruby" or ed == "sapphire" or ed == "emerald") and "rse" or "frlg"
  end

  local entriesPack
  local function gen3Text(index)
    if gen3Family() == "rse" then
      if entriesPack == nil then
        local Mapsec = engine("src.ui.game3.rse.mapsec")
        local ok, pack = pcall(Mapsec and Mapsec.readLua or error, "pokemon/pokedex/entries.lua")
        entriesPack = ok and type(pack) == "table" and pack or false
      end
      local e = entriesPack and entriesPack[index]
      if not e then return "" end
      local one, two = paragraph(e.description), paragraph(e.description2)
      if two ~= "" and two ~= one then return one .. " " .. two end
      return one
    end
    local PD = engine("src.core.game3.pokedex_data")
    local ok, e = pcall(PD and PD.getEntry or error, index)
    return ok and type(e) == "table" and paragraph(e.description) or ""
  end

  -- seen / caught on the running save
  local function dexState(id, rec)
    local seen, caught = false, false
    pcall(function()
      if generation == 3 then
        local dex = mod.game and mod.game.session and mod.game.session.dex
        local slot = rec and tonumber(rec.index)
        if dex and slot then
          caught = dex.owned ~= nil and dex.owned[slot] == true
          seen = caught or (dex.seen ~= nil and dex.seen[slot] == true)
        end
      else
        local p = mod.game and mod.game.save and mod.game.save.pokedex
        if p then
          caught = (p.owned ~= nil and p.owned[id] == true) or (p.caught ~= nil and p.caught[id] == true)
          seen = caught or (p.seen ~= nil and p.seen[id] == true)
        end
      end
    end)
    return seen, caught
  end

  -- how `parent` becomes `child`, from the Game Boy games' own evolution records ("Lv 16",
  -- "Moon Stone", "Trade", "Friendship"); nil when unknown (Gen 3: the line's levels instead)
  local function howEvolves(parent, child)
    if generation == 3 then return nil end
    local d = data()
    local def = d and d.pokemon and d.pokemon[parent]
    for _, e in ipairs(type(def) == "table" and def.evolutions or {}) do
      local into = e.species or e.into
      if into == child then
        local m = tostring(e.method or ""):gsub("^EVOLVE_", "")
        if m == "LEVEL" or m == "STAT" then return e.level and ("Lv " .. e.level) or nil end
        if m == "ITEM" then return e.item and titled(e.item) or "Item" end
        if m == "TRADE" then return "Trade" end
        if m == "HAPPINESS" then return "Friendship" end
        return e.level and ("Lv " .. e.level) or titled(m)
      end
    end
    return nil
  end

  -- the evolution line, first stage first: { { id, name, how } } ("Lv 16", "Moon Stone", ...)
  local function line(id)
    local out = {}
    if not profileOf then return out end
    local p = profileOf(id)
    if not p then return out end
    local root, guard = id, 0
    while guard < 8 do
      local pr = profileOf(root)
      if not (pr and pr.evolvesFrom) then break end
      root = pr.evolvesFrom
      guard = guard + 1
    end
    -- children by family: every species of the family, ordered by stage
    local fam = {}
    local okC, list = pcall(function()
      local ms = mod.exports
      return ms and ms.candidates and ms.candidates({ includeSpecial = true }) or {}
    end)
    for _, c in ipairs(okC and list or {}) do
      if c.family == p.family and not c.form then fam[#fam + 1] = c end
    end
    table.sort(fam, function(a, b)
      if (a.stage or 1) ~= (b.stage or 1) then return (a.stage or 1) < (b.stage or 1) end
      return (a.dex or 0) < (b.dex or 0)
    end)
    for _, c in ipairs(fam) do
      local rec = record(c.id)
      local how
      if c.evolvesFrom then
        how = howEvolves(c.evolvesFrom, c.id)
        local lvl = tonumber(c.evolveLevel)
        if not how and lvl and lvl > 0 then how = "Lv " .. lvl end
      end
      out[#out + 1] = { id = c.id, name = rec and rec.name or c.id, how = how, stage = c.stage }
    end
    if #out == 0 then out[1] = { id = id, name = (record(id) or {}).name or id } end
    return out
  end

  local pages = {}
  local Info = {}

  function Info.reset() pages = {} end

  function Info.page(id)
    local pg = pages[id]
    if pg then
      pg.seen, pg.caught = dexState(id, record(id))
      return pg
    end
    local rec = record(id) or {}
    pg = { id = id, name = rec.name or tostring(id), dex = tonumber(rec.dex), types = {}, stats = {},
           abilities = {} }
    for _, t in ipairs(type(rec.types) == "table" and rec.types or {}) do
      local name = typeName(t)
      if pg.types[1] ~= name then pg.types[#pg.types + 1] = name end
    end
    pcall(function()
      if generation == 3 then
        local Pk = engine("src.core.game3.pokemon")
        local index = tonumber(rec.index)
        if not (Pk and index) then return end
        local okD, de = pcall(Pk.dexEntry, index)
        de = okD and type(de) == "table" and de or {}
        pg.category = de.category and titled(de.category) or nil
        pg.height = de.height and heightOfDm(de.height) or nil
        pg.weight = de.weight and weightOfHg(de.weight) or nil
        pg.text = gen3Text(index)
        if #pg.types == 0 and Pk._types and Pk._types[index] then
          local t = Pk._types[index]
          pg.types[1] = typeName(t[1] or 0)
          if t[2] and t[2] ~= t[1] then pg.types[2] = typeName(t[2]) end
        end
        local okS, st = pcall(Pk.stats, index)
        st = okS and type(st) == "table" and st or {}
        pg.stats = { { "HP", st.hp }, { "ATK", st.atk }, { "DEF", st.def }, { "SP.ATK", st.spa },
                     { "SP.DEF", st.spd }, { "SPEED", st.spe } }
        local ab = Pk._abilities and Pk._abilities[index]
        local seen = {}
        for _, a in ipairs(type(ab) == "table" and ab or {}) do
          a = tonumber(a)
          if a and a > 0 and not seen[a] then
            seen[a] = true
            local okA, name = pcall(Pk.abilityName, a)
            if okA and name then pg.abilities[#pg.abilities + 1] = titled(name) end
          end
        end
      else
        local d = data()
        local def = d and d.pokemon and d.pokemon[id] or {}
        local b = def.baseStats or {}
        if generation == 2 then
          local de = d and d.gen2Pokedex and d.gen2Pokedex.entries and d.gen2Pokedex.entries[id] or {}
          pg.category = de.kind and titled(de.kind) or nil
          local h = tonumber(de.height)
          pg.height = h and heightOfInches(floor(h / 100) * 12 + h % 100) or nil
          pg.weight = de.weight and weightOfTenths(de.weight) or nil
          local one, two = paragraph(de.text), paragraph(de.text2)
          pg.text = two ~= "" and (one .. " " .. two) or one
          pg.stats = { { "HP", b.hp }, { "ATK", b.attack }, { "DEF", b.defense },
                       { "SP.ATK", b.specialAttack or b.special }, { "SP.DEF", b.specialDefense or b.special },
                       { "SPEED", b.speed } }
        else
          local de = def.dexEntry or {}
          pg.category = de.kind and titled(de.kind) or nil
          if de.heightFt or de.heightIn then
            pg.height = heightOfInches((tonumber(de.heightFt) or 0) * 12 + (tonumber(de.heightIn) or 0))
          end
          pg.weight = de.weight and weightOfTenths(de.weight) or nil
          pg.text = paragraph(de.text and d and d.text and d.text[de.text] or "")
          pg.stats = { { "HP", b.hp }, { "ATK", b.attack }, { "DEF", b.defense }, { "SPCL", b.special },
                       { "SPEED", b.speed } }
        end
      end
    end)
    pg.total = 0
    for _, s in ipairs(pg.stats) do
      s[2] = tonumber(s[2]) or 0
      pg.total = pg.total + s[2]
    end
    pg.line = line(id)
    pg.seen, pg.caught = dexState(id, rec)
    pages[id] = pg
    return pg
  end

  -- the name a list shows
  function Info.name(id)
    local rec = record(id)
    return rec and rec.name or tostring(id)
  end

  function Info.caught(id)
    local _, caught = dexState(id, record(id))
    return caught
  end

  return Info
end
