-- Простая программа для smoke-теста загрузчика pull.
-- Запуск:  pull _example аргумент1 аргумент2

local computer = require("computer")
local args = {...}

print("hello from github!")
print("uptime:    " .. tostring(computer.uptime()) .. " sec")
print("free RAM:  " .. tostring(computer.freeMemory()) .. " B")
print("аргументы: " .. (#args > 0 and table.concat(args, ", ") or "(нет)"))
