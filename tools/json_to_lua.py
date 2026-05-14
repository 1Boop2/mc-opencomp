#!/usr/bin/env python3
"""Конвертирует prices.json (корень репо) → lib/prices.lua с поиском по стаку.

Запуск:  python3 tools/json_to_lua.py
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "prices.json")
COMPUTED = os.path.join(ROOT, "computed_prices.json")
NAMES = os.path.join(ROOT, "display_names.json")
DST = os.path.join(ROOT, "lib", "prices.lua")
DST_NAMES = os.path.join(ROOT, "lib", "display_names.lua")

VERSION = "2026-05-14-generated"


def main():
    data = {}
    # computed подгружаем первым, prices.json (tooltip) перезаписывает —
    # tooltip имеет приоритет над расчётом
    if os.path.exists(COMPUTED):
        with open(COMPUTED, encoding="utf-8") as f:
            data.update(json.load(f))
    with open(SRC, encoding="utf-8") as f:
        data.update(json.load(f))
    # Округляем floating-point шум от Java суммирования (0.1+0.1+0.1=0.30000…)
    # до 3 знаков — это покрывает точность tooltip-цен (минимум 0.005).
    data = {k: round(v, 3) for k, v in data.items() if v is not None and v > 0}

    lines = [
        f"-- @version: {VERSION} — lib/prices: статичная таблица цен",
        f"-- Сгенерировано из prices.json. Перегенерация: python3 tools/json_to_lua.py",
        "",
        "local M = {}",
        f"M._VERSION = \"{VERSION}\"",
        "",
        "M.table = {",
    ]
    for k, v in sorted(data.items()):
        k_esc = k.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'  ["{k_esc}"] = {v},')
    lines += [
        "}",
        "",
        "--- Ищет цену для стака от PIM (поля id/name и dmg).",
        "--- Возвращает число или nil если не найдено.",
        "function M.for_stack(stack)",
        "  if not stack then return nil end",
        "  local id = stack.id or stack.raw_name or stack.name",
        "  if not id then return nil end",
        "  local meta = math.floor(tonumber(stack.dmg) or 0)",
        "  return M.table[id .. \":\" .. meta]",
        "end",
        "",
        "--- Размер таблицы (для статистики).",
        "function M.count()",
        "  local n = 0",
        "  for _ in pairs(M.table) do n = n + 1 end",
        "  return n",
        "end",
        "",
        "return M",
        "",
    ]

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(f"wrote {DST} ({len(data)} prices)")

    # display_names — отдельный файл lib/display_names.lua
    if os.path.exists(NAMES):
        with open(NAMES, encoding="utf-8") as f:
            names = json.load(f)
        name_lines = [
            f"-- @version: {VERSION} — lib/display_names: id:meta → читаемое имя",
            "-- Сгенерировано из display_names.json.",
            "",
            "return {",
        ]
        for k, v in sorted(names.items()):
            k_esc = k.replace('\\', '\\\\').replace('"', '\\"')
            v_esc = v.replace('\\', '\\\\').replace('"', '\\"')
            name_lines.append(f'  ["{k_esc}"] = "{v_esc}",')
        name_lines += ["}", ""]
        with open(DST_NAMES, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(name_lines))
        print(f"wrote {DST_NAMES} ({len(names)} names)")


if __name__ == "__main__":
    sys.exit(main())
