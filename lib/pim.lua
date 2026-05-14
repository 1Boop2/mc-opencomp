-- lib/pim.lua — обёртка над Player Inventory Manager (OpenPeripheral-Addons).
-- Делает: автопоиск компонента, защитные вызовы, нормализация полей стака
-- (qty/size/count) и имён методов между версиями. Версии PIM сильно различаются:
-- одни выставляют getOwner/getArmor, другие — только базовый инвентарь.

local component = require("component")

local M = {}
M._VERSION = "2026-05-14.5-pairs-methods"

-- Известные имена типа компонента PIM в разных версиях OpenPeripheral.
-- "pim" — короткое имя, которое видно через команду `components` в OpenOS.
local KNOWN_TYPES = {
  "pim",
  "openperipheral_manager",
  "openperipheral_inventory_manager",
  "openperipheral_inventoryManager",
  "inventory_manager",
  "manager",
}

-- Если ни одно из имён не совпало — ищем компонент с этими методами.
local SIGNATURE = { "getStackInSlot", "getInventorySize" }

--- Найти PIM-компонент. Возвращает proxy, address, type или nil.
function M.find()
  -- 1) Поиск по точному имени типа. Итерация через pairs — надёжнее, чем
  --    вызов component.list(t, true)() как функции (в некоторых версиях OC
  --    __call возвращает не то, что ожидаешь).
  for _, t in ipairs(KNOWN_TYPES) do
    for addr in pairs(component.list(t, true)) do
      local ok, proxy = pcall(component.proxy, addr)
      if ok and proxy then return proxy, addr, t end
    end
  end

  -- 2) Fallback: по сигнатурным методам.
  --    type(proxy[m]) не работает для прокси с metatable (метод там за __index
  --    и pairs/type не всегда видят его). Используем component.methods(addr)
  --    — это даёт надёжный список именно тех методов, которые компонент
  --    реально выставляет.
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

--- Размер основного инвентаря.
function M.size(proxy)
  local ok, n = pcall(proxy.getInventorySize)
  if not ok or type(n) ~= "number" then return nil end
  return n
end

--- Безопасно получить стак из слота (1-based).
function M.stack(proxy, slot)
  local ok, st = pcall(proxy.getStackInSlot, slot)
  if not ok then return nil end
  return st
end

--- Прочитать весь основной инвентарь.
--- Если есть getAllStacks — один вызов вместо 36; иначе fallback к поштучным.
function M.inventory(proxy)
  if type(proxy.getAllStacks) == "function" then
    local ok, all = pcall(proxy.getAllStacks)
    if ok and type(all) == "table" then
      local size = M.size(proxy) or #all
      local result = {}
      for i = 1, size do result[i] = all[i] end
      return result, size
    end
  end
  local size = M.size(proxy)
  if not size then return nil, "нет getInventorySize" end
  local result = {}
  for i = 1, size do result[i] = M.stack(proxy, i) end
  return result, size
end

--- Прочитать броню — если версия PIM её поддерживает. nil иначе.
function M.armor(proxy)
  if type(proxy.getArmorInventorySize) ~= "function" then return nil end
  local ok, size = pcall(proxy.getArmorInventorySize)
  if not ok or type(size) ~= "number" then return nil end
  local fn = proxy.getArmor or proxy.getStackInArmorSlot
  if type(fn) ~= "function" then return nil end
  local result = {}
  for i = 1, size do
    local s_ok, st = pcall(fn, i)
    result[i] = s_ok and st or nil
  end
  return result, size
end

--- Имя игрока на PIM, или nil.
--- В некоторых версиях нет API для имени — fallback к эвристике через
--- getAllStacks: если возвращает непустой массив, считаем что игрок стоит.
function M.owner(proxy)
  for _, m in ipairs({ "getOwner", "getName", "getPlayerName" }) do
    if type(proxy[m]) == "function" then
      local ok, v = pcall(proxy[m])
      if ok and v and v ~= "" then return v end
    end
  end
  -- Эвристика
  if type(proxy.getAllStacks) == "function" then
    local ok, all = pcall(proxy.getAllStacks)
    if ok and type(all) == "table" and next(all) then
      return "(player on PIM)"
    end
  end
  return nil
end

--- Количество в стаке — терпит разные имена полей между версиями.
function M.qty(stack)
  if not stack then return 0 end
  return stack.qty or stack.size or stack.count or stack.amount or 0
end

--- Лучшее имя стака из доступных полей.
function M.name(stack)
  if not stack then return "" end
  return stack.displayName or stack.label or stack.name or stack.id or "?"
end

--- Переместить из слота PIM наружу со стороны side.
--- Возвращает (ok:bool, moved:int | err:string).
function M.pull(proxy, side, slot, qty, into_slot)
  local fn = proxy.pullItem or proxy.pullItemIntoSlot
  if type(fn) ~= "function" then return false, "нет pullItem" end
  return pcall(fn, side, slot, qty, into_slot)
end

--- Положить в слот PIM из внешнего инвентаря со стороны side.
function M.push(proxy, side, slot, qty, into_slot)
  local fn = proxy.pushItem or proxy.pushItemIntoSlot
  if type(fn) ~= "function" then return false, "нет pushItem" end
  return pcall(fn, side, slot, qty, into_slot)
end

return M
