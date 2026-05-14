-- probe — диагностический дамп: все компоненты, кандидаты на PIM,
-- их методы. Запуск:  pull --update probe && pull probe

local component = require("component")

print("=== Все компоненты ===")
local candidates = {}
for addr, t in component.list() do
  print(string.format("  %-40s %s", t, addr:sub(1, 8)))
  local lt = t:lower()
  if lt:find("pim") or lt:find("manager") or lt:find("inventory")
     or lt:find("player") then
    candidates[#candidates + 1] = { addr = addr, type = t }
  end
end

if #candidates == 0 then
  print("\n(нет очевидных кандидатов на PIM по имени типа)")
else
  print("\n=== Кандидаты на PIM (по подстроке pim/manager/inventory/player) ===")
  for _, c in ipairs(candidates) do
    print(string.format("\n%s @ %s — методы:", c.type, c.addr:sub(1, 8)))
    local ok, proxy = pcall(component.proxy, c.addr)
    if not ok then
      print("  (proxy failed: " .. tostring(proxy) .. ")")
    else
      local methods = {}
      for m, v in pairs(proxy) do
        if type(v) == "function" then methods[#methods + 1] = m end
      end
      table.sort(methods)
      for _, m in ipairs(methods) do
        print("  " .. m)
      end
    end
  end
end

print("\n=== Проверка lib/pim.find() ===")
local ok, pim = pcall(require, "pim")
if not ok then
  print("require('pim') failed: " .. tostring(pim))
else
  local proxy, addr, ptype = pim.find()
  if proxy then
    print(string.format("OK: тип=%s addr=%s", ptype, addr:sub(1, 8)))
  else
    print("pim.find() вернул nil — ни по known_types, ни по сигнатурным методам")
  end
end
