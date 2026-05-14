-- @version: 2026-05-14-shop — shop: магазин с touch UI
-- @deps: pim, prices, me
-- Usage: pull shop
--
-- Требования:
--  - T2+ screen + touch
--  - PIM рядом с компьютером
--  - (опционально) AE2 ME Controller/Interface — для склада
--    Если ME подключён — buy/sell через AE2-сеть.
--    Если нет — продажа через сторону SIDE (можно поставить сундук).
--
-- Управление: всё кликами на экране. Ctrl+Alt+C — выход.

local component = require("component")
local event = require("event")
local term = require("term")
local sides = require("sides")
local fs = require("filesystem")
local serialization = require("serialization")
local unicode = require("unicode")

package.loaded.pim = nil
package.loaded.prices = nil
package.loaded.me = nil
local pim = require("pim")
local prices = require("prices")
local me_lib = require("me")

local VERSION = "2026-05-14-shop"
print(string.format("[shop %s | pim %s | prices %s | me %s]",
  VERSION, pim._VERSION or "?", prices._VERSION or "?", me_lib._VERSION or "?"))

-- ── конфиг ─────────────────────────────────────────────────────
local STATE_FILE = "/home/.shop_state.dat"
local STORAGE_SIDE = sides.east   -- сторона PIM, где стоит ME Interface / сундук
local COLS, ROWS = 4, 5            -- сетка предметов
local ITEMS_PER_PAGE = COLS * ROWS
local STARTING_BALANCE = 100.0     -- стартовый баланс если новая база

-- ── компоненты ─────────────────────────────────────────────────
local pim_proxy, pim_addr = pim.find()
if not pim_proxy then
  io.stderr:write("PIM не найден\n")
  return 1
end

local me_proxy, me_addr = me_lib.find()
if me_proxy then
  print("[shop] ME @ " .. me_addr:sub(1, 8))
else
  print("[shop] ME не найдена — режим без склада")
end

local gpu = component.gpu
local screen_w, screen_h = gpu.getResolution()
if screen_w < 80 or screen_h < 25 then
  io.stderr:write("Нужен экран T2+ (минимум 80x25)\n")
  return 1
end

-- ── состояние (баланс) ─────────────────────────────────────────
local function load_state()
  if not fs.exists(STATE_FILE) then
    return { balance = STARTING_BALANCE }
  end
  local f = io.open(STATE_FILE, "r")
  if not f then return { balance = STARTING_BALANCE } end
  local content = f:read("*a")
  f:close()
  local ok, st = pcall(serialization.unserialize, content)
  if not ok or type(st) ~= "table" then return { balance = STARTING_BALANCE } end
  return st
end

local function save_state(st)
  local f = io.open(STATE_FILE, "w")
  if f then
    f:write(serialization.serialize(st))
    f:close()
  end
end

local state = load_state()

-- ── список предметов ───────────────────────────────────────────
local function build_item_list()
  local list = {}
  for key, price in pairs(prices.table) do
    -- key вида "modid:itemname:meta"
    local last_colon = key:match(".*():")
    if last_colon then
      local meta = tonumber(key:sub(last_colon + 1)) or 0
      local id = key:sub(1, last_colon - 1)
      list[#list + 1] = {
        key = key, id = id, meta = meta, price = price,
        short = id:match(":([^:]+)$") or id,
      }
    end
  end
  table.sort(list, function(a, b)
    if a.price == b.price then return a.key < b.key end
    return a.price < b.price
  end)
  return list
end

local items = build_item_list()
local total_pages = math.max(1, math.ceil(#items / ITEMS_PER_PAGE))
local current_page = 1
local status_msg = ""

-- ── кеш инвентаря / ME ─────────────────────────────────────────
local function inv_counts()
  local inv = pim.inventory(pim_proxy) or {}
  local m = {}
  for i = 1, #inv do
    local st = inv[i]
    if st then
      local id = st.id or st.raw_name or st.name
      local meta = math.floor(tonumber(st.dmg) or 0)
      local k = (id or "?") .. ":" .. meta
      m[k] = (m[k] or 0) + pim.qty(st)
    end
  end
  return m
end

-- ── UI ─────────────────────────────────────────────────────────
local CELL_W = math.floor((screen_w - 2) / COLS)
local CELL_H = math.floor((screen_h - 6) / ROWS)
local GRID_Y = 4

local clickable = {}

local function add_btn(x1, y1, w, h, action)
  clickable[#clickable + 1] = {
    x1 = x1, y1 = y1, x2 = x1 + w - 1, y2 = y1 + h - 1, action = action,
  }
end

local function find_action(x, y)
  for _, c in ipairs(clickable) do
    if x >= c.x1 and x <= c.x2 and y >= c.y1 and y <= c.y2 then
      return c.action
    end
  end
end

local function trunc(s, n)
  if not s then return "" end
  if unicode.len(s) <= n then return s end
  return unicode.sub(s, 1, n - 1) .. "…"
end

local function render()
  clickable = {}
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, screen_w, screen_h, " ")

  -- header
  gpu.setForeground(0xFFFF80)
  gpu.set(2, 1, "═══ SHOP ═══")
  gpu.setForeground(0xFFFFFF)
  gpu.set(20, 1, string.format("Balance: $%.2f", state.balance))

  gpu.setForeground(0x888888)
  gpu.set(2, 2, string.format("Page %d/%d  (%d items)", current_page, total_pages, #items))

  -- prev/next кнопки
  local btn_y = 2
  gpu.setBackground(0x444444); gpu.setForeground(0xFFFFFF)
  gpu.set(screen_w - 18, btn_y, " < PREV ")
  add_btn(screen_w - 18, btn_y, 8, 1, "prev")
  gpu.set(screen_w - 9, btn_y, " NEXT > ")
  add_btn(screen_w - 9, btn_y, 8, 1, "next")
  gpu.setBackground(0x000000)

  -- статус
  if status_msg ~= "" then
    gpu.setForeground(0x80FF80)
    gpu.set(2, screen_h, trunc(status_msg, screen_w - 4))
  end

  -- сетка
  local inv = inv_counts()
  local me_snap = me_proxy and me_lib.snapshot(me_proxy) or {}

  local start = (current_page - 1) * ITEMS_PER_PAGE + 1
  local stop = math.min(start + ITEMS_PER_PAGE - 1, #items)

  for idx = start, stop do
    local item = items[idx]
    local rel = idx - start
    local col = rel % COLS
    local row = math.floor(rel / COLS)
    local x = 2 + col * CELL_W
    local y = GRID_Y + row * CELL_H

    local have = inv[item.key] or 0
    local stock = me_snap[item.key] or 0

    -- фон ячейки
    if have > 0 then
      gpu.setBackground(0x1F3D1F)   -- есть у игрока — зелёный
    elseif stock > 0 then
      gpu.setBackground(0x1F2D4D)   -- есть в ME — синий
    else
      gpu.setBackground(0x202020)
    end
    gpu.fill(x, y, CELL_W - 1, CELL_H - 1, " ")

    -- имя предмета
    gpu.setForeground(0xFFFFFF)
    gpu.set(x + 1, y, trunc(item.short, CELL_W - 3))

    -- цена
    gpu.setForeground(0xFFFF80)
    gpu.set(x + 1, y + 1, string.format("$%.2f", item.price))

    -- stock
    gpu.setForeground(stock > 0 and 0x88CCFF or 0x444444)
    gpu.set(x + 1, y + 2, "S:" .. stock)

    -- have
    gpu.setForeground(have > 0 and 0x00FF00 or 0x444444)
    gpu.set(x + 1, y + 3, "H:" .. have)

    -- кнопки внизу ячейки
    local btn_yy = y + CELL_H - 2
    gpu.setBackground(0x006600); gpu.setForeground(0xFFFFFF)
    gpu.set(x + 1, btn_yy, " BUY ")
    add_btn(x + 1, btn_yy, 5, 1, { type = "buy", item = item })

    gpu.setBackground(0x660000)
    gpu.set(x + CELL_W - 7, btn_yy, " SELL ")
    add_btn(x + CELL_W - 7, btn_yy, 6, 1, { type = "sell", item = item })

    gpu.setBackground(0x000000)
  end
end

-- ── операции ───────────────────────────────────────────────────
local function buy(item)
  if state.balance < item.price then
    status_msg = "Не хватает баланса: нужно $" ..
                 string.format("%.2f", item.price)
    return
  end
  if not me_proxy then
    status_msg = "Нет ME — покупка невозможна"
    return
  end
  local ok, moved = me_lib.request(me_proxy, item.id, item.meta,
                                   1, STORAGE_SIDE, 1)
  local n = tonumber(moved) or 0
  if ok and n > 0 then
    state.balance = state.balance - item.price * n
    save_state(state)
    status_msg = string.format("BUY %s × %d = -$%.2f",
                               item.short, n, item.price * n)
  else
    status_msg = "Не получилось купить: " .. tostring(moved)
  end
end

local function sell(item)
  local inv = pim.inventory(pim_proxy) or {}
  for i = 1, #inv do
    local st = inv[i]
    if st then
      local id = st.id or st.raw_name or st.name
      local meta = math.floor(tonumber(st.dmg) or 0)
      if id == item.id and meta == item.meta then
        local ok, moved = pim.pull(pim_proxy, STORAGE_SIDE, i, 1)
        local n = tonumber(moved) or 0
        if ok and n > 0 then
          state.balance = state.balance + item.price * n
          save_state(state)
          status_msg = string.format("SELL %s × %d = +$%.2f",
                                     item.short, n, item.price * n)
        else
          status_msg = "Не получилось продать: " .. tostring(moved)
        end
        return
      end
    end
  end
  status_msg = "Нет такого предмета у тебя"
end

-- ── главный цикл ───────────────────────────────────────────────
render()
while true do
  local e, _, x, y = event.pull(2)
  if e == "interrupted" then break end

  if e == "touch" then
    local action = find_action(x, y)
    if action == "prev" then
      current_page = math.max(1, current_page - 1)
      status_msg = ""
    elseif action == "next" then
      current_page = math.min(total_pages, current_page + 1)
      status_msg = ""
    elseif type(action) == "table" then
      if action.type == "buy" then buy(action.item) end
      if action.type == "sell" then sell(action.item) end
    end
    render()
  elseif not e then
    -- timeout — обновим инвентарь/склад
    render()
  end
end

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
term.clear()
print("Shop closed. Balance saved: $" .. string.format("%.2f", state.balance))
