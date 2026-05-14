# CLAUDE.md — рабочее пространство OpenComputers / Lua

Эта директория — для программирования модов **Minecraft OpenComputers** на Lua 5.3. Официальная документация: https://ocdoc.cil.li/. Локально код **НЕ исполняется** (эмулятора нет) — пишем здесь, запускаем в игре в OpenOS.

## Профиль работы

Фокус: GUI/программы для стационарных ПК + сети (modem, internet) + EEPROM/низкий уровень.
**Не предлагать решения на Robot API** (`require("robot")`, `robot.forward()` и т.п.) — это вне скоупа.

## Среда: Lua 5.3 в OpenComputers

**Что есть:** `coroutine`, `string`, `math`, `table`, `debug`, `io`, `os`, `package`/`require`, UTF-8 через `unicode`.

**Чего НЕТ:**
- `collectgarbage` — отсутствует.
- `dofile` / `loadfile` переработаны, работают только с локальной ФС.
- `os.execute` в Unix-смысле нет — есть `shell.execute` (через OpenOS).

**Что специфично:**
- В любом ожидании или бесконечном цикле обязателен **yield**: `event.pull([timeout])`, `os.sleep(t)` или `computer.pullSignal([timeout])`. Без yield Minecraft через ~5 секунд тушит программу как зависшую (signal `too long without yielding`).
- `_OSVERSION` — глобальная переменная с версией OpenOS.
- `checkArg(n, val, "type1", "type2", ...)` — встроенная проверка типов аргументов.

## Доступ к компонентам

Стандартный паттерн в OpenOS:
```lua
local component = require("component")
local gpu = component.gpu                                   -- primary компонент типа "gpu"
local rs  = component.proxy(component.list("redstone")())   -- если нужен конкретный адрес
component.invoke(addr, "method", arg1, arg2)                -- низкоуровневый вызов
```

В EEPROM-скриптах **`require` нет**! Там `component`, `computer`, `unicode` — это **глобалы**.

## Лимиты, которые надо держать в голове

- **RAM**: 256 KB на Tier 1, ~2 MB при максимальной комплектации. Глубокая рекурсия → переполнение стека.
- **EEPROM**: ~4 KB кода (`eeprom.set`) + 256 байт data-поля (`eeprom.getData`/`setData` — для адреса HDD, конфигов и т.п.).
- **Energy**: компьютер потребляет энергию из сети мода; кончилась — выключение.
- **GPU calls/tick**: большие `gpu.fill` / `gpu.copy` могут превысить бюджет на тик. Дробить на куски с `os.sleep(0.05)`.

## Конвенции кода

- **Стороны и цвета**: `require("sides")`, `require("colors")` — не магические числа.
- **UTF-8**: длина — `unicode.len`, подстрока — `unicode.sub`, ширина в ячейках экрана — `unicode.wlen` (CJK/символы занимают 2 клетки).
- **Сериализация** для `modem.send` и хранения конфигов — `require("serialization").serialize(t)` / `unserialize(s)`. Только plain-таблицы; функции/userdata/циклы не работают.
- **Защитные проверки**: `if component.isAvailable("internet") then ...` — потому что итеративный дебаг невозможен, лучше упасть с понятным сообщением заранее.
- **Комментарии в коде**: по-русски, если не оговорено иное.

## Структура проекта

```
programs/   — точки входа для OpenOS (копируются в /home или /bin)
lib/        — модули, доступные через require (копируются в /lib)
eeprom/     — содержимое EEPROM (заливается в чип через eeprom.set)
docs/       — заметки и cheatsheet
```

## Аддоны

В проекте предполагается работа с тремя сторонними модами, добавляющими свои OC-компоненты:

- **OpenSecurity** — `os_*` (keypad, rfid, mag, alarm, doors, data block, turret).
- **Computronics** — `tape_drive`, `chat_box`, `radar`, `camera`, `cipher_block`, `colorful_lamp`, `particle_card`.
- **OpenPeripheral + OpenPeripheral-Addons** — bridge для CC-peripheral'ов через Adapter Block; Terminal Glasses Bridge (HUD в AR-очках), Sensor, Player Inventory Manager.

Локальный конспект по этим аддонам — [docs/oc_addons.md](docs/oc_addons.md). При работе с блоком, которого там нет, проверить методы в игре: `for m in pairs(component.proxy(addr)) do print(m) end`.

## Тестирование

Локального runtime OpenComputers нет. Доступно:
- **Синтаксис**: `luac -p file.lua`
- **Линт**: `luacheck file.lua` (использует `.luacheckrc` в корне с раздельными глобалами для `eeprom/`, `programs/`, `lib/`)
- **Реальная проверка**: ручное копирование файла в игру + запуск

Когда пользователь говорит «проверь работу» — уточнить, какой вариант имелся в виду.

## Полезные ссылки

- Документация: https://ocdoc.cil.li/
- Локальный API-конспект: [docs/oc_cheatsheet.md](docs/oc_cheatsheet.md)
- Базовые API: [api:component](https://ocdoc.cil.li/api:component), [api:event](https://ocdoc.cil.li/api:event), [api:term](https://ocdoc.cil.li/api:term), [api:filesystem](https://ocdoc.cil.li/api:filesystem)
- Перечень железа: [component](https://ocdoc.cil.li/component)
