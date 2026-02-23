-- BedrockOS OpenRouter diagnostics
-- Purpose: isolate auth/model/header/path issues from inside CC:Tweaked.

local CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
local MODELS_URL = "https://openrouter.ai/api/v1/models"

local function line()
  print(string.rep("-", 60))
end

local function kv(k, v)
  print(string.format("[or_test] %-24s %s", k .. ":", tostring(v)))
end

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function safeReadAll(h)
  if not h then
    return ""
  end
  local ok, body = pcall(function()
    return h.readAll() or ""
  end)
  if not ok then
    return "<readAll failed: " .. tostring(body) .. ">"
  end
  return body
end

local function safeClose(h)
  if not h then
    return
  end
  pcall(function()
    h.close()
  end)
end

local function getCode(h)
  if not h or type(h.getResponseCode) ~= "function" then
    return "?"
  end
  local ok, code = pcall(function()
    return h.getResponseCode()
  end)
  if ok then
    return code
  end
  return "?"
end

local function decodeJSON(raw)
  if textutils.unserializeJSON then
    return textutils.unserializeJSON(raw)
  end
  if textutils.unserialiseJSON then
    return textutils.unserialiseJSON(raw)
  end
  return nil
end

local function loadConfig()
  local candidates = {
    "SB4/config.lua",
    "config.lua"
  }

  for i = 1, #candidates do
    local p = candidates[i]
    if fs.exists(p) then
      local ok, cfg = pcall(dofile, p)
      if ok and type(cfg) == "table" then
        return cfg, p, nil
      end
      return nil, p, "dofile failed: " .. tostring(cfg)
    end
  end

  return nil, nil, "No config found (checked SB4/config.lua and config.lua)"
end

local function summarizeKey(key)
  key = tostring(key or "")
  local len = #key
  local prefix = key:sub(1, 9)
  local suffix = key:sub(math.max(1, len - 5), len)
  local lastByte = len > 0 and key:byte(len) or -1
  local hasCR = key:find("\r", 1, true) ~= nil
  local hasLF = key:find("\n", 1, true) ~= nil
  local hasTab = key:find("\t", 1, true) ~= nil

  kv("key.len", len)
  kv("key.prefix", prefix)
  kv("key.suffix", suffix)
  kv("key.last_byte", lastByte)
  kv("key.has_CR", hasCR)
  kv("key.has_LF", hasLF)
  kv("key.has_TAB", hasTab)
end

local function request(label, url, body, headers)
  line()
  kv("request", label)
  kv("url", url)

  local h, err, fail = http.post(url, body, headers)
  local r = h or fail

  kv("post.err", err)
  if not r then
    kv("response", "none")
    return nil
  end

  local code = getCode(r)
  local raw = safeReadAll(r)
  safeClose(r)

  kv("http.code", code)
  kv("body.len", #raw)
  print("[or_test] body:")
  print(raw)

  return {
    code = code,
    body = raw,
    json = decodeJSON(raw)
  }
end

local function requestGet(label, url, headers)
  line()
  kv("request", label)
  kv("url", url)

  local h, err, fail = http.get(url, headers)
  local r = h or fail

  kv("get.err", err)
  if not r then
    kv("response", "none")
    return nil
  end

  local code = getCode(r)
  local raw = safeReadAll(r)
  safeClose(r)

  kv("http.code", code)
  kv("body.len", #raw)
  print("[or_test] body:")
  print(raw)

  return {
    code = code,
    body = raw,
    json = decodeJSON(raw)
  }
end

local function run()
  line()
  kv("version", _HOST or "unknown")
  kv("cwd", shell and shell.dir() or "?")
  kv("http api present", http ~= nil)
  kv("http.checkURL present", http and http.checkURL ~= nil)
  kv("fs.exists SB4/config.lua", fs.exists("SB4/config.lua"))
  kv("fs.exists config.lua", fs.exists("config.lua"))

  line()
  kv("checkURL chat", http and http.checkURL and select(1, http.checkURL(CHAT_URL)) or "n/a")
  kv("checkURL models", http and http.checkURL and select(1, http.checkURL(MODELS_URL)) or "n/a")

  local cfg, cfgPath, cfgErr = loadConfig()
  line()
  kv("config.path", cfgPath or "none")
  if cfgErr then
    kv("config.error", cfgErr)
    return
  end

  cfg.OPENROUTER_API_KEY = trim(cfg.OPENROUTER_API_KEY)
  cfg.MODEL = trim(cfg.MODEL)
  cfg.SYSTEM_PROMPT = trim(cfg.SYSTEM_PROMPT)

  kv("model", cfg.MODEL)
  kv("system_prompt.len", #cfg.SYSTEM_PROMPT)
  summarizeKey(cfg.OPENROUTER_API_KEY)

  local headersBase = {
    ["Authorization"] = "Bearer " .. cfg.OPENROUTER_API_KEY,
    ["Content-Type"] = "application/json"
  }

  local payload = {
    model = cfg.MODEL,
    messages = {
      { role = "system", content = "Reply with exactly: OK" },
      { role = "user", content = "Ping" }
    },
    max_tokens = 8,
    temperature = 0
  }

  local body = textutils.serializeJSON(payload)

  -- Test A: Minimal standard headers
  request("chat/minimal_headers", CHAT_URL, body, headersBase)

  -- Test B: BedrockOS-style headers
  local headersWithMeta = {
    ["Authorization"] = "Bearer " .. cfg.OPENROUTER_API_KEY,
    ["Content-Type"] = "application/json",
    ["HTTP-Referer"] = "https://computercraft.local/bedrockos",
    ["X-Title"] = "BedrockOS"
  }
  request("chat/with_meta_headers", CHAT_URL, body, headersWithMeta)

  -- Test C: Models endpoint with auth header
  requestGet("models/list_probe", MODELS_URL, {
    ["Authorization"] = "Bearer " .. cfg.OPENROUTER_API_KEY,
    ["Content-Type"] = "application/json"
  })

  line()
  print("[or_test] done")
end

print("[or_test] start")
local ok, err = pcall(run)
if not ok then
  line()
  print("[or_test] fatal: " .. tostring(err))
end
