-- Part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.

---------------------------------------------------------------------
-- PERIPHERALS
---------------------------------------------------------------------
-- Find a peripheral on the computer's sides OR anywhere on the wired network.
SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }

function norm(x) return (tostring(x):lower():gsub("[^%a]", "")) end

-- names of attached peripherals of the given types, split into
-- network names (wired modem) and plain sides
function candidates(types)
  local remote, side = {}, {}
  for _, name in ipairs(peripheral.getNames()) do
    for _, t in ipairs(types) do
      local ok, has = pcall(peripheral.hasType, name, t)
      if ok and has then
        if SIDES[name] then side[#side + 1] = name else remote[#remote + 1] = name end
        break
      end
    end
  end
  table.sort(remote)
  table.sort(side)
  return remote, side
end

-- `pinned`: exact network name from CONFIG.names.  Otherwise the first match;
-- network names are preferred over sides (so the block can be moved away from
-- the computer later), unless preferSide is set (the monitor).
function locate(label, pinned, types, required, preferSide)
  if pinned then
    local p = peripheral.wrap(pinned)
    if not p then
      error(label .. " '" .. pinned .. "' (CONFIG.names) is not on the network. " ..
            "Run 'peripherals' to see the names.", 0)
    end
    return p, pinned
  end

  local remote, side = candidates(types)
  local first, second = remote, side
  if preferSide then first, second = side, remote end
  local list = (#first > 0) and first or second
  if #list > 0 then
    if #list > 1 then
      print(label .. ": " .. #list .. " found (" .. table.concat(list, ", ") ..
            "), using " .. list[1] .. ". Pin the one you want in CONFIG.names.")
    end
    local p = peripheral.wrap(list[1])
    if p then return p, list[1] end
  end

  -- fuzzy fallback: ignore case, underscores and prefixes
  -- ("advancedperipherals:player_detector" still matches "player_detector")
  local want = {}
  for _, t in ipairs(types) do want[#want + 1] = norm(t) end
  for _, name in ipairs(peripheral.getNames()) do
    local cands = { name, peripheral.getType(name) }
    for _, c in ipairs(cands) do
      if type(c) == "string" then
        local nc = norm(c)
        for _, w in ipairs(want) do
          if nc:find(w, 1, true) then
            local p = peripheral.wrap(name)
            if p then
              print(label .. ": using '" .. name .. "' (type " ..
                    tostring(peripheral.getType(name)) .. ")")
              return p, name
            end
          end
        end
      end
    end
  end

  if required then
    error("No " .. label .. " found. Put it next to the computer, or connect it with " ..
          "a Wired Modem + Networking Cable (and right-click the modems).", 0)
  end
end

IM_TYPES = { "inventory_manager", "inventoryManager" }
PD_TYPES = { "player_detector", "playerDetector" }
ED_TYPES = { "environment_detector", "environmentDetector" }
CB_TYPES = { "chat_box", "chatBox" }
BR_TYPES = { "me_bridge", "meBridge", "rs_bridge", "rsBridge" }
DR_TYPES = { "drone_interface", "droneInterface" }
local scanDrones, forgetDrone      -- defined in the DRONE section (several drones)

picked = {}   -- which network name each peripheral was found under

inv, mon, det, envDet, bridge, bridgeKind = nil
inv, picked.inv = locate("Inventory Manager", CONFIG.names.inventoryManager, IM_TYPES, true)
mon, picked.mon = locate("monitor", CONFIG.names.monitor, { "monitor" }, true, true)

if not mon.isColor() then error("This needs an Advanced (gold) Monitor for colours.", 0) end

-- optional peripherals
det, picked.det = locate("Player Detector", CONFIG.names.playerDetector, PD_TYPES)
envDet, picked.env = locate("Environment Detector", CONFIG.names.environmentDetector, ED_TYPES)
chatBox = nil
chatBox, picked.chat = locate("Chat Box", nil, CB_TYPES)

invCaps = {}
function updateCaps()
  if inv then
    invCaps.storage = inv.wrapStorageItem ~= nil
    invCaps.curios = inv.listCurios ~= nil
  end
end
updateCaps()

function kindOf(name)
  local ty = tostring(peripheral.getType(name) or name):lower()
  return ty:find("rs", 1, true) == 1 and "RS" or "ME"
end
do
  local b, n = locate("ME/RS Bridge", CONFIG.names.meBridge, BR_TYPES)
  if b then bridge, picked.bridge, bridgeKind = b, n, kindOf(n) end
end

-- Everything the computer can see (sides + wired network), as "name (type)"
function netSummary()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    local ty = peripheral.getType(n)
    out[#out + 1] = n .. (ty and (" (" .. ty .. ")") or "")
  end
  table.sort(out)
  return out
end

-- Why can't I see my wired peripherals?  One line per modem.
function diagLines()
  local lines, modems = {}, 0
  for _, name in ipairs(peripheral.getNames()) do
    local okT, isModem = pcall(peripheral.hasType, name, "modem")
    if okT and isModem and SIDES[name] then
      modems = modems + 1
      local okW, wireless = pcall(peripheral.call, name, "isWireless")
      if okW and wireless then
        lines[#lines + 1] = name .. ": this is a WIRELESS modem. It cannot connect " ..
                            "peripherals - use a WIRED modem."
      else
        local okR, remote = pcall(peripheral.call, name, "getNamesRemote")
        local list = (okR and type(remote) == "table") and remote or {}
        if #list == 0 then
          lines[#lines + 1] = name .. ": wired modem, but NO peripherals on its network. " ..
            "Right-click the modem on each far block (it must show as connected) " ..
            "and check that every cable touches a modem."
        else
          table.sort(list)
          lines[#lines + 1] = name .. ": wired modem, " .. #list ..
                              " peripheral(s) on its network: " .. table.concat(list, ", ")
        end
      end
    end
  end
  if modems == 0 then
    lines[#lines + 1] = "No modem next to the computer. Put a WIRED modem on the computer " ..
                        "and connect it with Networking Cable."
  end
  return lines
end

print("Using: manager=" .. tostring(picked.inv) .. "  monitor=" .. tostring(picked.mon) ..
      "  detector=" .. tostring(picked.det) .. "  bridge=" .. tostring(picked.bridge))
do
  local sum = netSummary()
  print("Peripherals seen: " .. (#sum > 0 and table.concat(sum, ", ") or "none"))
end

-- Help text for a missing optional device (cached, it is shown on screen)
netInfo = { t = -100, lines = {} }
function deviceHelpLines(label)
  if os.clock() - netInfo.t > 3 then
    local lines = diagLines()
    local sum = netSummary()
    lines[#lines + 1] = "The computer sees: " .. (#sum > 0 and table.concat(sum, ", ") or "nothing")
    netInfo.lines, netInfo.t = lines, os.clock()
  end
  local out = { "No " .. label .. " found. Connect it with a Wired Modem and cable, " ..
                "or place it next to the computer." }
  for _, l in ipairs(netInfo.lines) do out[#out + 1] = l end
  return out
end

-- Look again for peripherals that were not there at start-up
-- (modem activated later, block moved, cable connected later, ...).
function tryLocate(...)
  local ok, p, n = pcall(locate, ...)
  if ok then return p, n end
end

function rescanPeripherals()
  if not inv then
    inv, picked.inv = tryLocate("Inventory Manager", CONFIG.names.inventoryManager, IM_TYPES)
    updateCaps()
  end
  if not det then
    det, picked.det = tryLocate("Player Detector", CONFIG.names.playerDetector, PD_TYPES)
  end
  if not chatBox then
    chatBox, picked.chat = tryLocate("Chat Box", nil, CB_TYPES)
  end
  if not envDet then
    envDet, picked.env = tryLocate("Environment Detector", CONFIG.names.environmentDetector, ED_TYPES)
  end
  if scanDrones then scanDrones() end
  if not bridge then
    local b, n = tryLocate("ME/RS Bridge", CONFIG.names.meBridge, BR_TYPES)
    if b then bridge, picked.bridge, bridgeKind = b, n, kindOf(n) end
  end
  netInfo.t = -100
end

-- forget a peripheral that was unplugged / moved
function forgetDetached(name)
  if picked.inv == name then inv, picked.inv = nil, nil end
  if picked.det == name then det, picked.det = nil, nil end
  if picked.env == name then envDet, picked.env = nil, nil end
  if picked.chat == name then chatBox, picked.chat = nil, nil end
  if forgetDrone then forgetDrone(name) end
  if picked.bridge == name then bridge, bridgeKind, picked.bridge = nil, nil, nil end
  netInfo.t = -100
end

monName = peripheral.getName(mon)
mon.setTextScale(CONFIG.textScale)

