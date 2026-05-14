# OpenComputers — аддоны

Карта по сторонним модам, которые добавляют свои компоненты в `component.list`. Полные API — на вики каждого мода (ссылки внизу секций).

---

## OpenSecurity

Контроль доступа и безопасность. Поддерживается на MC 1.12.2 (старые версии — deprecated).

### Компоненты

| Тип | Блок | Назначение |
|-----|------|------------|
| `os_rfidreader` | RFID Reader | Сканирование RFID-карт в радиусе |
| `os_magreader` | Magnetic Card Reader | Чтение магнитных карт |
| `os_biometric` | Biometric Reader | **stub, не работает** |
| `os_keypad` | Keypad | 12-кнопочная клавиатура с дисплеем |
| `os_cardwriter` | Card Writer | Запись карт + flash EEPROM |
| `os_doorcontroller` | Door Controller | Управление Security Door с паролем |
| `os_rolldoor` | Rolldoor Controller | Раздвижные двери до 16 блоков |
| `os_alarm` | Alarm | Сирена (`klaxon1` / `klaxon2`) |
| `os_entitydetector` | Entity Detector | Сканирование игроков/мобов |
| `os_energyturret` | Energy Turret | Турель (yaw/pitch/fire) |
| `os_datablock` | Data Block | Крипто: SHA256/MD5/CRC32/base64/deflate/ROT13 |
| `os_displaypanel` | Display Panel | **в разработке, заглушка** |
| `os_securityterminal` | Security Terminal | Центральная консоль |

### Ключевые методы

**Keypad** (`os_keypad`):
```lua
kp.setEventName(name)                  -- по умолчанию "keypad"
kp.setDisplay(text, [color])           -- до 8 символов, color 0-7
kp.setKey(id, [text], [color])         -- id 0-11; 10='*', 11='#'
kp.setVolume(v)                         -- 0.0..1.0
-- событие "keypad" (addr, button_id:int, button_label:string)
```

**RFID Reader / Mag Reader:**
```lua
rfid.scan([range])                     -- стоит 5*range энергии; → {data, uuid, locked}
mag.setEventName(name)                  -- по умолчанию "magData"
-- события: "rfidData" / "magData" (addr, data, uuid, locked)
```

**Door Controller:**
```lua
dc.setPassword(pwd) / removePassword(pwd)
dc.toggle() / open() / close()
dc.isOpen()  -- без аутентификации
```

**Alarm:**
```lua
a.setAlarm("klaxon1")                  -- или "klaxon2"
a.setRange(0..15)                       -- блоков
a.activate() / deactivate()
a.listSounds()
```

**Entity Detector:**
```lua
ed.scanPlayers([range])                -- 5*range энергии
ed.scanEntities([range])
-- событие "entityDetect" (addr, name_or_type)
```

**Card Writer:**
```lua
cw.write(data, [name], [locked], [color])  -- макс 128 символов
cw.flash(code, title, locked)              -- записать EEPROM (auto-trim по лимиту)
```

**Energy Turret:**
```lua
t.moveTo(yaw, pitch)                   -- yaw 0..360, pitch -45..+90
t.fire()                                -- требует isReady() и isPowered()
t.powerOn() / powerOff() / setArmed(bool)
t.isOnTarget() / isReady() / isPowered()
t.extendShaft(0..2)
```

**Data Block:**
```lua
d.encode64(s) / decode64(s)
d.deflate(s) / inflate(s)               -- zlib
d.sha256(s) / md5(s) / crc32(s)         -- binary output
d.rot13(s)
d.getLimit()                            -- макс байт на операцию
```

### Грабли

- Многие методы потребляют энергию OC-сети (особенно `scan*` — `5 × range`). Без питания вернут ошибку.
- Door Controller синхронизирует пароль со всеми смежными Security Door с одним владельцем.
- Card Writer урезает код для EEPROM автоматически — следить за размером.

### Ссылки

- Wiki: https://github.com/PC-Logix/OpenSecurity/wiki
- Полный API (`@Callback`-методы): `src/main/java/pcl/opensecurity/tileentity/TileEntity*.java`

---

## Computronics

Звук, камеры, мосты к индустриальным модам (Railcraft, IC2 и т.п.). MC 1.7.10, OpenComputers ≥ 1.5.9.21.

### Известные компоненты

| Тип | Блок | Назначение |
|-----|------|------------|
| `tape_drive` | Tape Drive | DFPWM-магнитофон (play/seek/write) |
| `chat_box` | Chat Box | Чат-сообщения в игре + redstone-pulse при приёме |
| `radar` | Radar | Сканирование сущностей |
| `camera` | Camera | Снимок 8-bit-картинки экрана |
| `cipher_block` | Cipher Block | Криптография (детали в wiki) |
| `colorful_lamp` | Colorful Lamp | Программируемая RGB-лампа |
| `lamp_block` | Lamp Block | Простая лампа |
| `particle_card` | Particle Card | Карта-апгрейд для частиц |

### Tape Drive

- Формат: **DFPWM** (моно, дифференциальная PCM).
- Конвертер из MP3/WAV в DFPWM: **LionRay** (отдельная Java-утилита от Vexatos) или Audacity-плагин.
- В OpenOS есть встроенная программа `tape`: `tape play`, `tape stop`, `tape pause`, `tape write <file>`.
- API publishes интерфейс `ITapeStorage` (можно делать свои совместимые кассеты).
- Управление через компонент: `play`, `stop`, `pause`, `seek(pos)`, `getLabel`, `setLabel`, `setSpeed` — точные сигнатуры на странице tape wiki.

### Chat Box

```lua
chat.say(text, [distance])              -- distance — радиус слышимости в блоках
-- При приёме сообщения: 4-тиковый redstone pulse + событие
```

### Ссылки

- Главная wiki: https://wiki.vexatos.com/wiki:computronics
- Tape: https://wiki.vexatos.com/wiki:computronics:tape
- Chat Box: https://wiki.vexatos.com/wiki:computronics:chat_box
- Radar: https://wiki.vexatos.com/wiki:computronics:radar
- Camera: https://wiki.vexatos.com/wiki:computronics:camera
- Cipher Block: https://wiki.vexatos.com/wiki:computronics:cipher_block
- Colorful Lamp: https://wiki.vexatos.com/wiki:computronics:colorful_lamp
- Particle Card: https://wiki.vexatos.com/wiki:computronics:particle_card

---

## OpenPeripheral / OpenPeripheral-Addons

**OpenPeripheral Core** — bridge framework: оборачивает peripheral'ы из других модов и делает их доступными как компоненты OC через **Adapter Block** (нужно поставить адаптер вплотную к целевому блоку). Изначально написан для ComputerCraft, OC-поддержка через тот же интерфейс.

**OpenPeripheral-Addons** — пакет собственных блоков, доступных как OC-компоненты.

### Главный кейс: Terminal Glasses Bridge

Рисует HUD-оверлей в AR-очках игрока. У каждого игрока — приватная surface; плюс одна общая (global).

**Концепция API:**
```lua
local bridge = component.openperipheral_bridge   -- точное имя может варьироваться по версии

bridge.getGuid()                                  -- guid этой пары bridge↔glasses
bridge.getUsers()                                 -- список ников игроков с привязанными glasses
local surf = bridge.getSurfaceByName(playerName)  -- private surface; без аргумента — global

-- Любой add* возвращает handle, через который можно менять объект:
local box = surf.addBox(x, y, w, h, color_hex, alpha)
box.setColor(0xFF0000)
box.setAlpha(0.5)
box.delete()

local txt = surf.addText(x, y, "Hello", 0xFFFFFF)
txt.setText("New text")
txt.setPosition(50, 50)

-- ВАЖНО: рисование не появится у игрока, пока не вызовешь sync.
bridge.sync()
```

### Player Inventory Manager (PIM)

Блок-плита. Игрок встаёт сверху → компонент даёт компьютеру доступ к его инвентарю, броне, hotbar. Игрок сходит → методы возвращают ошибки/пустоту.

**Не путать с Player Manipulator** — это отдельный блок, работает удалённо через перчатку Manipulator. PIM пассивный, без перчатки.

**Типовое API** (точные имена сверять в игре через `for m in pairs(component.proxy(addr)) do print(m) end`):
```lua
local pim = component.openperipheral_manager   -- имя зависит от версии

-- Основной инвентарь (обычно 36 слотов)
pim.getInventoryName()                     -- "container.player.inventory"
pim.getInventorySize()                     -- 36
pim.getStackInSlot(slot)                   -- → {id, name, displayName, qty, dmg, maxSize} | nil
pim.getAllStacks()                          -- итератор

-- Броня (4 слота: boots/leggings/chestplate/helmet)
pim.getArmorInventoryName()
pim.getArmorInventorySize()                 -- 4
pim.getArmor(slot)                          -- таблица | nil

-- Перемещение (направление — sides.*)
pim.pullItem(direction, slot, [qty], [intoSlot])   -- забрать НАРУЖУ
pim.pushItem(direction, slot, [qty], [intoSlot])   -- положить ВНУТРЬ

-- Кто стоит сверху
pim.getOwner()                              -- ник | nil
-- (UUID-методы зависят от версии)
```

**События** (зависят от версии): обычно есть сигнал при входе/выходе игрока, имя вроде `player_on` / `player_off` / `pim_*` — точное имя смотреть в игре.

**Грабли:**
- Когда игрок сходит — методы перестают работать. Защита: оборачивать в `pcall` или сразу проверять `getOwner()`.
- `direction` для `pullItem`/`pushItem` — сторона, куда смотрит соседний инвентарь (chest/контейнер). Использовать `require("sides")`.
- Размер стака в результирующей таблице — `qty`, а не `count` (хотя в новых версиях может быть и `size`/`count`).

#### PIM ↔ сундук / AE2 / другие хранилища

PIM сам по себе **не знает** про AE2-сеть. Он работает только с **физическими** инвентарями, которые стоят с одной из 6 сторон PIM-блока. `direction` в `pullItem`/`pushItem` — это та самая сторона.

**Сундук рядом:** поставь Chest (или Double Chest) вплотную к PIM, например с востока.
```lua
local sides = require("sides")
-- из PIM[slot 10] → сундук на востоке
pim.pullItem(sides.east, 10)
-- из сундука → PIM[slot 10]
pim.pushItem(sides.east, 10)
```

**AE2 ME-сеть:** поставь блок **ME Interface** вплотную к PIM. У ME Interface есть 9 буферных слотов, через которые сеть автоматически принимает (если что-то лежит в буфере, оно засасывается в сеть) и выдаёт (если настроены пресеты — буфер заполняется автоматически нужными предметами). С точки зрения PIM этот буфер — обычный инвентарь:
```lua
-- PIM[slot 10] → ME-сеть через ME Interface буфер
pim.pullItem(sides.east, 10)
-- Если на ME Interface настроен пресет «64 железа», после потребления
-- буфер сам пополнится из сети — следующий push возьмёт из готовых 64.
pim.pushItem(sides.east, 10)
```

**Прямой контроль над AE2** (например «дай мне 64 железа из сети сейчас»): нужен компонент `me_controller` или `me_interface`. Он появляется, если соответствующий блок AE2 подключён к компьютеру через **Adapter Block** OpenComputers или просто стоит рядом.
```lua
local me = component.me_controller
-- что есть в сети
local items = me.getItemsInNetwork({ name = "minecraft:iron_ingot" })
-- → таблица стаков с qty в сети
-- заказать 64 железа на сторону east, в слот 1 этого внешнего инвентаря
me.requestItems({ name = "minecraft:iron_ingot", count = 64 }, sides.east, 1)
```

Точные имена методов и сигнатуры зависят от версии AE2 — сверять через `component.methods(addr)` и `component.doc(addr, method)` в игре.

**Другие модовые хранилища** (Refined Storage, IronChests, AE drives и т.п.) — большинство выставляются как inventory-провайдеры и работают со стороны PIM как обычные сундуки. Если мод не выставляет inventory интерфейс — нужен Adapter Block и работа через специфичный API мода.

### Другие блоки OpenPeripheral-Addons

- **Sensor** — сканирование сущностей (`getPlayers`, `getMobIds`, `getPlayerByName`, `getPlayerByUUID`).
- **Player Manipulator** — удалённое управление игроком через перчатку Manipulator (НЕ PIM!).
- **Selector** — слот для предметов с программируемой логикой.
- **Ticket Machine** — Railcraft-интеграция.

Точные API каждого — в `src/main/java/openperipheral/addons/<имя>/` либо в wiki репо.

### Грабли

- Имена компонентов и сигнатуры **зависят от версии OpenPeripheral**. Между 1.x и 2.x могут отличаться (см. changelog).
- Без `bridge.sync()` графика не появится у клиента.
- Каждый `add*` возвращает свой handle — теряя ссылку, теряешь возможность изменить или удалить объект (накапливается).
- В разных модпаках бывает баг с привязкой glasses к bridge — переподключать через right-click.

### Ссылки

- Repo: https://github.com/OpenMods/OpenPeripheral-Addons
- Glasses Bridge source: https://github.com/OpenMods/OpenPeripheral-Addons/blob/master/src/main/java/openperipheral/addons/glasses/TileEntityGlassesBridge.java
- Changelog: https://openmods.info/changelog-openperipheraladdons.html
- Wiki репо: https://github.com/OpenMods/OpenPeripheral-Addons/wiki

---

## Универсальный совет

Если в задаче упомянут блок аддона, которого здесь нет — два пути за нужным API:

1. **Изнутри игры**: на работающем компьютере OC выполнить
   ```lua
   local component = require("component")
   local addr = component.list("<type>")()           -- найти первый компонент типа
   for m in pairs(component.proxy(addr)) do print(m) end
   print(component.doc(addr, "<method>"))             -- docstring
   ```
2. **Из исходников**: искать `@Callback` в Java-коде мода (TileEntity*-классы).
