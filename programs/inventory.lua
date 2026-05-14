-- inventory — мониторинг и управление инвентарём игрока через PIM.
-- Usage:
--   pull inventory                              показать инвентарь один раз (текст)
--   pull inventory watch                        следить непрерывно (GPU-сетка, 0.5 сек)
--   pull inventory pull <side> <slot> [qty]     забрать из PIM в инвентарь со стороны
--   pull inventory push <side> <slot> [qty]     положить в PIM из инвентаря со стороны
--
-- Требует /lib/pim.lua — поставь через:  pull lib/pim

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
  io.stderr:write("Доступные компоненты (для диагностики):\n")
  for c_addr, c_type in component.list() do
    io.stderr:write(string.format("  %-32s  %s\n", c_type, c_addr:sub(1, 8)))
  end
  io.stderr:write("\nЕсли видишь тут что-то похожее на PIM с непривычным именем — \n")
  io.stderr:write("скажи, какое именно. Добавлю в lib/pim.lua → KNOWN_TYPES.\n")
  return 1
end

if opts.verbose then
  io.write(string.format("[pim] %s @ %s\n", ptype, addr))
end

local cmd = args[1]

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
  if not owner then
    print("(на PIM никого нет)")
    return
  end
  print("Player: " .. owner)

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
  print(string.format("Inventory (%d slots, занято):", size))
  for i = 1, size do
    local st = inv[i]
    if st then
      print(string.format("  %2d: %3d × %s", i, pim.qty(st), pim.name(st)))
    end
  end
end

-- ── GPU-сетка для watch ───────────────────────────────────────
local gpu = component.gpu

local CELL_W, CELL_H = 7, 3
local GRID_COLS = 9
local GRID_ROWS_MAIN = 3   -- основной инвентарь: 3 ряда (слоты 10..36)
                            -- хотбар (слоты 1..9) рисуется отдельно ниже

local function draw_cell(x, y, slot, st)
  local qty = pim.qty(st)
  if qty > 0 then
    gpu.setBackground(0x1F3D1F)
    gpu.setForeground(0xCCFFCC)
  else
    gpu.setBackground(0x202020)
    gpu.setForeground(0x555555)
  end
  gpu.fill(x, y, CELL_W, CELL_H, " ")

  -- номер слота слева сверху мелким серым
  gpu.setForeground(0x808080)
  gpu.set(x + 1, y, string.format("%2d", slot))

  -- количество — по центру
  if qty > 0 then
    gpu.setForeground(0xFFFFFF)
    local s = tostring(qty)
    gpu.set(x + math.floor((CELL_W - #s) / 2), y + 1, s)
  end
end

local function draw_grid()
  local w, h = gpu.getResolution()

  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")

  local owner = pim.owner(proxy)
  local title = owner and ("Player: " .. owner) or "(PIM пуст)"
  gpu.set(2, 1, title)
  gpu.setForeground(0x666666)
  gpu.set(2, 2, "PIM " .. addr:sub(1, 8) .. " — Ctrl+Alt+C выход")
  gpu.setForeground(0xFFFFFF)

  if not owner then return end

  local x0 = 2
  local y0 = 4

  -- main: слоты 10..36 (3 ряда × 9 столбцов)
  for row = 0, GRID_ROWS_MAIN - 1 do
    for col = 0, GRID_COLS - 1 do
      local slot = 10 + row * GRID_COLS + col
      draw_cell(x0 + col * CELL_W, y0 + row * CELL_H,
                slot, pim.stack(proxy, slot))
    end
  end

  -- зазор + hotbar: слоты 1..9
  local hot_y = y0 + GRID_ROWS_MAIN * CELL_H + 1
  for col = 0, GRID_COLS - 1 do
    local slot = 1 + col
    draw_cell(x0 + col * CELL_W, hot_y, slot, pim.stack(proxy, slot))
  end

  -- armor сбоку
  local armor = pim.armor(proxy)
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

if cmd == "watch" then
  while true do
    draw_grid()
    local ev = event.pull(0.5)
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
