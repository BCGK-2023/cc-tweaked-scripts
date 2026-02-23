print("[or_test] start")

local cfg = dofile("SB4/config.lua")
print("[or_test] model: " .. tostring(cfg.MODEL))

local body = textutils.serializeJSON({
  model = cfg.MODEL,
  messages = {
    { role = "system", content = "Reply with exactly: OK" },
    { role = "user", content = "Ping" }
  },
  max_tokens = 8,
  temperature = 0
})

print("[or_test] posting...")
local h, err, fail = http.post(
  "https://openrouter.ai/api/v1/chat/completions",
  body,
  {
    ["Authorization"] = "Bearer " .. tostring(cfg.OPENROUTER_API_KEY),
    ["Content-Type"] = "application/json",
    ["HTTP-Referer"] = "https://computercraft.local/bedrockos",
    ["X-Title"] = "BedrockOS"
  }
)

print("[or_test] post complete")
print("[or_test] err: " .. tostring(err))

local r = h or fail
if not r then
  print("[or_test] no response handle")
  return
end

local code = r.getResponseCode and r.getResponseCode() or "?"
local raw = r.readAll() or ""
r.close()

print("[or_test] http code: " .. tostring(code))
print("[or_test] body length: " .. tostring(#raw))
print("[or_test] body:")
print(raw)
