-- @version: 2026-05-14-aetest — aetest: пощупать AE+PIM руками
-- @deps: pim, me
--
-- Usage:
--   pull aetest                              — общий статус
--   pull aetest methods                      — список методов me_controller / me_interface
--   pull aetest stock <id:meta>              — getItemsInNetwork для предмета
--   pull aetest pulls <slot> [qty]           — попробовать pim.pullItem на все 6 сторон
--   pull aetest pushs <slot> [qty]           — попробовать pim.pushItem на все 6 сторон
--   pull aetest buy <id:meta> <side> [slot] [qty]
--      — попробовать requestItems/exportItem на ВСЕ доступные ME-компоненты

local component = require("component")
local sides = require("sides")
local serialization = require("serialization")

package.loaded.pim = nil
package.loaded.me = nil
local pim = require("pim")
local me_lib = require("me")

local pim_proxy, pim_addr = pim.find()
if not pim_proxy then io.stderr:write("PIM не найден\n"); return 1 end
local me_r = me_lib.find_all()

local function p(...) print(...) end
local function dump(label, value)
  p("--- " .. label .. " ---")
  if type(value) == "table" then
    print(serialization.serialize(value, true))
  else
    print(tostring(value))
  end
end

local args = {...}
local cmd = args[1]

p(string.format("PIM @ %s | controller %s | interface %s",
  pim_addr:sub(1,8),
  me_r.controller_addr and me_r.controller_addr:sub(1,8) or "—",
  me_r.interface_addr and me_r.interface_addr:sub(1,8) or "—"))

if not cmd then
  p("Use: methods | stock <id:meta> | pulls <slot> [qty] | pushs <slot> [qty] | buy <id:meta> <side> [slot] [qty]")
  return 0
end

-- ── methods ───────────────────────────────────────────────────
if cmd == "methods" then
  for label, addr in pairs({
    controller = me_r.controller_addr,
    interface  = me_r.interface_addr,
  }) do
    if addr then
      p("\n=== " .. label .. " methods ===")
      local ok, methods = pcall(component.methods, addr)
      if ok and type(methods) == "table" then
        local names = {}
        for n in pairs(methods) do names[#names+1] = n end
        table.sort(names)
        for _, n in ipairs(names) do p("  " .. n) end
      end
    end
  end
  return 0
end

-- ── stock ─────────────────────────────────────────────────────
if cmd == "stock" then
  local key = args[2]
  if not key then p("Usage: aetest stock <id:meta>"); return 1 end
  local lc = key:match(".*():")
  local id, meta = key:sub(1, lc-1), tonumber(key:sub(lc+1)) or 0
  for label, proxy in pairs({controller = me_r.controller, interface = me_r.interface}) do
    if proxy and type(proxy.getItemsInNetwork) == "function" then
      p("\n=== getItemsInNetwork via " .. label .. " ===")
      local ok, items = pcall(proxy.getItemsInNetwork, {name=id, damage=meta})
      if ok then dump("result", items) else p("err: " .. tostring(items)) end
    end
  end
  return 0
end

-- ── pulls (sell) — пробуем все стороны ─────────────────────────
if cmd == "pulls" then
  local slot = tonumber(args[2]) or 1
  local qty = tonumber(args[3]) or 1
  local st = pim.stack(pim_proxy, slot)
  p(string.format("slot %d: %s × %d", slot, pim.name(st), pim.qty(st)))
  for _, side_name in ipairs({"bottom","top","north","south","east","west"}) do
    local side = sides[side_name]
    local ok, moved = pim.pull(pim_proxy, side, slot, qty)
    p(string.format("  %-6s (%d): ok=%s moved=%s",
      side_name, side, tostring(ok), tostring(moved)))
  end
  return 0
end

-- ── pushs ─────────────────────────────────────────────────────
if cmd == "pushs" then
  local slot = tonumber(args[2]) or 1
  local qty = tonumber(args[3]) or 1
  for _, side_name in ipairs({"bottom","top","north","south","east","west"}) do
    local side = sides[side_name]
    local ok, moved = pim.push(pim_proxy, side, slot, qty)
    p(string.format("  %-6s (%d): ok=%s moved=%s",
      side_name, side, tostring(ok), tostring(moved)))
  end
  return 0
end

-- ── buy: пробуем все методы и proxy ──────────────────────────
if cmd == "buy" then
  local key, side_name = args[2], args[3]
  local slot = tonumber(args[4]) or 1
  local qty = tonumber(args[5]) or 1
  if not key or not side_name then
    p("Usage: aetest buy <id:meta> <side> [slot] [qty]"); return 1
  end
  local lc = key:match(".*():")
  local id, meta = key:sub(1, lc-1), tonumber(key:sub(lc+1)) or 0
  local side = sides[side_name]
  if side == nil then p("Bad side"); return 1 end

  for label, proxy in pairs({interface = me_r.interface, controller = me_r.controller}) do
    if proxy then
      p("\n=== via " .. label .. " ===")
      for _, m in ipairs({"requestItems", "exportItem"}) do
        if type(proxy[m]) == "function" then
          p(string.format("%s({name=%s, damage=%d, size=%d}, %s/%d, %d)",
            m, id, meta, qty, side_name, side, slot))
          local ok, moved = pcall(proxy[m],
            {name=id, damage=meta, size=qty}, side, slot)
          p(string.format("  ok=%s moved=%s", tostring(ok), tostring(moved)))
        else
          p("  " .. m .. ": нет метода")
        end
      end
    end
  end
  return 0
end

p("Unknown command")
return 1
