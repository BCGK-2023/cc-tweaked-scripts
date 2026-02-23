local OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
local HISTORY_LIMIT = 24 -- Non-system messages kept in memory for this run.

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
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

local function check(name, fn)
  write(name .. ": checking... ")
  local ok, extra = fn()
  if ok then
    print("granted")
    return true
  end

  print("denied")
  if extra and extra ~= "" then
    print(extra)
  end
  error(name .. " check failed", 0)
end

local function loadConfig(path)
  local ok, cfg = pcall(dofile, path)
  if not ok or type(cfg) ~= "table" then
    return nil
  end

  cfg.OPENROUTER_API_KEY = trim(cfg.OPENROUTER_API_KEY)
  cfg.MODEL = trim(cfg.MODEL)
  cfg.SYSTEM_PROMPT = trim(cfg.SYSTEM_PROMPT)

  if cfg.OPENROUTER_API_KEY == "" or cfg.MODEL == "" or cfg.SYSTEM_PROMPT == "" then
    return nil
  end

  return cfg
end

local function extractAssistantText(choice)
  if type(choice) ~= "table" or type(choice.message) ~= "table" then
    return nil
  end

  local content = choice.message.content
  if type(content) == "string" then
    return content
  end

  if type(content) == "table" then
    local parts = {}
    for i = 1, #content do
      local part = content[i]
      if type(part) == "table" and part.type == "text" and type(part.text) == "string" then
        parts[#parts + 1] = part.text
      end
    end
    if #parts > 0 then
      return table.concat(parts, "\n")
    end
  end

  return nil
end

local function openRouterChat(config, messages, maxTokens)
  local payload = {
    model = config.MODEL,
    messages = messages,
    max_tokens = maxTokens or 300,
    temperature = 0.2
  }

  local body = textutils.serializeJSON(payload)
  local headers = {
    ["Authorization"] = "Bearer " .. config.OPENROUTER_API_KEY,
    ["Content-Type"] = "application/json",
    ["HTTP-Referer"] = "https://computercraft.local/bedrockos",
    ["X-Title"] = "BedrockOS"
  }

  local response, err, failResponse = http.post(OPENROUTER_CHAT_URL, body, headers)
  local handle = response or failResponse
  if not handle then
    return nil, err or "Request failed"
  end

  local raw = handle.readAll() or ""
  handle.close()

  local data = decodeJSON(raw)
  if type(data) ~= "table" then
    return nil, "Invalid JSON response"
  end

  local choices = data.choices
  if type(choices) ~= "table" or type(choices[1]) ~= "table" then
    local message = type(data.error) == "table" and data.error.message or nil
    return nil, message or "No choices in response"
  end

  local text = extractAssistantText(choices[1])
  if not text or text == "" then
    return nil, "Assistant returned empty content"
  end

  return text, nil
end

local function clampHistory(messages)
  local system = messages[1]
  local extra = #messages - 1
  if extra <= HISTORY_LIMIT then
    return messages
  end

  local keepFrom = #messages - HISTORY_LIMIT + 1
  local pruned = { system }
  for i = keepFrom, #messages do
    pruned[#pruned + 1] = messages[i]
  end
  return pruned
end

local configPath = "SB4/config.lua"
local config = loadConfig(configPath)

print("[BedrockOS] Boot Sequence")
check("Config", function()
  if config == nil then
    return false, "Create " .. configPath .. " from SB4/config.example.lua and fill values."
  end
  return true
end)

check("HTTP access", function()
  if not http or not http.checkURL then
    return false, "HTTP API is unavailable or disabled"
  end

  local ok, reason = http.checkURL(OPENROUTER_CHAT_URL)
  if not ok then
    return false, reason or "URL check failed"
  end

  return true
end)

check("OpenRouter", function()
  local probeMessages = {
    { role = "system", content = "Reply with exactly: OK" },
    { role = "user", content = "Ping" }
  }

  local reply, err = openRouterChat(config, probeMessages, 8)
  if not reply then
    return false, err or "OpenRouter probe failed"
  end

  return true
end)

print("[BedrockOS] Ready")
print("Type your message. Commands: new, exit")

local history = {
  { role = "system", content = config.SYSTEM_PROMPT }
}

while true do
  write("you> ")
  local input = trim(read())

  if input == "" then
    -- No-op for empty inputs.
  elseif input == "exit" or input == "quit" then
    print("[BedrockOS] Session ended")
    break
  elseif input == "new" then
    history = {
      { role = "system", content = config.SYSTEM_PROMPT }
    }
    print("[BedrockOS] Conversation reset")
  else
    history[#history + 1] = { role = "user", content = input }
    history = clampHistory(history)

    write("bedrockos> ")
    local reply, err = openRouterChat(config, history, 300)
    if not reply then
      print("error: " .. tostring(err))
      history[#history] = nil
    else
      print(reply)
      history[#history + 1] = { role = "assistant", content = reply }
      history = clampHistory(history)
    end
  end
end
