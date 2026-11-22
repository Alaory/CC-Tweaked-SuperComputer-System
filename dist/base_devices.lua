

















function writeSafe(path, text)
local tmp = path .. ".tmp"
local h = fs.open(tmp, "w")
if not h then return false, "cannot write " .. tmp end
local ok, err = pcall(function() h.write(text) h.close() end)
if not ok or not fs.exists(tmp) or fs.getSize(tmp) < #text then
pcall(h.close)
pcall(fs.delete, tmp)
return false, "not saved: " .. tostring(ok and "disk full" or err)
end
local okM, errM = pcall(function()
if fs.exists(path) then fs.delete(path) end
fs.move(tmp, path)
end)
if not okM then return false, tostring(errM) end
return true
end

function readSafe(path)
for _, p in ipairs({ path, path .. ".tmp" }) do
if fs.exists(p) then
local h = fs.open(p, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if t ~= nil then return t end
end
end
return nil
end

SETTINGS_FILE = "settings.dat"
SETTINGS = {}
CONFIG_ORIGINAL = {}
function setConfigPath(path, value)
local t = CONFIG
local parts = {}
for p in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = p end
for i = 1, #parts - 1 do
if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
t = t[parts[i]]
end
t[parts[#parts]] = value
end
function getConfigPath(path)
local t = CONFIG
for p in tostring(path):gmatch("[^%.]+") do
if type(t) ~= "table" then return nil end
t = t[p]
end
return t
end
do
local t = readSafe(SETTINGS_FILE)
if type(t) == "table" then SETTINGS = t end


for path, v in pairs(SETTINGS) do
local cur = type(path) == "string" and path:find("%.") and getConfigPath(path)
local tv = type(v)
local tc = type(cur)
if type(path) ~= "string" or not path:find("^[%w_]+%.[%w_.]+$")
or (tv ~= "number" and tv ~= "string" and tv ~= "boolean" and tv ~= "table")
or (tc == "table" and tv ~= "table")
or (tv == "table" and cur ~= nil and cur ~= false and tc ~= "table")
or (tc == "number" and tv == "string") then
SETTINGS[path] = nil
else
CONFIG_ORIGINAL[path] = cur
pcall(setConfigPath, path, v)
end
end
end
local function saveSettings()
writeSafe(SETTINGS_FILE, textutils.serialize(SETTINGS))
end

function setSetting(path, value)
if SETTINGS[path] == nil and CONFIG_ORIGINAL[path] == nil then CONFIG_ORIGINAL[path] = getConfigPath(path) end
setConfigPath(path, value)
SETTINGS[path] = value
saveSettings()
end

function resetSetting(path)
if SETTINGS[path] == nil then return end
setConfigPath(path, CONFIG_ORIGINAL[path])
SETTINGS[path] = nil
saveSettings()
end
function isChanged(path) return SETTINGS[path] ~= nil end





SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }


function norm(x) return (tostring(x):lower():gsub("[^%a]", "")) end



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




function locate(label, pinned, types, required, preferSide)
if pinned then
local p = peripheral.wrap(pinned)
if not p then


if required then
error(label .. " '" .. pinned .. "' (CONFIG.names) is not on the network. " ..
"Run 'peripherals' to see the names.", 0)
end
print(label .. " '" .. pinned .. "' is not there yet - looked for again every 20 s")
return nil
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
local scanDrones, forgetDrone

picked = {}














NET_FILE = "net_seen.dat"
NET = { p = {}, f = {} }
DATA_AWAY = {}
NET_START_MISSING = {}
local function startCfg(k, d)
local c = CONFIG.startup
if type(c) == "table" and c[k] ~= nil then return c[k] end
return d
end
do
local okR, t = pcall(readSafe, NET_FILE)
if okR and type(t) == "table" then
for n, e in pairs(type(t.p) == "table" and t.p or {}) do
if type(n) == "string" and type(e) == "table" and tonumber(e.at) then NET.p[n] = { t = tostring(e.t or "?"), at = tonumber(e.at) } end
end
for id, e in pairs(type(t.f) == "table" and t.f or {}) do
if tonumber(id) and type(e) == "table" and tonumber(e.at) then
local files = {}
for _, f in ipairs(type(e.files) == "table" and e.files or {}) do if type(f) == "string" then files[#files + 1] = f end end
NET.f[tonumber(id)] = { at = tonumber(e.at), drive = tostring(e.drive or "?"), files = files }
end
end
end
end
local function nowE() return (os.epoch and os.epoch("utc")) or 0 end

function floppyHere(id)
if not disk then return nil end
for _, n in ipairs(peripheral.getNames()) do
local okT, isDrive = pcall(peripheral.hasType, n, "drive")
if okT and isDrive then
local okP, there = pcall(disk.isPresent, n)
local okI, did = pcall(disk.getID or function() end, n)
if okP and there and okI and did == id then return n end
end
end
return nil
end

function netMissing()
local out = {}
local since = nowE() - (tonumber(startCfg("rememberDays", 3)) or 3) * 86400000
local names = {}
for n in pairs(NET.p) do names[#names + 1] = n end
table.sort(names)
for _, n in ipairs(names) do
local e = NET.p[n]
if e.at >= since and not peripheral.isPresent(n) then out[#out + 1] = { kind = "block", name = n, what = e.t } end
end
for id, e in pairs(NET.f) do
if e.at >= since and #e.files > 0 and not floppyHere(id) then
out[#out + 1] = { kind = "floppy", name = "floppy #" .. id, id = id, what = "data floppy (" .. e.drive .. "): " ..
table.concat(e.files, ", ", 1, math.min(4, #e.files)) .. (#e.files > 4 and " ..." or "") }
end
end
return out
end

function noteNetwork(force)
local now = nowE()
local changed = false
for _, n in ipairs(peripheral.getNames()) do
local okT, ty = pcall(peripheral.getType, n)
local e = NET.p[n]
if not e then changed = true end
NET.p[n] = { t = tostring(okT and ty or "?"), at = now }
local okD, isDrive = pcall(peripheral.hasType, n, "drive")
if disk and okD and isDrive then
local okP, there = pcall(disk.isPresent, n)
local okM, mount = pcall(disk.getMountPath, n)
local okI, id = pcall(disk.getID or function() end, n)
if okP and there and okM and mount and okI and id and fs.exists(fs.combine(mount, "base_data")) then
local files = {}
for _, f in ipairs(fs.list(mount)) do
if (f:find("%.dat$") or f:find("%.log$")) and not fs.isDir(fs.combine(mount, f)) then files[#files + 1] = f end
end
table.sort(files)
local old = NET.f[id]
if not old or table.concat(old.files, ",") ~= table.concat(files, ",") then changed = true end
NET.f[id] = { at = now, drive = n, files = files }
end
end
end
local since = now - (tonumber(startCfg("rememberDays", 3)) or 3) * 86400000
for n, e in pairs(NET.p) do if e.at < since then NET.p[n] = nil changed = true end end
for id, e in pairs(NET.f) do if e.at < since then NET.f[id] = nil changed = true end end
if changed or force or not NET.savedAt or os.clock() - NET.savedAt > 600 then
NET.savedAt = os.clock()
pcall(writeSafe, NET_FILE, textutils.serialize({ p = NET.p, f = NET.f }))
end
end




function dedupeDataFiles()
if not (fs.attributes and disk) then return 0 end
local places = { "" }
for _, n in ipairs(peripheral.getNames()) do
local okD, isDrive = pcall(peripheral.hasType, n, "drive")
if okD and isDrive then
local okP, there = pcall(disk.isPresent, n)
local okM, mount = pcall(disk.getMountPath, n)
if okP and there and okM and mount and fs.exists(fs.combine(mount, "base_data")) then places[#places + 1] = mount end
end
end
local names = {}
for _, e in pairs(NET.f) do for _, f in ipairs(e.files) do names[f] = true end end
local removed = 0
for name in pairs(names) do
local copies = {}
for _, pl in ipairs(places) do
local p = pl == "" and name or fs.combine(pl, name)
if fs.exists(p) and not fs.isDir(p) then
local okA, a = pcall(fs.attributes, p)
local m = okA and type(a) == "table" and tonumber(a.modified or a.modification)
if not m then copies = nil break end
copies[#copies + 1] = { p = p, m = m }
end
end
if copies and #copies > 1 then
table.sort(copies, function(a, b) return a.m > b.m end)
for i = 2, #copies do
if pcall(fs.delete, copies[i].p) then
removed = removed + 1
if sysLog then pcall(sysLog, "Data file " .. name .. ": an OLDER copy on " .. copies[i].p .. " was removed " ..
"(its floppy came back after the base saved it on " .. copies[1].p .. ")", "INFO") end
end
end
end
end
return removed
end

function dataAway(path)
local id = DATA_AWAY[fs.getName(tostring(path or ""))]
if not id then return nil end
if floppyHere(id) then return nil end
return id
end

function waitForNetwork()
local maxW = tonumber(startCfg("wait", 60)) or 60
local missing = netMissing()
if maxW <= 0 or #missing == 0 then return missing end
local okM, m = pcall(peripheral.find, "monitor")
local monW = okM and m or nil
local t0 = os.clock()
print("Waiting for blocks that are not loaded yet (" .. #missing .. ") - tap the screen or press a key to start now")
while #missing > 0 and os.clock() - t0 < maxW do
local left = math.ceil(maxW - (os.clock() - t0))
if monW then
pcall(function()
monW.setBackgroundColor(colors.black)
monW.clear()
monW.setTextColor(colors.orange)
monW.setCursorPos(2, 2)
monW.write("BASE STARTING - waiting for its blocks to load (" .. left .. " s)")
monW.setTextColor(colors.lightGray)
for i, e in ipairs(missing) do
if i > 12 then break end
monW.setCursorPos(4, 3 + i)
monW.write(e.name .. "  (" .. tostring(e.what) .. ")")
end
monW.setTextColor(colors.white)
monW.setCursorPos(2, 5 + math.min(12, #missing))
monW.write("Tap the screen to start without them - they are found when their chunk loads.")
end)
end
local tm = os.startTimer(1)
local ev, a = os.pullEventRaw()
if ev == "terminate" then error("Terminated", 0) end
if ev == "key" or ev == "char" or ev == "monitor_touch" then break end
missing = netMissing()
end
if #missing > 0 then
print("Started without: " .. #missing .. " block(s) / floppy(s) - their chunks may not be loaded")
end
return missing
end
NET_START_MISSING = waitForNetwork()
for _, e in ipairs(NET_START_MISSING) do
if e.kind == "floppy" then
for _, f in ipairs(NET.f[e.id].files) do DATA_AWAY[f] = e.id end
end
end
pcall(noteNetwork)

inv, mon, det, envDet, bridge, bridgeKind = nil

inv, picked.inv = locate("Inventory Manager", CONFIG.names.inventoryManager, IM_TYPES)
mon, picked.mon = locate("monitor", CONFIG.names.monitor, { "monitor" }, true, true)

if not mon.isColor() then error("This needs an Advanced (gold) Monitor for colours.", 0) end


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


function netSummary()
local out = {}
for _, n in ipairs(peripheral.getNames()) do
local ty = peripheral.getType(n)
out[#out + 1] = n .. (ty and (" (" .. ty .. ")") or "")
end
table.sort(out)
return out
end


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

