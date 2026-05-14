# OpenComputers / Lua cheatsheet

Локальная выжимка под профиль: **GUI/ПК + сети + EEPROM**. Полная документация — https://ocdoc.cil.li/.

## Обязательные минимумы

- **Lua 5.3**, нет `collectgarbage`, нет нормального `os.execute`.
- В любом ожидающем цикле — `event.pull(timeout)` или `os.sleep(t)`. Иначе `too long without yielding` через ~5 сек.
- `checkArg(n, val, "type1", "type2", ...)` — проверка типов в начале функции.
- Адреса компонентов — UUID-строки; можно сокращать до уникального префикса в `component.get`.

---

## component (`require("component")`)

```lua
local component = require("component")

component.list([filter, exact])      -- итератор addr → type
component.proxy(addr)                -- таблица с методами компонента
component.invoke(addr, method, ...)  -- прямой вызов
component.methods(addr)              -- что умеет компонент
component.doc(addr, method)          -- docstring метода
component.type(addr)                 -- "gpu", "modem", ...
component.isAvailable(type)          -- есть ли primary этого типа
component.getPrimary(type)
component.setPrimary(type, addr)
component.gpu                        -- сахар = getPrimary("gpu")
```

Связанные события: `component_added (addr, type)`, `component_removed (addr, type)`, `component_available (type)`, `component_unavailable (type)`.

---

## computer

```lua
computer.address()         -- UUID этого компьютера
computer.tmpAddress()      -- UUID /tmp ФС
computer.freeMemory()      -- байты
computer.totalMemory()     -- байты
computer.energy()          -- текущая энергия
computer.maxEnergy()       -- максимум
computer.uptime()          -- секунд с загрузки
computer.users()           -- авторизованные игроки
computer.beep([freq], [duration])
computer.shutdown([reboot])
computer.pullSignal([timeout])  -- низкоуровневое получение события
computer.pushSignal(name, ...)
computer.getDeviceInfo()
```

---

## event (`require("event")`)

```lua
local event = require("event")

event.pull([timeout], [filter, ...])  -- блокирует, возвращает name, ...args
event.listen(name, callback)          -- callback(name, ...) → если вернёт false, снимется
event.ignore(name, callback)
event.timer(interval, callback, [times])  -- times = math.huge для вечного
event.cancel(timerId)
event.push(name, ...)                 -- = computer.pushSignal
```

**Типичные события:**

| Событие | Аргументы (после имени) |
|---------|-------------------------|
| `key_down` | screen_addr, char (Unicode), code (LWJGL), player |
| `key_up` | screen_addr, char, code, player |
| `clipboard` | screen_addr, value, player |
| `touch` | screen_addr, x, y, button, player |
| `drag` | screen_addr, x, y, button, player |
| `drop` | screen_addr, x, y, button, player |
| `scroll` | screen_addr, x, y, direction (+1/-1), player |
| `modem_message` | local_addr, remote_addr, port, distance, ...data |
| `redstone_changed` | addr, side, old_value, new_value |
| `component_added` / `component_removed` | addr, type |
| `interrupted` | uptime (Ctrl+Alt+C) |

`event.pull(1)` → ждать 1 с, `nil` по таймауту. `event.pull(5, "modem_message")` — фильтр.

---

## GPU (`component.gpu`)

```lua
local gpu = component.gpu

gpu.bind(screen_addr, [reset])
gpu.getScreen()
gpu.maxResolution()
gpu.getResolution() / setResolution(w, h)
gpu.maxDepth() / getDepth() / setDepth(bits)  -- 1 / 4 / 8
gpu.getForeground() / setForeground(rgb, [isPaletteIndex])
gpu.getBackground() / setBackground(rgb, [isPaletteIndex])
gpu.getPaletteColor(idx) / setPaletteColor(idx, rgb)
gpu.set(x, y, text, [vertical])
gpu.fill(x, y, w, h, char)
gpu.copy(x, y, w, h, dx, dy)
gpu.get(x, y)  -- → char, fg, bg, fgPaletteIndex, bgPaletteIndex
```

**Тиры:**

| Tier | Max res | Depth | Цвета |
|------|---------|-------|-------|
| 1 | 50×16 | 1 | моно |
| 2 | 80×25 | 4 | 16 |
| 3 | 160×50 | 8 | 256 |

---

## term (`require("term")`)

```lua
local term = require("term")

term.write(s, [wrap])
term.clear() / term.clearLine()
term.getCursor() / term.setCursor(x, y)
term.getViewport()                              -- w, h, dx, dy, cx, cy
term.gpu()                                       -- GPU-прокси
term.read([history], [dobreak], [hint], [pwchar])  -- интерактивный ввод
term.pull(...)                                   -- = event.pull
term.isAvailable()                               -- есть ли GPU + screen
```

---

## keyboard (`require("keyboard")`)

```lua
keyboard.isControlDown() / isShiftDown() / isAltDown()
keyboard.isKeyDown(code)
keyboard.keys                                    -- таблица: keys.enter, keys.space, keys.q, ...
```

В `key_down`: `char` — Unicode-код (например `97` = 'a'); `code` — LWJGL keycode (раскладочно-зависим).

---

## modem (`component.modem`)

```lua
local modem = component.modem

modem.isWireless()
modem.maxPacketSize()
modem.open(port)                                 -- порт 1..65535
modem.close([port])
modem.isOpen(port)
modem.send(target_addr, port, ...)
modem.broadcast(port, ...)
modem.setStrength(n) / getStrength()             -- беспроводная дальность (только wireless)
```

Приём — через `modem_message (local_addr, remote_addr, port, distance, ...data)`.
Слать можно только примитивы и plain-таблицы. Сложное → `serialization.serialize` сначала.

---

## internet (`component.internet`)

```lua
local inet = component.internet

inet.isHttpEnabled()
inet.isTcpEnabled()

local handle = inet.request(url, [body], [headers], [method])
-- handle.read([n])             → строка | nil (EOF)
-- handle.finishConnect()       → true когда заголовки получены
-- handle.response()            → code, message, headers
-- handle.close()

local sock = inet.connect(host, [port])
-- sock.read / sock.write / sock.close / sock.finishConnect
```

Только outgoing. Серверов нельзя.

---

## serialization (`require("serialization")`)

```lua
local ser = require("serialization")

local s = ser.serialize(t, [multiline])
local t = ser.unserialize(s)
```

Только plain Lua (без функций, userdata, thread, циклов в графе таблиц).

---

## filesystem (`require("filesystem")`)

```lua
local fs = require("filesystem")

fs.exists(path)
fs.isDirectory(path)
fs.size(path)
fs.list(path)                                    -- итератор имён (директории с '/')
fs.makeDirectory(path)
fs.remove(path)
fs.rename(old, new)
fs.copy(from, to)
fs.concat(a, b, ...)                             -- склейка путей
fs.path(p) / fs.name(p)                          -- dirname / basename
fs.canonical(p)
fs.get(path)                                     -- → proxy, mountPath
fs.mount(proxyOrAddr, path)
fs.umount(pathOrProxy)
fs.mounts()                                      -- итератор

local f = fs.open(path, [mode])                  -- "r" / "rb" / "w" / "wb" / "a" / "ab"
-- f:read(format), f:write(s), f:close(), f:seek(whence, offset)
```

Для текстовых форматов удобнее `io.open(path, mode)` — даёт line-итераторы.

---

## unicode (`require("unicode")`)

```lua
unicode.char(...)                  -- codepoints → строка
unicode.len(s)                      -- число codepoints
unicode.sub(s, i, [j])
unicode.upper(s) / lower(s)
unicode.reverse(s)
unicode.charWidth(c)                -- 1 или 2 ячейки экрана
unicode.wlen(s)                     -- сумма ширин
unicode.wtrunc(s, n)                -- обрезать до ширины n
unicode.isWide(c)                   -- занимает ли 2 ячейки
```

Стандартный `string.len/sub` работает с байтами, не codepoints. Для UTF-8 — всегда `unicode.*`.

---

## sides (`require("sides")`)

```
sides.bottom = 0  (down)
sides.top    = 1  (up)
sides.back   = 2  (north)
sides.front  = 3  (south)
sides.right  = 4  (west)
sides.left   = 5  (east)
```

`sides[n]` → имя.

---

## colors (`require("colors"))`

```
colors.white = 0, orange, magenta, lightblue, yellow, lime, pink,
gray, lightgray, cyan, purple, blue, brown, green, red, black = 15
```

`colors[n]` → имя. `colors.combine(...)` для битмасок (например для color cable).

---

## EEPROM (`component.eeprom`)

В EEPROM-коде `require` НЕТ. `component`, `computer`, `unicode` — глобалы.

```lua
local eeprom = component.proxy(component.list("eeprom")())

eeprom.get()                       -- читать код прошивки
eeprom.set(code)                   -- записать (≤ ~4 KB)
eeprom.getLabel() / setLabel(s)
eeprom.getData()                   -- ≤ 256 байт постоянных данных (адрес HDD и т.п.)
eeprom.setData(s)
eeprom.getSize() / getDataSize()
eeprom.getChecksum()
eeprom.makeReadonly(checksum)      -- запечатать (нужен текущий checksum)
```

### Минимальный шаблон загрузчика OpenOS

```lua
-- Поиск загрузочного HDD и запуск /init.lua
local eeprom = component.proxy(component.list("eeprom")())
local boot = eeprom.getData()

if boot == "" or not component.list("filesystem")[boot] then
  for addr in component.list("filesystem") do
    if component.invoke(addr, "exists", "/init.lua") then
      boot = addr
      eeprom.setData(addr)
      break
    end
  end
end

local handle = component.invoke(boot, "open", "/init.lua")
local code = ""
repeat
  local chunk = component.invoke(boot, "read", handle, math.huge)
  code = code .. (chunk or "")
until not chunk
component.invoke(boot, "close", handle)

local fn, err = load(code, "=init")
if not fn then error(err) end
fn()
```

---

## Что обычно идёт не так

1. **`too long without yielding`** — в цикле забыли `os.sleep(0)` или `event.pull(0.05)`. Везде в long-running кодах нужен yield.
2. **`out of memory`** — слишком много в RAM. Стриминговое чтение, не грузить файлы целиком.
3. **`modem.send` «не доходит»** — забыли `modem.open(port)` на приёмнике; или беспроводной `setStrength(0)`; или receiver не слушает `modem_message`.
4. **GPU операция падает на большом `fill`/`copy`** — превышен бюджет на тик. Дробить циклом с `os.sleep(0.05)`.
5. **EEPROM не запускается** — синтаксическая ошибка в прошивке → boot loop. Спасение: вынуть HDD/прошить EEPROM через дисковод/программатор, либо `component.list("eeprom")` с другого компьютера.
6. **`unicode.sub` vs `string.sub`** — для русского/CJK всегда `unicode`, иначе разрежет символ пополам.
7. **`serialization.unserialize` падает** — данные содержали функцию или цикл; перед отправкой по modem проверять структуру.
8. **`gpu.set` не пишет** — забыли `gpu.bind(screen_addr)`. Без screen GPU молчит.
