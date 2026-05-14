-- @version: 2026-05-14-shop2 — lib/me: AE2 ME-сеть (controller + interface)
-- Использует и me_controller (для snapshot всей сети), и me_interface
-- (для физической выдачи на сторону) — берёт что есть.

local component = require("component")
local M = {}
M._VERSION = "2026-05-14-shop2"

--- Найти оба компонента сразу. Возвращает таблицу:
---   { controller = proxy|nil, controller_addr = addr,
---     interface  = proxy|nil, interface_addr  = addr,
---     primary    = proxy }  -- что нашлось (controller предпочтительнее)
function M.find_all()
  local r = {}
  for addr, ctype in pairs(component.list()) do
    if ctype == "me_controller" and not r.controller then
      local ok, p = pcall(component.proxy, addr)
      if ok and p then r.controller, r.controller_addr = p, addr end
    elseif ctype == "me_interface" and not r.interface then
      local ok, p = pcall(component.proxy, addr)
      if ok and p then r.interface, r.interface_addr = p, addr end
    end
  end
  -- Fallback: компонент с getItemsInNetwork
  if not r.controller and not r.interface then
    for addr, ctype in pairs(component.list()) do
      local ok, methods = pcall(component.methods, addr)
      if ok and type(methods) == "table" and methods.getItemsInNetwork then
        local pp_ok, p = pcall(component.proxy, addr)
        if pp_ok and p then
          r.controller, r.controller_addr = p, addr
          break
        end
      end
    end
  end
  r.primary = r.controller or r.interface
  return r
end

--- Совместимость с прошлой версией — возвращает primary.
function M.find()
  local r = M.find_all()
  if r.primary then
    local addr = r.controller_addr or r.interface_addr
    return r.primary, addr, r.controller and "me_controller" or "me_interface"
  end
end

--- Снэпшот всей сети: map "id:meta" → qty.
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

--- Запросить count предметов на side+slot.
--- В этой версии AE2 правильный метод — interface.exportItem(filter, side, slot).
--- Filter: {name=, damage=} (size игнорируется в exportItem — count приходит
--- 4-м аргументом или внутрь size — пробуем оба варианта).
function M.request(r_or_proxy, id, meta, count, side, slot)
  local interface
  if type(r_or_proxy) == "table" and r_or_proxy.primary then
    interface = r_or_proxy.interface
  else
    interface = r_or_proxy
  end
  if not interface or type(interface.exportItem) ~= "function" then
    return false, "нет exportItem (нужен me_interface)"
  end

  local filter = { name = id, damage = meta, size = count }
  -- Пробуем сначала с size в фильтре (как в большинстве версий AE2 API)
  local ok, moved = pcall(interface.exportItem, filter, side, slot)
  if ok and tonumber(moved) and tonumber(moved) > 0 then
    return true, moved
  end
  -- Fallback: count вторым аргументом
  local ok2, moved2 = pcall(interface.exportItem, filter, count, side, slot)
  if ok2 and tonumber(moved2) and tonumber(moved2) > 0 then
    return true, moved2
  end
  return false, "exportItem moved=0 (нет в сети или плохая сторона)"
end

return M
