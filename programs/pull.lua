-- pull — загрузчик скриптов и библиотек с публичного GitHub-репозитория.
-- Usage:
--   pull <name> [args...]      programs/<name>.lua: ВСЕГДА свежее, запустить
--   pull --cached <name>       взять из /home/.pull_cache/, если есть
--   pull lib/<name>            lib/<name>.lua в /lib/ (один раз; --update перекачает)
--   pull --update lib/<name>   принудительно обновить библиотеку
--   pull --list                что лежит в кеше programs
--   pull --self-update         обновить сам pull.lua в /bin

local component = require("component")
local internet  = require("internet")
local fs        = require("filesystem")
local shell     = require("shell")

-- === Конфигурация ===
local VERSION = "2026-05-14.4-fresh-default-cachebust"
local REPO   = "1Boop2/mc-opencomp"
local BRANCH = "main"
local CACHE  = "/home/.pull_cache/"
local LIBDIR = "/lib/"
local SELF   = "/bin/pull.lua"
-- =====================

-- Добавляем ?t=<uptime>, чтобы обойти CDN-кеш GitHub и любые промежуточные
-- кеши. raw.githubusercontent.com игнорирует query string, а CDN считает
-- URL уникальным и тянет свежее.
local function url_for(subdir, name)
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s%s?t=%d",
    REPO, BRANCH, subdir, name,
    math.floor(require("computer").uptime() * 1000)
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
  -- GitHub raw на 404 отдаёт текст "404: Not Found"
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
  -- В OpenOS io.open("w") иногда не truncates корректно — удаляем заранее.
  if fs.exists(path) then
    fs.remove(path)
  end
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(body)
  f:close()
  return true
end

local args, opts = shell.parse(...)

-- ── --version ─────────────────────────────────────────────
if opts.version then
  print("pull " .. VERSION)
  print("REPO=" .. REPO .. " BRANCH=" .. BRANCH)
  return 0
end

-- ── --self-update ─────────────────────────────────────────
if opts["self-update"] then
  local body, err = fetch(url_for("programs/", "pull.lua"))
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

-- ── --list ────────────────────────────────────────────────
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
  pull <name> [args...]   programs/<name>.lua: всегда свежее, запустить
  pull --cached <name>    из /home/.pull_cache/, если есть
  pull lib/<name>         lib/<name>.lua в /lib/ (один раз; --update перекачает)
  pull --update lib/<name>  перетянуть библиотеку
  pull --list             что в кеше
  pull --self-update      обновить сам pull.lua в /bin
]])
  return 1
end

-- ── разбор имени: lib/* идёт в /lib/, остальное — в кеш ──
local raw_name = args[1]
local is_lib = false
local name = raw_name
if name:sub(1, 4) == "lib/" then
  is_lib = true
  name = name:sub(5)
end

if not name:match("%.lua$") then
  name = name .. ".lua"
end

local target_path, subdir
if is_lib then
  target_path = LIBDIR .. name
  subdir = "lib/"
else
  target_path = CACHE .. name
  subdir = "programs/"
end

-- Программы всегда свежие (если не указан --cached);
-- библиотеки ставятся один раз (если уже есть и нет --update — не качаем).
local need_fetch
if is_lib then
  need_fetch = opts.update or not fs.exists(target_path)
else
  need_fetch = not opts.cached
end

if need_fetch then
  local url = url_for(subdir, name)
  print("[pull] " .. url)
  local body, err = fetch(url)
  if not body then
    if not is_lib and fs.exists(target_path) then
      io.stderr:write("[pull] " .. err .. " — fallback к кешу\n")
    else
      io.stderr:write("[pull] " .. err .. "\n")
      return 1
    end
  else
    local ok, werr = write_file(target_path, body)
    if not ok then
      io.stderr:write("[pull] " .. tostring(werr) .. "\n")
      return 1
    end
    print(string.format("[pull] saved %d bytes → %s", #body, target_path))
  end
else
  print("[pull] cached: " .. target_path)
end

-- ── библиотеки не запускаем ──────────────────────────────
if is_lib then
  print("[pull] installed: " .. target_path)
  return 0
end

-- ── запуск программы ─────────────────────────────────────
local cmd = target_path
for i = 2, #args do
  cmd = cmd .. " " .. args[i]
end

local ok, code = shell.execute(cmd)
if not ok then
  io.stderr:write("[pull] ошибка выполнения: " .. tostring(code) .. "\n")
  return 1
end
return 0
