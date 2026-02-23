local function trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function check(name, fn)
  write(name .. ": checking... ")
  local ok = fn()
  if ok then
    print("granted")
  else
    print("denied")
    error(name .. " check failed", 0)
  end
end

local function loadConfig(path)
  local ok, cfg = pcall(dofile, path)
  if not ok or type(cfg) ~= "table" then
    return nil
  end
  cfg.OPENROUTER_API_KEY = trim(cfg.OPENROUTER_API_KEY)
  cfg.MODEL = trim(cfg.MODEL)
  if cfg.OPENROUTER_API_KEY == "" or cfg.MODEL == "" then
    return nil
  end
  return cfg
end

local config = loadConfig("SB4/config.lua")

print("[BedrockOS] Boot Sequence")
check("Config", function()
  return config ~= nil
end)

check("HTTP access", function()
  return http and http.checkURL and http.checkURL("https://openrouter.ai/api/v1/models")
end)

check("OpenRouter", function()
  return config ~= nil and config.OPENROUTER_API_KEY ~= "" and config.MODEL ~= ""
end)

print("[BedrockOS] Ready")
