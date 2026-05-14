-- pull — загрузчик скриптов и библиотек с публичного GitHub-репозитория.
-- Каждый pull тянет свежую копию (минуя CDN-кеш через ?t=).
-- Программа может объявить зависимости в комментарии:  -- @deps: pim, foo
-- Эти библиотеки тоже будут скачаны свежими перед запуском.
--
-- Usage:
--   pull <name> [args...]   programs/<name>.lua: свежее, +deps, запустить
--   pull lib/<name>         lib/<name>.lua в /lib/ (всегда свежее)
--   pull --self-update      обновить сам pull.lua в /bin
--   pull --version          версия pull
--   pull --list             что лежит в кеше

local component = require("component")
local internet  = require("internet")
local fs        = require("filesystem")
local shell     = require("shell")
local computer  = require("computer")

-- === Конфигурация ===
local VERSION = "2026-05-14.8-verify-write"
local REPO   = "1Boop2/mc-opencomp"
local BRANCH = "main"
local CACHE  = "/home/.pull_cache/"
local LIBDIR = "/lib/"
local SELF   = "/bin/pull.lua"
-- =====================

local function url_for(subdir, name)
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s%s?t=%d",
    REPO, BRANCH, subdir, name,
    math.floor(computer.uptime() * 1000)
  )
end

local function fetch(url)
  if not component.isAvailable("internet") then
    return nil, "нет internet card"
  end
  local handle, err = internet.request(url)
  if not handle then return nil, "request: " .. tostring(err) end
  local body = ""
  for chunk in handle do body = body .. chunk end
  if #body == 0 then return nil, "пустой ответ" end
  if body:match("^404") then return nil, "404 Not Found: " .. url end
  return body
end

local function write_file(path, body)
  local dir = fs.path(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDirectory(dir)
  end
  if fs.exists(path) then
    print("[pull] rm " .. path)
    local ok_r, rerr = fs.remove(path)
    if not ok_r then
      return nil, "fs.remove failed: " .. tostring(rerr)
    end
  end
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(body)
  f:close()
  -- Verify: прочитать обратно, убедиться что запись полная
  local rf = io.open(path, "r")
  if rf then
    local back = rf:read("*a")
    rf:close()
    if back ~= body then
      return nil, string.format(
        "verify failed: wrote %d, got back %d", #body, back and #back or 0)
    end
  end
  return true
end

-- Тянем и пишем. Возвращает body или nil + err.
local function fetch_and_save(subdir, name, target_path)
  local url = url_for(subdir, name)
  print("[pull] " .. url)
  local body, err = fetch(url)
  if not body then return nil, err end
  local ok, werr = write_file(target_path, body)
  if not ok then return nil, werr end
  print(string.format("[pull] saved %d bytes → %s", #body, target_path))
  return body
end

-- Парс зависимостей из тела скрипта:  -- @deps: foo, bar
local function parse_deps(body)
  local list = {}
  local line = body:match("%-%-%s*@deps:%s*([^\r\n]+)")
  if line then
    for dep in line:gmatch("[%w_]+") do
      list[#list + 1] = dep
    end
  end
  return list
end

-- ── Main ──────────────────────────────────────────────────────
local args, opts = shell.parse(...)

if opts.version then
  print("pull " .. VERSION)
  print("REPO=" .. REPO .. " BRANCH=" .. BRANCH)
  return 0
end

if opts["self-update"] then
  local _, err = fetch_and_save("programs/", "pull.lua", SELF)
  if err then
    io.stderr:write("[pull] self-update: " .. err .. "\n")
    return 1
  end
  return 0
end

if opts.list then
  if not fs.exists(CACHE) then print("(кеш пуст)") return 0 end
  for entry in fs.list(CACHE) do print(entry) end
  return 0
end

if #args == 0 then
  io.stderr:write([[
Usage:
  pull <name> [args...]   programs/<name>.lua: свежее, +deps, запустить
  pull lib/<name>         lib/<name>.lua в /lib/ (всегда свежее)
  pull --self-update      обновить сам pull.lua в /bin
  pull --version          версия pull
  pull --list             что в кеше
]])
  return 1
end

-- ── разбор имени: lib/* идёт в /lib/, остальное — в кеш ────
local raw = args[1]
local is_lib = false
local name = raw
if name:sub(1, 4) == "lib/" then
  is_lib = true
  name = name:sub(5)
end
if not name:match("%.lua$") then name = name .. ".lua" end

local target_path, subdir
if is_lib then
  target_path = LIBDIR .. name
  subdir = "lib/"
else
  target_path = CACHE .. name
  subdir = "programs/"
end

local body, err = fetch_and_save(subdir, name, target_path)
if not body then
  io.stderr:write("[pull] " .. err .. "\n")
  return 1
end

-- ── для программ — подтянуть deps свежими ─────────────────
if not is_lib then
  for _, dep in ipairs(parse_deps(body)) do
    local dep_file = dep:match("%.lua$") and dep or (dep .. ".lua")
    local _, derr = fetch_and_save("lib/", dep_file, LIBDIR .. dep_file)
    if derr then
      io.stderr:write(string.format("[pull dep %s] %s\n", dep, derr))
    end
  end

  -- ── запуск программы ────────────────────────────────────
  local cmd = target_path
  for i = 2, #args do cmd = cmd .. " " .. args[i] end
  local ok, code = shell.execute(cmd)
  if not ok then
    io.stderr:write("[pull] exec: " .. tostring(code) .. "\n")
    return 1
  end
end

return 0
