-- The WoobNav's words, by language: lang/<code>.lua, lang/en.lua the master (every key; what
-- another language leaves out shows in English). The LANGUAGE option picks one (options.lua);
-- the same seven languages as WoobOS and Kanto Gear. Each file is data only, run with an empty
-- environment. Never in any RNG key or cache key: words change no spawn.
--
--   T = makeI18n({ read = fn(path) -> source | nil, log = fn(fmt, ...) | nil })
--   T(key) -> the word (the language's, else English, else the key itself)
--   T.f(key, ...) -> string.format of it (a translation whose %s don't match falls back to English)
--   T.set(code) -> true | false ; T.code() ; T.languages() -> { { code, name } } (CODES order)
--   T.raw(code) -> that language's own strings (tests) ; T.CODES

local CODES = { "en", "de", "es", "fr", "it", "ja", "pt-br" }

return function(deps)
  local langs, en, cur = {}, nil, nil

  local function loadData(source, name)
    if type(source) ~= "string" then return nil, "missing" end
    local env = {}
    local chunk, err = load(source, "@" .. name, "t", env)
    if not chunk then return nil, err end
    if setfenv then setfenv(chunk, env) end
    local ok, data = pcall(chunk)
    if not ok then return nil, data end
    if type(data) ~= "table" or type(data.strings) ~= "table" then return nil, "no strings table" end
    return data
  end

  for _, code in ipairs(CODES) do
    local path = "lang/" .. code .. ".lua"
    local okR, source = pcall(deps.read, path)
    local data, err = loadData(okR and source or nil, path)
    if data then
      local strings = {}
      for k, v in pairs(data.strings) do
        if type(k) == "string" and type(v) == "string" then strings[k] = v end
      end
      langs[code] = { code = code, name = type(data.name) == "string" and data.name or code, strings = strings }
    elseif deps.log then
      deps.log("%s was skipped: %s", path, tostring(err))
    end
  end
  en = langs.en or { code = "en", name = "English", strings = {} }
  langs.en = en
  cur = en

  local T = { CODES = CODES }
  setmetatable(T, { __call = function(_, key)
    local s = cur.strings[key]
    if s == nil then s = en.strings[key] end
    if s == nil then return key end
    return s
  end })

  function T.f(key, ...)
    local ok, s = pcall(string.format, T(key), ...)
    if ok then return s end
    ok, s = pcall(string.format, en.strings[key] or key, ...)
    return ok and s or key
  end

  function T.code() return cur.code end

  function T.set(code)
    local l = langs[code]
    if not l then return false end
    cur = l
    return true
  end

  function T.languages()
    local out = {}
    for _, code in ipairs(CODES) do
      if langs[code] then out[#out + 1] = { code = code, name = langs[code].name } end
    end
    return out
  end

  function T.raw(code) return langs[code] and langs[code].strings or nil end

  return T
end
