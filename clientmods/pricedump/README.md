# PriceDump — клиентский мод 1.7.10 для дампа цен

Клиентский Forge-мод. Команда `/dumpprices` сканирует все предметы в реестре, вытаскивает из их tooltip'ов строки вида `Минимальная цена: N$` и сохраняет в JSON.

## Что собирает

Map `{modid:itemname:meta -> price}`. Пример:

```json
{
  "OpenComputers:item:27": 0.65,
  "minecraft:diamond:0": 0.03,
  "appliedenergistics2:material:47": 1.0
}
```

## Сборка

Требуется **Gradle 8.5+** и **JDK 17** (для запуска gradle). Сам мод компилится в Java 8 байткод — будет работать на JDK 8 внутри игры.

```sh
cd clientmods/pricedump
gradle build
```

Готовый jar — `build/libs/PriceDump-1.0.jar`. Положи его в `mods/` своей сборки 1.7.10 (для MCSkill — `C:\Users\<User>\AppData\Roaming\MCSkill\updates\Industrial_1.7.10\mods\`).

> На первой сборке gradle скачает Forge 1.7.10 и mappings через RetroFuturaGradle (~500 MB в `~/.gradle/`). Это разовая операция.

## Использование

1. Запусти игру с установленным модом, зайди на сервер (важно — tooltip'ы с ценами обычно требуют чтобы игрок был на сервере, потому что мод-tooltip активируется через сервер).
2. В чате: `/dumpprices`
3. Файл `prices.json` появится в корне `.minecraft/` (или там же где `Industrial_1.7.10/`).
4. Можно указать путь: `/dumpprices my/custom/path.json`.

## Импорт в OC

Файл `prices.json` можно положить в репо `1Boop2/mc-opencomp` под `lib/prices.json`. Потом из Lua-программ:

```lua
local internet = require("internet")
local handle = internet.request(
  "https://raw.githubusercontent.com/1Boop2/mc-opencomp/main/lib/prices.json")
local body = ""
for chunk in handle do body = body .. chunk end

-- Lua не имеет встроенного JSON, но можно либо взять lib/json.lua, либо
-- адаптировать prices.json под Lua-таблицу.
```

Удобнее сразу сохранить prices как Lua-файл (`prices.lua`), который возвращает таблицу:

```lua
return {
  ["OpenComputers:item:27"] = 0.65,
  -- ...
}
```

Если нужно — добавлю в этот мод флаг `/dumpprices --lua` для сохранения сразу в Lua-формате.

## Ограничения

- Tooltip собирается только для тех предметов, у которых мод-tooltip успел синхронизироваться с сервером. Зайди в JEI/инвентарь хотя бы раз, чтобы мод-tooltip полностью подгрузился.
- Предметы с под-мета (например, разные DV блоки) разворачиваются через `getSubItems` — должны собираться все варианты.
- Если у предмета цена показывается **только под Shift/Alt** (динамический tooltip), `getTooltip(player, true)` всё равно её получит — флаг `advanced=true` включает все строки.
- Серверы со строгим античитом могут детектировать модификации клиента — используй на свой риск.
