-- pull — загрузчик скриптов с публичного GitHub-репозитория.
-- Usage:
--   pull <name> [args...]    скачать (или из кеша) и запустить
--   pull --update <name>     принудительно обновить из сети
--   pull --list              что лежит в кеше
--   pull --self-update       обновить сам pull.lua в /bin

local component = require("component")
local internet  = require("internet")
local fs        = require("filesystem")
local shell     = require("shell")

-- === Конфигурация ===
local REPO   = "1Boop2/mc-opencomp"
local BRANCH = "main"
local PREFIX = "programs/"        -- путь внутри репо до Lua-скриптов
local CACHE  = "/home/.pull_cache/"
local SELF   = "/bin/pull.lua"
-- =====================

local function url_for(name)
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s%s",
    REPO, BRANCH, PREFIX, name
  )
end

local function fetch(url)
  if not component.isAvailable("internet") then
    return nil, "нет internet card"
  end
  local handle, err = internet.request(url)
  if not handle then
    return nil, "request: " .. tostring(err)
  end
  local body = ""
  for chunk in handle do
    body = body .. chunk
  end
  if #body == 0 then
    return nil, "пустой ответ"
  end
  -- GitHub raw на 404 отдаёт "404: Not Found"
  if body:match("^404") then
    return nil, "404 Not Found: " .. url
  end
  return body
end

local function write_file(path, body)
  local dir = fs.path(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDirectory(dir)
  end
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(body)
  f:close()
  return true
end

local args, opts = shell.parse(...)

if opts["self-update"] then
  local body, err = fetch(url_for("pull.lua"))
  if not body then
    io.stderr:write("[pull] self-update: " .. err .. "\n")
    return 1
  end
  local ok, werr = write_file(SELF, body)
  if not ok then
    io.stderr:write("[pull] self-update: " .. tostring(werr) .. "\n")
    return 1
  end
  print("[pull] обновлён: " .. SELF)
  return 0
end

if opts.list then
  if not fs.exists(CACHE) then
    print("(кеш пуст)")
    return 0
  end
  for entry in fs.list(CACHE) do
    print(entry)
  end
  return 0
end

if #args == 0 then
  io.stderr:write([[
Usage:
  pull <name> [args...]   скачать (или из кеша) и запустить
  pull --update <name>    принудительно обновить
  pull --list             что в кеше
  pull --self-update      обновить сам pull.lua в /bin
]])
  return 1
end

local name = args[1]
if not name:match("%.lua$") then
  name = name .. ".lua"
end

local cache_path = CACHE .. name
local need_fetch = opts.update or not fs.exists(cache_path)

if need_fetch then
  print("[pull] " .. url_for(name))
  local body, err = fetch(url_for(name))
  if not body then
    io.stderr:write("[pull] " .. err .. "\n")
    return 1
  end
  local ok, werr = write_file(cache_path, body)
  if not ok then
    io.stderr:write("[pull] кеш: " .. tostring(werr) .. "\n")
    return 1
  end
else
  print("[pull] cached: " .. cache_path .. "   (--update чтобы обновить)")
end

-- Собираем команду для shell.execute: путь + остальные аргументы
local cmd = cache_path
for i = 2, #args do
  cmd = cmd .. " " .. args[i]
end

local ok, code = shell.execute(cmd)
if not ok then
  io.stderr:write("[pull] ошибка выполнения: " .. tostring(code) .. "\n")
  return 1
end
return 0
