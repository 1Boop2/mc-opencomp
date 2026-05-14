-- @version: 2026-05-14-shop — lib/me: AE2 ME-сеть обёртка
-- Поддерживает разные имена компонентов в разных версиях AE2.

local component = require("component")
local M = {}
M._VERSION = "2026-05-14-shop"

local KNOWN_TYPES = {
  "me_controller",
  "me_interface",
}
local SIGNATURE = { "getItemsInNetwork" }   -- основной маркер AE2-узла

--- Найти ME-компонент. Возвращает proxy, address, type или nil.
function M.find()
  for _, t in ipairs(KNOWN_TYPES) do
    for addr in pairs(component.list(t, true)) do
      local ok, proxy = pcall(component.proxy, addr)
      if ok and proxy then return proxy, addr, t end
    end
  end
  for addr, ctype in pairs(component.list()) do
    local ok, methods = pcall(component.methods, addr)
    if ok and type(methods) == "table" then
      local match = true
      for _, m in ipairs(SIGNATURE) do
        if not methods[m] then match = false; break end
      end
      if match then
        local p_ok, proxy = pcall(component.proxy, addr)
        if p_ok and proxy then return proxy, addr, ctype end
      end
    end
  end
  return nil
end

--- Снять снэпшот всех предметов в сети: map "id:meta" → qty.
--- Один тяжёлый вызов, потом lookup быстрый.
function M.snapshot(proxy)
  local result = {}
  if not proxy then return result end
  local ok, items = pcall(proxy.getItemsInNetwork)
  if not ok or type(items) ~= "table" then return result end
  for _, st in pairs(items) do
    if st then
      local id = st.name or st.id
      local meta = math.floor(tonumber(st.damage or st.dmg) or 0)
      local qty = tonumber(st.size or st.qty or st.count or 0) or 0
      if id then
        local k = id .. ":" .. meta
        result[k] = (result[k] or 0) + qty
      end
    end
  end
  return result
end

--- Запросить count предметов из сети на side+slot (внешний инвентарь).
--- Возвращает (ok, moved_qty | err).
function M.request(proxy, id, meta, count, side, slot)
  if not proxy then return false, "no ME" end
  -- API ME Controller: requestItems(item_table, side, slot)
  if type(proxy.requestItems) == "function" then
    local ok, moved = pcall(proxy.requestItems,
      { name = id, damage = meta, size = count }, side, slot)
    if ok then return true, moved end
  end
  -- Альтернативное API: exportItem
  if type(proxy.exportItem) == "function" then
    local ok, moved = pcall(proxy.exportItem,
      { name = id, damage = meta, size = count }, side, slot)
    if ok then return true, moved end
  end
  return false, "нет requestItems/exportItem"
end

return M
