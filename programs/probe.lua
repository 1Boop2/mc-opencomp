-- @version: 2026-05-14.10-banner — probe: component diagnostic
-- @deps: pim
-- Запуск:  pull probe

local component = require("component")
local fs = require("filesystem")

local VERSION = "2026-05-14.10-banner"
print("[probe " .. VERSION .. "]")
print("OS: " .. tostring(_OSVERSION or "(unknown)"))
print()

-- Содержимое установленной библиотеки — чтобы убедиться, что она обновилась
print("=== /lib/pim.lua (первые 600 символов) ===")
if fs.exists("/lib/pim.lua") then
  local f = io.open("/lib/pim.lua", "r")
  if f then
    print(f:read(600) or "(empty)")
    f:close()
  end
else
  print("(файла нет — сделай  pull lib/pim)")
end
print()

print("=== Все компоненты ===")
local candidates = {}
for addr, t in component.list() do
  print(string.format("  %-32s %s", t, addr:sub(1, 8)))
  local lt = t:lower()
  if lt:find("pim") or lt:find("manager") or lt:find("inventory")
     or lt:find("player") then
    candidates[#candidates + 1] = { addr = addr, type = t }
  end
end

if #candidates == 0 then
  print("\n(нет очевидных кандидатов на PIM)")
else
  for _, c in ipairs(candidates) do
    print(string.format("\n=== %s @ %s — методы (component.methods) ===",
                        c.type, c.addr:sub(1, 8)))
    local ok, methods = pcall(component.methods, c.addr)
    if not ok or not methods then
      print("  (component.methods failed: " .. tostring(methods) .. ")")
    else
      local names = {}
      for name in pairs(methods) do names[#names + 1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
        print("  " .. name)
      end
      if #names == 0 then
        print("  (методов нет)")
      end
    end
  end
end

print("\n=== Проверка lib/pim.find() ===")
package.loaded.pim = nil   -- сброс кеша require, чтобы взять свежую версию
local ok, pim = pcall(require, "pim")
if not ok then
  print("require('pim') failed: " .. tostring(pim))
else
  print("pim._VERSION = " .. tostring(pim._VERSION))
  local proxy, addr, ptype = pim.find()
  if proxy then
    print(string.format("OK: тип=%s addr=%s", ptype, addr:sub(1, 8)))
  else
    print("pim.find() вернул nil")
  end
end
