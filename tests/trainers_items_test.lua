-- Standalone: luajit mods/modern_spawns/tests/trainers_items_test.lua (from the
-- gen1recomp root; needs Crystal and Emerald imported and
-- mods/national_dex_gen3). TRAINER TEAMS ON + ITEMS over every story trainer:
-- held items scale with the game's progress and the battle's weight.
--   * ordinary trainers: nothing before Lv 20, then one, later one or two (the
--     items the game gave them count), a Berry or a type booster only;
--   * the rival's first battle: nothing new;
--   * Gym Leaders and other major battles: the ace always (an early Gym's a
--     Berry or booster, competitive items only late), the others by chance;
--   * the Elite Four, champions and the rival's final battle: every Pokemon;
--   * an item handed out is never one the team already holds (by the game's
--     item number: two names can be one item).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_helpers.lua")
local Runtime = require("src.mods.Runtime")
local Config = H.module("src/config.lua")
local rules = Config.TrainerConfig.items

local STRONG = { LIFE_ORB = true, CHOICE_BAND = true, CHOICE_SPECS = true, CHOICE_SCARF = true,
                 FOCUS_SASH = true, ASSAULT_VEST = true, EVIOLITE = true }
local MAJOR_ONLY = { LEFTOVERS = true, BLACK_SLUDGE = true }
for k in pairs(STRONG) do MAJOR_ONLY[k] = true end

local function stageOf(level)
  return level >= rules.late_level and "late" or level >= rules.mid_level and "mid" or "early"
end

-- battles: { label, kind ("ordinary" | "boss" | "elite" | "rival"), rivalId?, own, new }
local function check(label, battles, nameOf, itemOf)
  -- the rival's first and final battles, by their top level
  local rivalTops = {}
  local function topOf(rows)
    local top = 0
    for _, r in ipairs(rows) do top = math.max(top, tonumber(r.level) or 0) end
    return top
  end
  for _, b in ipairs(battles) do
    if b.kind == "rival" then
      local t = rivalTops[b.rivalId] or {}
      rivalTops[b.rivalId] = t
      local top = topOf(b.own)
      t.first = math.min(t.first or top, top)
      t.last = math.max(t.last or top, top)
    end
  end
  local bad = { early = {}, ordinaryMax = {}, ordinaryKind = {}, strongEarly = {}, rivalFirst = {}, full = {},
                aceMissing = {}, dup = {} }
  local count = { ordinaryMid = 0, ordinaryLate = 0, first = 0, full = 0 }
  local function note(list, text) if #list < 6 then list[#list + 1] = text end end
  for _, b in ipairs(battles) do
    local top = topOf(b.own)
    local stage = stageOf(top)
    local new, held, seen = {}, 0, {}
    for i, row in ipairs(b.new) do
      local it = itemOf(row)
      if it then
        held = held + 1
        seen[it] = (seen[it] or 0) + 1
      end
      if it and not itemOf(b.own[i]) then new[#new + 1] = { slot = i, name = nameOf(it), item = it } end
    end
    -- an item this mod hands out is never one the team already holds (the
    -- game's own teams may repeat one: Pokefans with a Berry each)
    for _, n in ipairs(new) do
      if seen[n.item] > 1 then note(bad.dup, b.label .. " " .. tostring(n.name)) end
    end
    local full = b.kind == "elite"
    local rt = b.kind == "rival" and rivalTops[b.rivalId]
    if rt and rt.first < rt.last then
      if top <= rt.first then
        count.first = count.first + 1
        if #new > 0 then note(bad.rivalFirst, b.label) end
      elseif top >= rt.last then
        full = true
      end
    end
    if full then
      count.full = count.full + 1
      if held < #b.new then note(bad.full, b.label .. " " .. held .. "/" .. #b.new) end
    elseif b.kind == "ordinary" then
      if stage == "early" and #new > 0 then note(bad.early, b.label) end
      if #new > 0 and held > 2 then note(bad.ordinaryMax, b.label .. " " .. held) end
      for _, n in ipairs(new) do
        if MAJOR_ONLY[n.name] then note(bad.ordinaryKind, b.label .. " " .. n.name) end
      end
      if stage == "mid" then count.ordinaryMid = count.ordinaryMid + #new end
      if stage == "late" then count.ordinaryLate = count.ordinaryLate + #new end
    elseif not (rt and top <= rt.first) then
      -- a major battle: its ace holds something
      local ace, aceLevel = nil, -1
      for i, row in ipairs(b.new) do
        if (tonumber(row.level) or 0) >= aceLevel then ace, aceLevel = i, tonumber(row.level) or 0 end
      end
      if not itemOf(b.new[ace]) then note(bad.aceMissing, b.label) end
      for _, n in ipairs(new) do
        if stage ~= "late" and STRONG[n.name] then note(bad.strongEarly, b.label .. " " .. n.name) end
        if stage == "early" and MAJOR_ONLY[n.name] then note(bad.strongEarly, b.label .. " " .. n.name) end
      end
    end
  end
  T.eq(table.concat(bad.early, "; "), "", label .. ": ordinary trainers before Lv " .. rules.mid_level .. " hold nothing new")
  T.check(count.ordinaryMid > 20 and count.ordinaryLate > count.ordinaryMid / 2,
          label .. ": later ordinary trainers hold some (mid " .. count.ordinaryMid .. ", late " .. count.ordinaryLate .. ")")
  T.eq(table.concat(bad.ordinaryMax, "; "), "", label .. ": an ordinary trainer holds two items at most")
  T.eq(table.concat(bad.ordinaryKind, "; "), "", label .. ": an ordinary trainer's items are Berries and boosters")
  T.check(count.first >= 3, label .. ": the rival's first battles found (" .. count.first .. ")")
  T.eq(table.concat(bad.rivalFirst, "; "), "", label .. ": the rival's first battle holds nothing new")
  T.check(count.full >= 5, label .. ": Elite Four and final rival battles found (" .. count.full .. ")")
  T.eq(table.concat(bad.full, "; "), "", label .. ": the Elite Four and the rival's final battle hold items on every Pokemon")
  T.eq(table.concat(bad.aceMissing, "; "), "", label .. ": a major battle's ace always holds something")
  T.eq(table.concat(bad.strongEarly, "; "), "", label .. ": no competitive items before Lv " .. rules.late_level
       .. ", only a Berry or booster before Lv " .. rules.mid_level)
  T.eq(table.concat(bad.dup, "; "), "", label .. ": an item handed out is never one the team already holds")
end

local function load(game, gen)
  local data
  if gen == 2 then data = H.gen2Data(game) else H.mountGen3(game) data = H.gen3Data(game) end
  local run = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/modern_spawns" }, { data = data, generation = gen })
  T.eq(#run.errors, 0, game .. ": loads clean (" .. tostring(run.errors[1]) .. ")")
  local loader = run.loader
  loader.modSave.modern_spawns = { seed = "ITEMS" }
  loader.modOptions.modern_spawns = { enabled = "on", max_generation = "9" }
  local set, game_ = H.manager(loader)
  game_.data = data
  loader.events:emit("game.ready", { game = game_ })
  set("trainer_teams", "items")
  return run, data, loader
end

-- ======================================================== Crystal

do
  local run, data = load("crystal", 2)
  local Trainers = require("src.world.gen2.Trainers")
  local ELITE = { WILL = true, KOGA = true, BRUNO = true, KAREN = true, CHAMPION = true }
  local GYM = { FALKNER = 1, BUGSY = 1, WHITNEY = 1, MORTY = 1, CHUCK = 1, JASMINE = 1, PRYCE = 1, CLAIR = 1,
                BROCK = 1, MISTY = 1, LT_SURGE = 1, ERIKA = 1, JANINE = 1, SABRINA = 1, BLAINE = 1, BLUE = 1, RED = 1 }
  local battles, falkner = {}, nil
  local classes = {}
  for class in pairs(data.gen2Trainers.classes) do classes[#classes + 1] = class end
  table.sort(classes)
  for _, class in ipairs(classes) do
    for _, m in ipairs(data.gen2Trainers.classes[class].trainers) do
      local own = Trainers.party(data, { roster = m.party })
      local new = Runtime.call("trainer.party", function(_, _, p) return p end, class, m.id, own)
      local rival = class == "RIVAL1" or class == "RIVAL2"
      local kind = ELITE[class] and "elite" or rival and "rival" or GYM[class] and "boss" or "ordinary"
      battles[#battles + 1] = { label = class .. ":" .. m.id, kind = kind, rivalId = rival and "rival" or nil,
                                own = own, new = new }
      if m.id == "FALKNER1" then falkner = { own = own, new = new } end
    end
  end
  check("Crystal", battles, function(it) return it end, function(r) return r and r.item or nil end)
  -- Falkner (Lv 9): just his ace, with a Berry or its booster
  local n, kind = 0, nil
  for i, mon in ipairs(falkner.new) do
    if mon.item and not falkner.own[i].item then n, kind = n + 1, mon.item end
  end
  T.eq(n, 1, "Crystal: Falkner's ace alone holds an item (" .. tostring(kind) .. ")")
  run.release()
end

-- ======================================================== Emerald

do
  local run, data, loader = load("emerald", 3)
  local Trainers = require("src.core.game3.scripting.trainers")
  local G3 = require("src.mods.Gen3Compat")
  local ItemsData = require("src.core.game3.items_data")
  local nameOf = {}
  local dex = loader.exports.national_dex_gen3
  for name, rec in pairs(dex and dex._held and dex._held.state and dex._held.state.byId or {}) do
    if rec.index then nameOf[rec.index] = name end
  end
  for name in pairs(MAJOR_ONLY) do
    local ok, num = pcall(ItemsData.toNumericId, name)
    if ok and num then nameOf[num] = name end
  end
  local function itemOf(r)
    local v = r and (r.item or r.heldItem)
    if v == nil or v == 0 or v == "" or v == "NONE" or v == "ITEM_NONE" then return nil end
    if type(v) == "string" then
      local ok, num = pcall(ItemsData.toNumericId, v)
      return ok and num or v
    end
    return v
  end
  local p = Trainers.pack()
  local ids = {}
  for id in pairs(p.trainers) do ids[#ids + 1] = id end
  table.sort(ids)
  local battles = {}
  for _, id in ipairs(ids) do
    local t = p.trainers[id]
    local cn = t.className or p.classNames[t.class]
    local ok, foe = pcall(Trainers.foeFromId, id)
    if ok and foe and foe.party then
      local named = G3.partyNames(foe.party)
      local new = Runtime.call("trainer.party", function(_, _, x) return x end, foe.trainerClass, id, named)
      local rival = cn and cn:find("TRAINER") and (t.name == "MAY" or t.name == "BRENDAN")
      local kind = (cn == "ELITE FOUR" or cn == "CHAMPION") and "elite" or rival and "rival"
        or (cn == "LEADER" or cn == "AQUA LEADER" or cn == "MAGMA LEADER") and "boss"
        or (cn and cn:find("TRAINER") and t.name ~= "?") and "boss" or "ordinary"
      battles[#battles + 1] = { label = tostring(cn) .. ":" .. tostring(t.name) .. "#" .. id, kind = kind,
                                rivalId = rival and t.name or nil, own = named, new = new }
    end
  end
  check("Emerald", battles, function(it) return nameOf[it] or tostring(it) end, itemOf)
  run.release()
end

T.finish("modern_spawns trainers (held items by progress)")
