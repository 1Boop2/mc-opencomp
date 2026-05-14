-- @version: 2026-05-14-shop2 — shop: магазин с touch UI + фильтры/сортировки
-- @deps: pim, prices, me, display_names
-- Usage: pull shop
--
-- Требования:
--  - T2+ компьютер, экран T2+ с touch
--  - PIM рядом с компом
--  - (опционально) AE2 ME компонент — для склада
--    Если нет — продажа идёт в STORAGE_SIDE (сундук рядом).
--
-- Управление:
--  - Левый клик BUY/SELL → продать/купить qty штук
--  - Правый клик BUY/SELL → продать/купить 64 (стак)
--  - Кнопки [+1] [+10] [+64] [-1] [R] — управление qty
--  - Sort: [name][$↑][$↓]   Mod: [all][mod1]…   < PREV > NEXT
--  - Ctrl+Alt+C — выход

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
package.loaded.display_names = nil
local pim = require("pim")
local prices = require("prices")
local me_lib = require("me")
local names = nil
do
  local ok, n = pcall(require, "display_names")
  if ok then names = n end
end

local VERSION = "2026-05-14-shop2"
print(string.format("[shop %s | pim %s | prices %s | me %s | names %s]",
  VERSION, pim._VERSION or "?", prices._VERSION or "?",
  me_lib._VERSION or "?", names and "ok" or "none"))

-- ── конфиг ─────────────────────────────────────────────────────
local STATE_FILE = "/home/.shop_state.dat"
local STORAGE_SIDE = sides.east
local COLS, ROWS = 4, 5
local ITEMS_PER_PAGE = COLS * ROWS
local STARTING_BALANCE = 100.0

-- ── компоненты ─────────────────────────────────────────────────
local pim_proxy, pim_addr = pim.find()
if not pim_proxy then
  io.stderr:write("PIM не найден\n"); return 1
end
local me_proxy, me_addr = me_lib.find()

local gpu = component.gpu
local screen_w, screen_h = gpu.getResolution()
if screen_w < 80 or screen_h < 25 then
  io.stderr:write("Нужен экран T2+ (минимум 80x25)\n"); return 1
end

-- ── состояние ──────────────────────────────────────────────────
local function load_state()
  if not fs.exists(STATE_FILE) then return { balance = STARTING_BALANCE } end
  local f = io.open(STATE_FILE, "r")
  if not f then return { balance = STARTING_BALANCE } end
  local content = f:read("*a"); f:close()
  local ok, st = pcall(serialization.unserialize, content)
  if not ok or type(st) ~= "table" then return { balance = STARTING_BALANCE } end
  return st
end
local function save_state(st)
  local f = io.open(STATE_FILE, "w")
  if f then f:write(serialization.serialize(st)); f:close() end
end
local state = load_state()

-- ── каталог предметов ──────────────────────────────────────────
local function display_of(item)
  if names and names[item.key] then return names[item.key] end
  return item.id:match(":([^:]+)$") or item.id
end

local all_items = {}
do
  for key, price in pairs(prices.table) do
    local last_colon = key:match(".*():")
    if last_colon then
      local meta = tonumber(key:sub(last_colon + 1)) or 0
      local id = key:sub(1, last_colon - 1)
      local modid = id:match("^([^:]+)") or id
      all_items[#all_items + 1] = {
        key = key, id = id, meta = meta, price = price, mod = modid,
      }
    end
  end
end

-- Топ модов по числу предметов
local mod_counts = {}
for _, it in ipairs(all_items) do
  mod_counts[it.mod] = (mod_counts[it.mod] or 0) + 1
end
local top_mods = {}
for m in pairs(mod_counts) do top_mods[#top_mods + 1] = m end
table.sort(top_mods, function(a, b) return mod_counts[a] > mod_counts[b] end)
while #top_mods > 8 do top_mods[#top_mods] = nil end

-- ── фильтр + сортировка ────────────────────────────────────────
local sort_mode = "price_asc"   -- "name" | "price_asc" | "price_desc"
local mod_filter = "all"
local current_page = 1
local qty_select = 1
local status_msg = ""
local visible = {}
local total_pages = 1

local function rebuild_visible()
  visible = {}
  for _, it in ipairs(all_items) do
    if mod_filter == "all" or it.mod == mod_filter then
      visible[#visible + 1] = it
    end
  end
  if sort_mode == "name" then
    table.sort(visible, function(a, b) return display_of(a) < display_of(b) end)
  elseif sort_mode == "price_asc" then
    table.sort(visible, function(a, b)
      if a.price == b.price then return a.key < b.key end
      return a.price < b.price
    end)
  else
    table.sort(visible, function(a, b)
      if a.price == b.price then return a.key < b.key end
      return a.price > b.price
    end)
  end
  total_pages = math.max(1, math.ceil(#visible / ITEMS_PER_PAGE))
  if current_page > total_pages then current_page = total_pages end
end
rebuild_visible()

-- ── текущий инвентарь ──────────────────────────────────────────
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
local CELL_H = math.floor((screen_h - 7) / ROWS)
local GRID_Y = 5

local clickable = {}
local function add_btn(x, y, w, h, action)
  clickable[#clickable + 1] = {
    x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, action = action }
end
local function find_action(x, y)
  for _, c in ipairs(clickable) do
    if x >= c.x1 and x <= c.x2 and y >= c.y1 and y <= c.y2 then return c.action end
  end
end

local function trunc(s, n)
  if not s then return "" end
  if unicode.len(s) <= n then return s end
  return unicode.sub(s, 1, n - 1) .. "…"
end

local function btn(x, y, label, action, active)
  local bg, fg = 0x444444, 0xFFFFFF
  if active then bg, fg = 0xAA8800, 0x000000 end
  gpu.setBackground(bg); gpu.setForeground(fg)
  gpu.set(x, y, label)
  add_btn(x, y, unicode.len(label), 1, action)
  return x + unicode.len(label) + 1
end

local function render()
  clickable = {}
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, screen_w, screen_h, " ")

  -- ROW 1: title | balance | qty controls
  gpu.setForeground(0xFFFF80); gpu.set(2, 1, "═══ SHOP ═══")
  gpu.setForeground(0xFFFFFF)
  gpu.set(16, 1, string.format("Balance: $%.2f", state.balance))

  local qx = 42
  gpu.setForeground(0xFFFFFF)
  gpu.set(qx, 1, "qty=" .. qty_select); qx = qx + 6 + #tostring(qty_select)
  qx = btn(qx, 1, " +1 ",  { type = "qty_d", n = 1 })
  qx = btn(qx, 1, " +10 ", { type = "qty_d", n = 10 })
  qx = btn(qx, 1, " +64 ", { type = "qty_d", n = 64 })
  qx = btn(qx, 1, " -1 ",  { type = "qty_d", n = -1 })
  qx = btn(qx, 1, " R ",   { type = "qty_reset" })

  -- ROW 2: page | sort | nav
  gpu.setBackground(0x000000); gpu.setForeground(0x888888)
  gpu.set(2, 2, string.format("Page %d/%d  (%d items)",
                              current_page, total_pages, #visible))
  local sx = 24
  gpu.setForeground(0xFFFFFF); gpu.set(sx, 2, "Sort:"); sx = sx + 6
  sx = btn(sx, 2, "name", { type = "sort", v = "name" }, sort_mode == "name")
  sx = btn(sx, 2, "$↑",   { type = "sort", v = "price_asc"  }, sort_mode == "price_asc")
  sx = btn(sx, 2, "$↓",   { type = "sort", v = "price_desc" }, sort_mode == "price_desc")

  -- nav buttons на правом краю
  local nx = screen_w - 19
  nx = btn(nx, 2, " < PREV ", "prev")
  nx = btn(nx, 2, " NEXT > ", "next")

  -- ROW 3: mod filter
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF); gpu.set(2, 3, "Mod:")
  local mx = 7
  mx = btn(mx, 3, "all", { type = "mod", v = "all" }, mod_filter == "all")
  for _, mod in ipairs(top_mods) do
    if mx + #mod + 2 > screen_w - 2 then break end
    mx = btn(mx, 3, mod, { type = "mod", v = mod }, mod_filter == mod)
  end

  -- ── grid ──
  local inv = inv_counts()
  local me_snap = me_proxy and me_lib.snapshot(me_proxy) or {}

  local start = (current_page - 1) * ITEMS_PER_PAGE + 1
  local stop = math.min(start + ITEMS_PER_PAGE - 1, #visible)
  for idx = start, stop do
    local item = visible[idx]
    local rel = idx - start
    local col = rel % COLS
    local row = math.floor(rel / COLS)
    local x = 2 + col * CELL_W
    local y = GRID_Y + row * CELL_H

    local have = inv[item.key] or 0
    local stock = me_snap[item.key] or 0

    if have > 0 then gpu.setBackground(0x1F3D1F)
    elseif stock > 0 then gpu.setBackground(0x1F2D4D)
    else gpu.setBackground(0x202020) end
    gpu.fill(x, y, CELL_W - 1, CELL_H - 1, " ")

    gpu.setForeground(0xFFFFFF)
    gpu.set(x + 1, y, trunc(display_of(item), CELL_W - 3))

    gpu.setForeground(0xFFFF80)
    gpu.set(x + 1, y + 1, string.format("$%.2f", item.price))

    gpu.setForeground(stock > 0 and 0x88CCFF or 0x444444)
    gpu.set(x + 1, y + 2, "S:" .. stock)
    gpu.setForeground(have > 0 and 0x00FF00 or 0x444444)
    gpu.set(x + 1, y + 3, "H:" .. have)

    -- BUY / SELL
    local byy = y + CELL_H - 2
    gpu.setBackground(0x006600); gpu.setForeground(0xFFFFFF)
    gpu.set(x + 1, byy, " BUY ")
    add_btn(x + 1, byy, 5, 1, { type = "buy", item = item })
    gpu.setBackground(0x660000)
    gpu.set(x + CELL_W - 7, byy, " SELL ")
    add_btn(x + CELL_W - 7, byy, 6, 1, { type = "sell", item = item })

    gpu.setBackground(0x000000)
  end

  -- status row
  if status_msg ~= "" then
    gpu.setForeground(0x80FF80)
    gpu.set(2, screen_h, trunc(status_msg, screen_w - 4))
  end
end

-- ── операции ───────────────────────────────────────────────────
local function buy(item, n)
  n = n or qty_select
  local cost = item.price * n
  if state.balance < cost then
    status_msg = string.format("Не хватает $%.2f (нужно $%.2f)",
                               cost - state.balance, cost)
    return
  end
  if not me_proxy then
    status_msg = "Нет ME — покупка невозможна"; return
  end
  local ok, moved = me_lib.request(me_proxy, item.id, item.meta,
                                   n, STORAGE_SIDE, 1)
  local m = tonumber(moved) or 0
  if ok and m > 0 then
    state.balance = state.balance - item.price * m
    save_state(state)
    status_msg = string.format("BUY %s × %d = -$%.2f",
                               display_of(item), m, item.price * m)
  else
    status_msg = "Покупка не удалась: " .. tostring(moved)
  end
end

local function sell(item, n)
  n = n or qty_select
  local left = n
  local inv = pim.inventory(pim_proxy) or {}
  local sold = 0
  for i = 1, #inv do
    if left <= 0 then break end
    local st = inv[i]
    if st then
      local id = st.id or st.raw_name or st.name
      local meta = math.floor(tonumber(st.dmg) or 0)
      if id == item.id and meta == item.meta then
        local q = math.min(pim.qty(st), left)
        local ok, moved = pim.pull(pim_proxy, STORAGE_SIDE, i, q)
        local m = tonumber(moved) or 0
        if ok and m > 0 then
          sold = sold + m
          left = left - m
        else
          break
        end
      end
    end
  end
  if sold > 0 then
    state.balance = state.balance + item.price * sold
    save_state(state)
    status_msg = string.format("SELL %s × %d = +$%.2f",
                               display_of(item), sold, item.price * sold)
  else
    status_msg = "Нет в инвентаре"
  end
end

-- ── главный цикл ───────────────────────────────────────────────
render()
while true do
  local e, _, x, y, button = event.pull(2)
  if e == "interrupted" then break end

  if e == "touch" then
    local action = find_action(x, y)
    local right_click = (button == 1)
    if action == "prev" then
      current_page = math.max(1, current_page - 1); status_msg = ""
    elseif action == "next" then
      current_page = math.min(total_pages, current_page + 1); status_msg = ""
    elseif type(action) == "table" then
      if action.type == "buy" then
        buy(action.item, right_click and 64 or nil)
      elseif action.type == "sell" then
        sell(action.item, right_click and 64 or nil)
      elseif action.type == "qty_d" then
        qty_select = math.max(1, qty_select + action.n)
      elseif action.type == "qty_reset" then
        qty_select = 1
      elseif action.type == "sort" then
        sort_mode = action.v; rebuild_visible(); current_page = 1
        status_msg = ""
      elseif action.type == "mod" then
        mod_filter = action.v; rebuild_visible(); current_page = 1
        status_msg = ""
      end
    end
    render()
  elseif not e then
    render()
  end
end

gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
term.clear()
print("Shop closed. Balance: $" .. string.format("%.2f", state.balance))
