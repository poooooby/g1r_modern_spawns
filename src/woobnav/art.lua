-- WoobNav: drawing in Kanto Gear's pixel style, its fonts, and the Pokemon's pictures.
--
-- The palette, the rounded-rectangle rows and the pixel-art rows follow Kanto Gear's Pokegear
-- skin (ui/skins/init.lua, chrome.lua; MIT, (c) 2026 AverageConsumer), so the WoobNav reads as
-- one of its apps. The fonts are Kanto Gear's HGSS pixel atlases (assets/fonts: BobsGame nD,
-- WTFPL; scientifica, OFL 1.1; HGSS_PIXEL_FONT_LICENSE.txt). Gen 1/2 pictures are coloured on
-- the CPU as NaviPlay's src/refresh/host_gb.lua does (MIT, (c) 2026 poooooby).
--
-- Every love call is guarded: headless (tests) the fonts are nil and text measures by length.

return function(mod)
  local A = {}
  local floor, max, min = math.floor, math.max, math.min
  local G = love and love.graphics

  local function engine(name)
    local ok, m = pcall(require, name)
    return ok and type(m) == "table" and m or nil
  end

  -- ------- colours

  local hexCache = {}
  local function hex(value, alpha)
    local key = value .. ":" .. tostring(alpha or 1)
    local c = hexCache[key]
    if c then return c end
    local v = value:gsub("#", "")
    c = { tonumber(v:sub(1, 2), 16) / 255, tonumber(v:sub(3, 4), 16) / 255, tonumber(v:sub(5, 6), 16) / 255,
          alpha or 1 }
    hexCache[key] = c
    return c
  end
  local function mix(a, b, k)
    return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, a[4] or 1 }
  end
  local function rampOf(c)
    return { M = c, L = mix(c, { 1, 1, 1, 1 }, 0.30), D = mix(c, { 0, 0, 0, 1 }, 0.42),
             Hi = mix(c, { 1, 1, 1, 1 }, 0.62) }
  end
  A.hex, A.mix, A.rampOf = hex, mix, rampOf

  -- the Pokegear skin, light
  A.C = {
    bgA = hex("c3e6cf"), bgB = hex("b5dec5"), emboss = hex("a6d3b8"),
    paper = hex("f8f8f0"), paper2 = hex("e8efe6"), line = hex("cfdcd2"),
    ink = hex("383c44"), muted = hex("5f7468"), disabled = hex("8c9a92"), outline = hex("283036"),
    surface = hex("f8f8f0"), white = hex("f8f8f8"), silver = hex("cdd6d0"), silverDark = hex("6a7a72"),
    red = hex("c8382c"), amber = hex("c07a10"), amberLight = hex("f8c048"), blue = hex("2f6cc0"),
    hp = hex("40d058"), hpMid = hex("f8c030"), hpLow = hex("f04838"), focus = hex("fff0cc"),
    shadow = { 0.09, 0.19, 0.16, 0.24 }, well = hex("14483c"),
    acc = { M = hex("2f8c76"), L = hex("4fae95"), D = hex("1b5a4c"), Hi = hex("9fe0cc") },
    accS = hex("3a9a82"),
  }
  A.WHITE = { 1, 1, 1, 1 }

  -- each type's colour (the games' own hues)
  A.TYPE = {
    NORMAL = hex("a8a878"), FIRE = hex("f08030"), WATER = hex("6890f0"), GRASS = hex("78c850"),
    ELECTRIC = hex("e8b820"), ICE = hex("80c8c8"), FIGHTING = hex("c03028"), POISON = hex("a040a0"),
    GROUND = hex("d0b060"), FLYING = hex("a890f0"), PSYCHIC = hex("f85888"), BUG = hex("a8b820"),
    ROCK = hex("b8a038"), GHOST = hex("705898"), DRAGON = hex("7038f8"), DARK = hex("705848"),
    STEEL = hex("a8a8c0"), FAIRY = hex("ee99ac"), BIRD = hex("a890f0"), MYSTERY = hex("68a090"),
  }

  -- ------- primitives (Kanto Gear's)

  local function setc(c) G.setColor(c[1], c[2], c[3], c[4] or 1) end
  A.setc = setc

  function A.R(x, y, w, h, c)
    if w <= 0 or h <= 0 then return end
    setc(c)
    G.rectangle("fill", x, y, w, h)
  end
  local R = A.R

  local RAD = {
    [0] = {}, [1] = { 1 }, [2] = { 2, 1 }, [3] = { 3, 1, 1 }, [4] = { 4, 2, 1, 1 },
    [5] = { 5, 3, 2, 1, 1 }, [6] = { 6, 4, 3, 2, 1, 1 },
  }
  local function inset(r, h, i)
    local t = RAD[r] or RAD[6]
    if i < #t then return t[i + 1] end
    if h - 1 - i < #t then return t[h - i] end
    return 0
  end
  -- a rounded rectangle, row by row (only rows from..to-1 when given)
  function A.RR(x, y, w, h, r, c, from, to)
    if w <= 0 or h <= 0 then return end
    r = min(r, floor(min(w, h) / 2))
    setc(c)
    local n = #(RAD[r] or RAD[6])
    local i, stop = max(0, from or 0), min(h, to or h)
    while i < stop do
      local k = inset(r, h, i)
      if i >= n and i < h - n then
        local e = min(stop, h - n)
        G.rectangle("fill", x, y + i, w, e - i)
        i = e
      else
        if w - 2 * k > 0 then G.rectangle("fill", x + k, y + i, w - 2 * k, 1) end
        i = i + 1
      end
    end
  end
  local RR = A.RR

  -- pixel-art rows: each char a colour from pal ("." clear)
  function A.ART(rows, x, y, pal)
    for j, row in ipairs(rows) do
      local i = 1
      while i <= #row do
        local ch = row:sub(i, i)
        local c = pal[ch]
        if c then
          local e = i
          while e < #row and row:sub(e + 1, e + 1) == ch do e = e + 1 end
          R(x + i - 1, y + j - 1, e - i + 1, 1, c)
          i = e + 1
        else
          i = i + 1
        end
      end
    end
  end
  local ART = A.ART

  -- a window: outline, then the surface (Kanto Gear's v4Window)
  function A.window(x, y, w, h, fill, edge, shadow)
    local r = h < 16 and 2 or (h < 30 and 3 or 4)
    if shadow ~= false then RR(x + 2, y + 2, w, h, r, A.C.shadow) end
    RR(x, y, w, h, r, edge or A.C.outline)
    RR(x + 1, y + 1, w - 2, h - 2, max(0, r - 1), fill or A.C.surface)
    return r
  end

  -- a lipped button (Kanto Gear's v4Button), ramp { M, L, D, Hi }
  function A.button(x, y, w, h, a, pressed, radius)
    local off = pressed and 2 or 0
    local r = radius or 4
    if not pressed then RR(x + 1, y + 2, w, h, r, A.C.shadow) end
    RR(x, y + off, w, h - off, r, A.C.outline)
    RR(x + 1, y + 1 + off, w - 2, h - 2 - off, r - 1, a.D)
    local hh = h - 2 - 3 + (pressed and 2 or 0) - off
    RR(x + 1, y + 1 + off, w - 2, hh, r - 1, a.M)
    RR(x + 1, y + 1 + off, w - 2, hh, r - 1, a.L, 0, floor(hh * 0.45))
    R(x + r, y + 2 + off, w - 2 * r, 1, a.Hi)
    return off
  end

  -- ------- backdrop and header plate (Kanto Gear's Pokegear chrome)

  local stripe
  function A.backdrop(top)
    top = top or 0
    if stripe == nil then
      stripe = false
      pcall(function()
        local data = love.image.newImageData(8, 8)
        for y = 0, 7 do for x = 0, 7 do
          local c = ((x + y) % 8) < 4 and A.C.bgB or A.C.bgA
          data:setPixel(x, y, c[1], c[2], c[3], 1)
        end end
        local image = G.newImage(data)
        image:setFilter("nearest", "nearest")
        image:setWrap("repeat", "repeat")
        stripe = { image = image, quad = G.newQuad(0, 0, 240, 216, 8, 8) }
      end)
    end
    if stripe then
      stripe.quad:setViewport(0, top, 240, 216 - top, 8, 8)
      G.setColor(1, 1, 1, 1)
      G.draw(stripe.image, stripe.quad, 0, top)
    else
      R(0, top, 240, 216 - top, A.C.bgA)
    end
  end

  local BACK = { "...#", "..##", ".###", "####", ".###", "..##", "...#" }
  A.CHEV_L = { "..#", ".##", "###", ".##", "..#" }
  A.CHEV_R = { "#..", "##.", "###", "##.", "#.." }

  -- the header plate in the page's tint, the back button at (3,3) 20x16 when `back`, the title
  -- in the well; `pressed`: the back button held. Returns the well's right edge.
  function A.header(title, tint, back, pressed, right)
    local acc = tint and rampOf(tint) or A.C.acc
    local accS = tint and mix(acc.M, acc.L, 0.35) or A.C.accS
    local well = tint and mix(acc.D, { 0, 0, 0, 1 }, 0.45) or A.C.well
    local C = A.C
    R(0, 0, 240, 23, acc.D)
    for y = 1, 20 do R(0, y, 240, 1, y % 2 == 1 and acc.M or accS) end
    R(0, 0, 240, 1, acc.Hi)
    R(0, 21, 240, 1, acc.D); R(0, 22, 240, 1, C.outline)
    for x = 0, 239, 6 do
      R(x + 1, 23, 4, 1, C.outline); R(x + 2, 24, 2, 1, C.outline)
      R(x + 1, 24, 1, 1, C.shadow); R(x + 4, 24, 1, 1, C.shadow)
      R(x + 2, 25, 2, 1, C.shadow)
    end
    local left = 4
    if back then
      local o = pressed and 1 or 0
      RR(3, 3, 20, 16, 4, C.outline)
      RR(4, 4 + o, 18, 14 - o, 3, pressed and acc.M or acc.L)
      if not pressed then RR(4, 4, 18, 14, 3, acc.Hi, 0, 7) end
      R(4, 15, 18, 2, acc.D)
      ART(BACK, 10, 7 + o, { ["#"] = acc.D })
      ART(BACK, 9, 6 + o, { ["#"] = A.WHITE })
      left = 26
    end
    local wellW = (right or 236) - left
    RR(left, 3, wellW, 17, 3, acc.D)
    RR(left + 1, 4, wellW - 2, 15, 2, well)
    R(left + 3, 18, wellW - 6, 1, acc.M)
    local shown = A.fit("label", title, wellW - 10)
    local w = A.width("label", shown)
    A.text("label", shown, left + floor((wellW - w) / 2), 3, A.WHITE)
    return left + wellW
  end

  -- ------- fonts

  A.fonts = {}
  local LINE = { label = 14, small = 11, large = 28 }
  local function loadFonts()
    if not (G and G.newImageFont and love.image and love.filesystem and mod.read) then return end
    local okG, glyphs = pcall(function() return load(mod:read("assets/fonts/glyphs.lua"))() end)
    if not okG or type(glyphs) ~= "string" then return end
    local function face(file)
      local ok, font = pcall(function()
        local bytes = mod:read(file)
        local data = love.image.newImageData(love.filesystem.newFileData(bytes, file:match("[^/]+$")))
        local f = G.newImageFont(data, glyphs)
        f:setFilter("nearest", "nearest")
        return f
      end)
      return ok and font or nil
    end
    A.fonts.label = face("assets/fonts/hgss_font.png")
    A.fonts.small = face("assets/fonts/hgss_small_font.png")
    A.fonts.large = face("assets/fonts/hgss_large_font.png")
  end
  local fontsLoaded = false
  local function font(name)
    if not fontsLoaded then
      fontsLoaded = true
      pcall(loadFonts)
    end
    return A.fonts[name]
  end

  function A.lineHeight(name) return LINE[name] or 11 end

  function A.width(name, s)
    s = tostring(s or "")
    local f = font(name)
    if f then return f:getWidth(s) end
    return #s * (name == "large" and 12 or name == "label" and 6 or 5)
  end

  function A.text(name, s, x, y, c, width, align)
    local f = font(name)
    if not (G and f) then return end
    s = tostring(s or "")
    setc(c or A.C.ink)
    local prev = G.getFont()
    G.setFont(f)
    if width then G.printf(s, floor(x), floor(y), width, align or "left")
    else G.print(s, floor(x), floor(y)) end
    if prev then G.setFont(prev) end
  end

  -- the string cut to fit `maxW`, an ellipsis on what was cut
  function A.fit(name, s, maxW)
    s = tostring(s or "")
    if A.width(name, s) <= maxW then return s end
    local chars = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    while #chars > 0 and A.width(name, table.concat(chars) .. "…") > maxW do table.remove(chars) end
    return table.concat(chars) .. "…"
  end

  -- words wrapped to `maxW` -> lines
  function A.wrap(name, s, maxW)
    local lines, line = {}, ""
    for word in tostring(s or ""):gmatch("%S+") do
      local try = line == "" and word or (line .. " " .. word)
      if A.width(name, try) <= maxW or line == "" then
        line = try
      else
        lines[#lines + 1] = line
        line = word
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
  end

  -- ------- small icons (original pixel art)

  -- how each method is met: a grass tuft, a wave, a rod, a rock, a cave mouth
  local ICONS = {
    grass = { "..g...g.", ".gG..gG.", ".gG.gGg.", "gGgGgGGg", "gGGgGGgG", "GGGGGGGG" },
    cave = { "..oooo..", ".oddddo.", "oddkkddo", "odkkkkdo", "odkkkkdo", "oooooooo" },
    surf = { "........", "..bbb...", ".bBBBb..", "bB..BBb.", "......Bb", "bBBbbBBb" },
    rod = { "......o.", ".....o.l", "....o..l", "...o...l", "..o...lw", ".o....l." },
    rock = { "..oooo..", ".orrrro.", "orRrrrRo", "orrRRrro", "orrrrrro", ".oooooo." },
  }
  local ICON_PAL = {
    g = hex("4fae95"), G = hex("2f8c76"), o = hex("283036"), d = hex("8a7a68"), k = hex("383c44"),
    b = hex("68b8d8"), B = hex("245a80"), l = hex("8c9a92"), w = hex("f8f8f8"),
    r = hex("b8a890"), R = hex("8a7a68"),
  }
  local METHOD_ICON = { grass = "grass", cave = "cave", surf = "surf", old = "rod", good = "rod", super = "rod",
                        rock = "rock" }
  function A.methodIcon(method, x, y)
    local rows = ICONS[METHOD_ICON[method] or "grass"]
    ART(rows, x, y, ICON_PAL)
  end

  -- a Poke Ball, 7x7 (caught)
  local BALL = { "..ooo..", ".orrro.", "orrrrro", "ooowooo", "owwwwwo", ".owwwo.", "..ooo.." }
  local BALL_PAL = { o = hex("283036"), r = hex("e04838"), w = hex("f8f8f8") }
  function A.ball(x, y) ART(BALL, x, y, BALL_PAL) end

  -- the time of day: sun (DAY), half sun (MORN), moon (NITE / night)
  local SUN = { ".a.a.a.", "..aaa..", "aaAAAaa", "..aaa..", ".a.a.a." }
  local MORN = { ".......", "..aaa..", "aaAAAaa", "ooooooo", "......." }
  local MOON = { "..mmm..", ".mm....", "mm.....", ".mm....", "..mmm.." }
  local TIME_PAL = { a = hex("c07a10"), A = hex("f8c048"), o = hex("8c9a92"), m = hex("5a6c88") }
  function A.timeIcon(time, x, y)
    local rows = (time == "NITE" or time == "night") and MOON or time == "MORN" and MORN or SUN
    ART(rows, x, y, TIME_PAL)
  end

  -- ------- Pokemon pictures

  local generation = tonumber(mod.generation) or 1
  local pics = {}   -- id -> { image, x0, y0, w, h } (the opaque part) | false

  local function data()
    return mod.game and mod.game.data
  end

  -- the species' four colours, 0..1, light to dark
  local function colorsOf(species)
    local c
    local d = data()
    if generation == 1 then
      local PaletteFX = engine("src.render.PaletteFX")
      if PaletteFX and PaletteFX.monPal then
        local ok, v = pcall(PaletteFX.monPal, d, species)
        c = ok and v or nil
      end
    else
      local Palettes = engine("src.world.gen2.Palettes")
      if Palettes and Palettes.monColors then
        local ok, v = pcall(Palettes.monColors, d and d.gen2Palettes, species, false)
        c = ok and v or nil
      end
    end
    if type(c) ~= "table" or #c < 4 then
      c = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 } }
    end
    local out = {}
    for i = 1, 4 do
      local e = c[i] or { 0, 0, 0 }
      local k = ((e[1] or 0) > 1 or (e[2] or 0) > 1 or (e[3] or 0) > 1) and 255 or 1
      out[i] = { (e[1] or 0) / k, (e[2] or 0) / k, (e[3] or 0) / k }
    end
    return out
  end

  -- a four-shade Game Boy picture coloured, the white reachable from its edge made clear
  local function colour(src, colors)
    local w, h = src:getDimensions()
    local out = love.image.newImageData(w, h)
    local shade = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, _, _, a = src:getPixel(x, y)
        local s
        if a < 0.5 or r > 0.83 then s = 0 elseif r > 0.5 then s = 1 elseif r > 0.17 then s = 2 else s = 3 end
        shade[y * w + x] = s
      end
    end
    local clear, stack = {}, {}
    local function push(x, y)
      local i = y * w + x
      if not clear[i] and shade[i] <= 0 then clear[i] = true; stack[#stack + 1] = i end
    end
    for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
    for y = 0, h - 1 do push(0, y); push(w - 1, y) end
    while #stack > 0 do
      local i = table.remove(stack)
      local x, y = i % w, floor(i / w)
      if x > 0 then push(x - 1, y) end
      if x < w - 1 then push(x + 1, y) end
      if y > 0 then push(x, y - 1) end
      if y < h - 1 then push(x, y + 1) end
    end
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local i = y * w + x
        if clear[i] then out:setPixel(x, y, 0, 0, 0, 0)
        else
          local c = colors[shade[i] + 1]
          out:setPixel(x, y, c[1], c[2], c[3], 1)
        end
      end
    end
    return out
  end

  -- the opaque bounds of an ImageData -> x0, y0, w, h
  local function bounds(d)
    local w, h = d:getDimensions()
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = d:getPixel(x, y)
        if a > 0.05 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    if x1 < 0 then return 0, 0, w, h end
    return x0, y0, x1 - x0 + 1, y1 - y0 + 1
  end

  local function gbPic(id)
    local Sprites, Assets = engine("src.pokemon.Sprites"), engine("src.render.Assets")
    local path, trueColor
    if Sprites and Sprites.path then
      local ok, p, t = pcall(Sprites.path, data(), id, "front", { kind = "summary" })
      if ok then path, trueColor = p, t end
    end
    if not path then
      local d = data()
      local def = d and d.pokemon and d.pokemon[id]
      path = def and def.spriteFront
    end
    if not (path and Assets and Assets.imageData) then return nil end
    local okD, src = pcall(Assets.imageData, path)
    if not (okD and src) then return nil end
    local coloured = trueColor and src or colour(src, colorsOf(id))
    local x0, y0, w, h = bounds(coloured)
    local image = G.newImage(coloured)
    image:setFilter("nearest", "nearest")
    return { image = image, x0 = x0, y0 = y0, w = w, h = h }
  end

  local function gen3Pic(id)
    local P = engine("src.core.game3.pokemon")
    local rec = mod.content and mod.content.pokemon and mod.content.pokemon:get(id)
    local index = type(rec) == "table" and tonumber(rec.index)
    if not (P and P.frontPic and index) then return nil end
    local ok, pic = pcall(P.frontPic, index, nil, false, nil, "summary")
    local image = ok and type(pic) == "table" and pic.image or nil
    if not image then return nil end
    -- the opaque part, read back once from a canvas (a pic is an Image, not pixels)
    local iw, ih = image:getDimensions()
    local x0, y0, w, h = 0, 0, iw, ih
    pcall(function()
      local c = G.newCanvas(iw, ih, { dpiscale = 1 })
      G.push("all")
      G.setCanvas(c)
      G.origin()
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      G.draw(image, 0, 0)
      G.pop()
      local d = c:newImageData()
      x0, y0, w, h = bounds(d)
      if d.release then d:release() end
      if c.release then c:release() end
    end)
    return { image = image, x0 = x0, y0 = y0, w = w, h = h }
  end

  -- build pictures ahead of drawing (never inside the view's own canvas)
  function A.prepare(ids)
    if not (G and love.image) then return end
    for _, id in ipairs(ids or {}) do
      if pics[id] == nil then
        local ok, pic = pcall(generation == 3 and gen3Pic or gbPic, id)
        pics[id] = ok and pic or false
      end
    end
  end

  function A.dropPictures() pics = {} end

  -- the picture fitted into a box (cx: its centre; bottom: its foot), the largest of 1, 3/4, 1/2
  -- (or smaller still for big art) that fits
  function A.pokemon(id, cx, bottom, boxW, boxH)
    local pic = pics[id]
    if not (G and pic) then return false end
    local s = 1
    for _, k in ipairs({ 1, 0.75, 0.5 }) do
      s = k
      if pic.w * k <= boxW and pic.h * k <= boxH then break end
    end
    if pic.w * s > boxW or pic.h * s > boxH then s = min(boxW / pic.w, boxH / pic.h) end
    pic.quad = pic.quad or G.newQuad(pic.x0, pic.y0, pic.w, pic.h, pic.image:getDimensions())
    G.setColor(1, 1, 1, 1)
    G.draw(pic.image, pic.quad, floor(cx - pic.w * s / 2), floor(bottom - pic.h * s), 0, s, s)
    return true
  end

  return A
end
