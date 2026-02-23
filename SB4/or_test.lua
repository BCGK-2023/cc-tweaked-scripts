local CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
local LOG_PATH = "SB4/or_test.log"

local function trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function logOpen()
  local h = fs.open(LOG_PATH, "w")
  if not h then return nil end
  h.writeLine("[or_test] diagnostics")
  return h
end

local function log(h, k, v)
  if h then h.writeLine((k or "") .. ": " .. tostring(v)) end
end

local function close(h)
  if h then h.close() end
end

local function loadConfig()
  local paths = { "SB4/config.lua", "config.lua" }
  for i = 1, #paths do
    local p = paths[i]
    if fs.exists(p) then
      local ok, cfg = pcall(dofile, p)
      if ok and type(cfg) == "table" then
        return cfg, p
      end
      return nil, p
    end
  end
  return nil, nil
end

local function request(cfg)
  local body = textutils.serializeJSON({
    model = cfg.MODEL,
    messages = {
      { role = "system", content = "Reply with exactly: OK" },
      { role = "user", content = "Ping" }
    },
    max_tokens = 8,
    temperature = 0
  })

  return http.post(CHAT_URL, body, {
    ["Authorization"] = "Bearer " .. cfg.OPENROUTER_API_KEY,
    ["Content-Type"] = "application/json"
  })
end

local logh = logOpen()

local cfg, cfgPath = loadConfig()
if not cfg then
  print("or_test: config missing")
  log(logh, "config.path", tostring(cfgPath))
  close(logh)
  return
end

cfg.OPENROUTER_API_KEY = trim(cfg.OPENROUTER_API_KEY)
cfg.MODEL = trim(cfg.MODEL)

local keyLen = #cfg.OPENROUTER_API_KEY
local keyPrefix = cfg.OPENROUTER_API_KEY:sub(1, 9)

log(logh, "config.path", cfgPath)
log(logh, "model", cfg.MODEL)
log(logh, "key.len", keyLen)
log(logh, "key.prefix", keyPrefix)
log(logh, "http.checkURL", http and http.checkURL and select(1, http.checkURL(CHAT_URL)) or "n/a")

local h, err, fail = request(cfg)
local r = h or fail
local code = "none"
local raw = ""

if r then
  code = (r.getResponseCode and r.getResponseCode()) or "?"
  raw = r.readAll() or ""
  r.close()
end

log(logh, "request.err", err)
log(logh, "http.code", code)
log(logh, "response.body", raw)
close(logh)

print("or_test summary")
print("config.path: " .. tostring(cfgPath))
print("key.len: " .. tostring(keyLen))
print("http.code: " .. tostring(code))
print("log: " .. LOG_PATH)
