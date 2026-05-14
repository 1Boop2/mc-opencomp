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
DST = os.path.join(ROOT, "lib", "prices.lua")

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


if __name__ == "__main__":
    sys.exit(main())
