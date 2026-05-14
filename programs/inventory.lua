-- inventory — мониторинг и управление инвентарём игрока через PIM.
-- @deps: pim
-- Usage:
--   pull inventory                              показать инвентарь один раз (текст)
--   pull inventory watch                        следить непрерывно (GPU-сетка)
--   pull inventory dump <slot>                  полный дамп стака слота (NBT/extended)
--   pull inventory pull <side> <slot> [qty]     забрать из PIM в инвентарь со стороны
--   pull inventory push <side> <slot> [qty]     положить в PIM из инвентаря со стороны

local component = require("component")
local event     = require("event")
local term      = require("term")
local shell     = require("shell")
local sides     = require("sides")

package.loaded.pim = nil   -- сброс кеша require, чтобы взять свежую версию
local ok_lib, pim = pcall(require, "pim")
if not ok_lib then
  io.stderr:write("Не найден /lib/pim.lua. Установи: pull lib/pim\n")
  return 1
end

local args, opts = shell.parse(...)

local proxy, addr, ptype = pim.find()
if not proxy then
  io.stderr:write("PIM-компонент не найден.\n")
  io.stderr:write("Доступные компоненты:\n")
  for c_addr, c_type in component.list() do
    io.stderr:write(string.format("  %-32s  %s\n", c_type, c_addr:sub(1, 8)))
  end
  return 1
end

if opts.verbose then
  io.write(string.format("[pim] %s @ %s\n", ptype, addr))
end

local cmd = args[1]

-- ── dump <slot> ──────────────────────────────────────────────
if cmd == "dump" then
  local slot = tonumber(args[2])
  if not slot then
    io.stderr:write("Usage: pull inventory dump <slot>\n")
    return 1
  end

  local serialization = require("serialization")
  local function show(label, value)
    print("\n=== " .. label .. " ===")
    if type(value) == "table" then
      print(serialization.serialize(value, true))
    else
      print(tostring(value))
    end
  end

  -- 1) Обычный getStackInSlot
  local ok1, st = pcall(proxy.getStackInSlot, slot)
  if not ok1 then
    print("getStackInSlot упал: " .. tostring(st))
    return 1
  end
  if not st then
    print(string.format("slot %d: пусто", slot))
    return 0
  end
  show(string.format("getStackInSlot(%d)", slot), st)

  -- 2) Wrapper-объект с advanced API: .all() / .keys() / .single(key)
  local ok2, wrap = pcall(proxy.getStackInSlot, slot, true)
  if ok2 and type(wrap) == "table" and type(wrap.all) == "function" then
    local ok_keys, keys = pcall(wrap.keys)
    if ok_keys then show("stack:keys()", keys) end

    local ok_all, all = pcall(wrap.all)
    if ok_all then show("stack:all()", all) end

    if type(wrap.listMethods) == "function" then
      local ok_lm, lm = pcall(wrap.listMethods)
      if ok_lm then show("stack:listMethods()", lm) end
    end
  end

  -- 3) Методы самого PIM-компонента — listMethods и getAdvancedMethodsData
  if type(proxy.listMethods) == "function" then
    local ok3, lm = pcall(proxy.listMethods)
    if ok3 then show("proxy.listMethods()", lm) end
  end
  if type(proxy.getAdvancedMethodsData) == "function" then
    local ok4, data = pcall(proxy.getAdvancedMethodsData)
    if ok4 then show("proxy.getAdvancedMethodsData()", data) end
  end

  return 0
end

-- ── pull / push ───────────────────────────────────────────────
if cmd == "pull" or cmd == "push" then
  local side_name = args[2]
  local slot      = tonumber(args[3])
  local qty       = tonumber(args[4])
  if not side_name or not slot then
    io.stderr:write(string.format(
      "Usage: pull inventory %s <side> <slot> [qty]\n", cmd))
    io.stderr:write("Sides: top | bottom | north | south | east | west\n")
    return 1
  end
  local side = sides[side_name]
  if side == nil then
    io.stderr:write("Неизвестная сторона: " .. side_name .. "\n")
    return 1
  end
  local fn = (cmd == "pull") and pim.pull or pim.push
  local success, moved = fn(proxy, side, slot, qty)
  if not success then
    io.stderr:write("Ошибка: " .. tostring(moved) .. "\n")
    return 1
  end
  print(string.format("[%s] %s slot=%d → %s",
                      cmd, side_name, slot, tostring(moved)))
  return 0
end

-- ── вспомогательные ───────────────────────────────────────────
local function truncate(s, n)
  if not s or s == "" then return "" end
  if #s <= n then return s end
  return s:sub(1, n - 1) .. "…"
end

-- ── текстовый дамп ────────────────────────────────────────────
local function draw_text()
  io.write("\n")
  local owner = pim.owner(proxy)
  print("PIM " .. addr:sub(1, 8) .. (owner and ("  (" .. owner .. ")") or ""))

  local armor = pim.armor(proxy)
  if armor then
    print("Armor:")
    for i, st in ipairs(armor) do
      print(string.format("  %d: %s", i, pim.name(st)))
    end
  end

  local inv, size = pim.inventory(proxy)
  if not inv then
    print("Inventory: <ошибка чтения>")
    return
  end
  local nonempty = 0
  for i = 1, size do if inv[i] then nonempty = nonempty + 1 end end
  print(string.format("Inventory (%d/%d занято):", nonempty, size))
  for i = 1, size do
    local st = inv[i]
    if st then
      print(string.format("  %2d: %3d × %s", i, pim.qty(st), pim.name(st)))
    end
  end
end

-- ── GPU-сетка для watch ───────────────────────────────────────
local gpu = component.gpu

local CELL_W, CELL_H = 8, 3
local GRID_COLS = 9
local GRID_ROWS_MAIN = 3   -- основной инвентарь: 3 ряда (слоты 10..36)
                            -- хотбар (слоты 1..9) рисуется отдельно ниже

-- Достать короткое имя предмета: отрезать modid-префикс (minecraft:...) и
-- обрезать до n символов.
local function short_name(st, n)
  local s = pim.name(st)
  if not s or s == "" then return "" end
  local colon = s:find(":")
  if colon then s = s:sub(colon + 1) end
  if #s > n then s = s:sub(1, n) end
  return s
end

local function draw_cell(x, y, slot, st)
  local qty = pim.qty(st)
  if qty > 0 then
    gpu.setBackground(0x1F3D1F)
  else
    gpu.setBackground(0x202020)
  end
  gpu.fill(x, y, CELL_W, CELL_H, " ")

  -- номер слота сверху слева
  gpu.setForeground(0x808080)
  gpu.set(x + 1, y, string.format("%2d", slot))

  if qty > 0 then
    -- имя предмета по центру, обрезанное под ширину ячейки
    local name = short_name(st, CELL_W - 2)
    if name ~= "" then
      gpu.setForeground(0xCCFFCC)
      gpu.set(x + math.floor((CELL_W - #name) / 2), y + 1, name)
    end
    -- количество снизу: x<qty>
    gpu.setForeground(0xFFFFFF)
    local q = "x" .. tostring(qty)
    gpu.set(x + math.floor((CELL_W - #q) / 2), y + 2, q)
  end
end

local function draw_grid(inv, armor)
  local w, h = gpu.getResolution()

  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")

  local owner = pim.owner(proxy)
  local title = "PIM " .. addr:sub(1, 8) ..
                (owner and ("  (" .. owner .. ")") or "")
  gpu.set(2, 1, title)
  gpu.setForeground(0x666666)
  gpu.set(2, 2, "watch — Ctrl+Alt+C выход")
  gpu.setForeground(0xFFFFFF)

  local x0 = 2
  local y0 = 4

  -- main: слоты 10..36 (3 ряда × 9 столбцов)
  for row = 0, GRID_ROWS_MAIN - 1 do
    for col = 0, GRID_COLS - 1 do
      local slot = 10 + row * GRID_COLS + col
      draw_cell(x0 + col * CELL_W, y0 + row * CELL_H, slot, inv and inv[slot])
    end
  end

  -- зазор + hotbar: слоты 1..9
  local hot_y = y0 + GRID_ROWS_MAIN * CELL_H + 1
  for col = 0, GRID_COLS - 1 do
    local slot = 1 + col
    draw_cell(x0 + col * CELL_W, hot_y, slot, inv and inv[slot])
  end

  -- armor сбоку
  if armor then
    local ax = x0 + GRID_COLS * CELL_W + 2
    gpu.setBackground(0x000000)
    gpu.setForeground(0xAAAAAA)
    gpu.set(ax, y0, "Armor:")
    for i, st in ipairs(armor) do
      local label = pim.name(st)
      if label == "" then label = "—" end
      gpu.setForeground(pim.qty(st) > 0 and 0xCCCCFF or 0x444444)
      gpu.set(ax, y0 + i, string.format("%d: %s", i, truncate(label, 14)))
    end
  end

  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
end

-- Снимок инвентаря: одна строка-отпечаток для быстрого сравнения "изменилось/нет"
local function snapshot(inv, armor)
  local parts = {}
  if inv then
    for i = 1, #inv do
      local st = inv[i]
      if st then
        parts[#parts + 1] =
          string.format("i%d:%s:%d", i, pim.name(st), pim.qty(st))
      end
    end
  end
  if armor then
    for i = 1, #armor do
      local st = armor[i]
      if st then
        parts[#parts + 1] =
          string.format("a%d:%s:%d", i, pim.name(st), pim.qty(st))
      end
    end
  end
  return table.concat(parts, "|")
end

if cmd == "watch" then
  local last_snap = nil
  while true do
    local inv = pim.inventory(proxy)
    local armor = pim.armor(proxy)
    local snap = snapshot(inv, armor)
    if snap ~= last_snap then
      draw_grid(inv, armor)
      last_snap = snap
    end
    local ev = event.pull(0.1)
    if ev == "interrupted" then
      term.clear()
      print("bye.")
      break
    end
  end
  return 0
end

-- по умолчанию — одноразовый текстовый вывод
draw_text()
return 0
