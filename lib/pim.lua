-- lib/pim.lua — обёртка над Player Inventory Manager (OpenPeripheral-Addons).
-- Делает: автопоиск компонента в системе, защитные вызовы, нормализация
-- полей стака (qty/size/count) и имён методов между версиями.

local component = require("component")

local M = {}

-- Известные имена типа компонента PIM в разных версиях OpenPeripheral
local KNOWN_TYPES = {
  "openperipheral_manager",
  "openperipheral_inventory_manager",
  "inventory_manager",
  "manager",
}

-- Если ни одно из имён не совпало — ищем компонент с этими методами.
local SIGNATURE = { "getStackInSlot", "getInventorySize" }

--- Найти PIM-компонент. Возвращает proxy, address, type или nil.
function M.find()
  for _, t in ipairs(KNOWN_TYPES) do
    local addr = component.list(t, true)()  -- exact match
    if addr then
      return component.proxy(addr), addr, t
    end
  end

  for addr, t in component.list() do
    local ok, proxy = pcall(component.proxy, addr)
    if ok and proxy then
      local match = true
      for _, m in ipairs(SIGNATURE) do
        if type(proxy[m]) ~= "function" then
          match = false
          break
        end
      end
      if match then
        return proxy, addr, t
      end
    end
  end

  return nil
end

--- Безопасно получить стак из слота (1-based)
function M.stack(proxy, slot)
  local ok, st = pcall(proxy.getStackInSlot, slot)
  if not ok then return nil end
  return st
end

--- Прочитать весь основной инвентарь. Возвращает массив [1..size], где
--- индекс — номер слота, значение — таблица стака или nil.
function M.inventory(proxy)
  local ok, size = pcall(proxy.getInventorySize)
  if not ok then return nil, "getInventorySize: " .. tostring(size) end
  local result = {}
  for i = 1, size do
    result[i] = M.stack(proxy, i)
  end
  return result, size
end

--- Прочитать броню (обычно 4 слота).
function M.armor(proxy)
  if type(proxy.getArmorInventorySize) ~= "function" then return nil end
  local ok, size = pcall(proxy.getArmorInventorySize)
  if not ok then return nil end
  local fn = proxy.getArmor or proxy.getStackInArmorSlot
  if type(fn) ~= "function" then return nil end
  local result = {}
  for i = 1, size do
    local s_ok, st = pcall(fn, i)
    result[i] = s_ok and st or nil
  end
  return result, size
end

--- Имя игрока, который стоит на PIM. nil — никого.
function M.owner(proxy)
  for _, m in ipairs({ "getOwner", "getName" }) do
    if type(proxy[m]) == "function" then
      local ok, v = pcall(proxy[m])
      if ok and v and v ~= "" then return v end
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
