














CURIOS = { fits = {}, auto = {}, busy = {}, lastRead = -100 }
local FITS_FILE, AUTO_FILE = "curios_fits.dat", "curios_auto.dat"

local function load(path)
if not fs.exists(path) then return nil end
local h = fs.open(path, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
return type(t) == "table" and t or nil
end
CURIOS.fits = load(FITS_FILE) or {}
CURIOS.auto = load(AUTO_FILE) or {}
for _, list in pairs(CURIOS.fits) do
for n in pairs(list) do if meRememberName then meRememberName(n) end end
end

function CURIOS.save()
saveFileSafe(FITS_FILE, serialSmall(CURIOS.fits))
saveFileSafe(AUTO_FILE, serialSmall(CURIOS.auto))
end


function CURIOS.learn(slot, name)
if type(slot) ~= "string" or type(name) ~= "string" then return end
CURIOS.fits[slot] = CURIOS.fits[slot] or {}
if not CURIOS.fits[slot][name] then
CURIOS.fits[slot][name] = true
if meRememberName then meRememberName(name) end
CURIOS.save()
end
end

function CURIOS.learnWorn(rows)
for _, row in ipairs(rows or {}) do
for _, it in pairs(row.cells or {}) do
if type(it) == "table" and it.name then CURIOS.learn(row.name, it.name) end
end
end
end


function CURIOS.ruleOf(slot, name)
for i, r in ipairs(CURIOS.auto) do if r.slot == slot and r.item == name then return i end end
end

function CURIOS.toggleAuto(slot, name, display)
local i = CURIOS.ruleOf(slot, name)
if i then
table.remove(CURIOS.auto, i)
CURIOS.save()
return false
end
CURIOS.auto[#CURIOS.auto + 1] = { slot = slot, item = name, display = display }
CURIOS.learn(slot, name)
CURIOS.save()
CURIOS.lastRead = -100
return true
end


local function emptySlot(row)
for pos = 1, row.count or 0 do
if not row.cells[pos] then return (row.raw and row.raw[pos]) or (pos - 1 + (row.base or 1)), pos end
end
end

local function wearing(row, name)
for _, it in pairs(row.cells or {}) do if type(it) == "table" and it.name == name then return true end end
return false
end





function CURIOS.autoTick()
if #CURIOS.auto == 0 or not inv or not bridge or not fetchCurios then return end

if os.clock() - CURIOS.lastRead < 1.5 then return end
CURIOS.lastRead = os.clock()
local ok, rows, msg, note = pcall(fetchCurios)
if not ok or type(rows) ~= "table" then return end
state.curios, state.curiosMsg, state.curiosNote = rows, msg, note
state.t.curios = os.clock()
CURIOS.learnWorn(rows)
if note then return end
for _, r in ipairs(CURIOS.auto) do
local row
for _, x in ipairs(rows) do if x.name == r.slot then row = x end end
local key = r.slot .. "|" .. r.item
if row and not row.unreadable and not wearing(row, r.item) and os.clock() >= (CURIOS.busy[key] or 0) then
local slotNo = emptySlot(row)
if slotNo then
local okI, it = callx(bridge, "getItem", { name = r.item })
local have = okI and type(it) == "table" and (tonumber(it.count) or 0) or 0
if have > 0 then
CURIOS.busy[key] = os.clock() + 20
r.why = nil

table.insert(state.actionQueue, 1, { kind = "cequip", name = r.item, count = 1, slotType = r.slot,
slotNo = slotNo, auto = true, key = "auto:" .. key })
os.queueEvent("inv_action")
else
r.why = "none left in AE2"
CURIOS.busy[key] = os.clock() + 60
end
end
end
end
end

function CURIOS.autoResult(a, n, err)
local key = a.slotType .. "|" .. a.name
for _, r in ipairs(CURIOS.auto) do
if r.slot == a.slotType and r.item == a.name then r.why = (n > 0) and nil or tostring(err or "did not go on") end
end
if n > 0 then
CURIOS.learn(a.slotType, a.name)
if pushNote then pushNote("DONE", "Auto-equipped " .. (a.display or prettify(a.name)) .. " (" .. a.slotType .. ")", C.good) end
else
CURIOS.busy[key] = os.clock() + 60
end
end
