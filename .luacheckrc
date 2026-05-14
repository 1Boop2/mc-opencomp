-- luacheck config для проекта OpenComputers
-- См. https://luacheck.readthedocs.io/

std = "lua53"
max_line_length = 140

-- Глобалы, встроенные в OpenComputers/OpenOS поверх стандартного Lua 5.3
globals = {
  "checkArg",    -- встроенная проверка типов аргументов
  "_OSVERSION",  -- версия OpenOS
}

-- EEPROM-код запускается без OpenOS — там нет require, и component/computer/unicode
-- доступны как глобалы, которые можно и читать, и переопределять (например, обёртки)
files["eeprom/**/*.lua"] = {
  globals = { "component", "computer", "unicode" },
}

-- В programs/ и lib/ ожидается require("component") и т.п., но мы допускаем чтение
-- этих имён как глобалов на случай OpenOS-стиля без локализации
files["programs/**/*.lua"] = {
  read_globals = { "component", "computer", "unicode" },
}

files["lib/**/*.lua"] = {
  read_globals = { "component", "computer", "unicode" },
}
