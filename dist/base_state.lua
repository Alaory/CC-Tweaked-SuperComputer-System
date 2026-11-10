









HAND_CMD = false
state = {
status = "loading",
owner = nil,
slots = {},
list = {},
total = 0,
used = 0,
dropped = 0,
equip = {},
player = nil,
playerDim = nil,
playerMsg = nil,
players = {},
page = "home",
playersPage = 1,
rawView = {},
storage = {},
storageMsg = nil,
storagePage = 1,
curios = nil,
curiosMsg = nil,
curiosPage = 1,
curiosSel = nil,
me = nil,
meVersion = 0,
meSel = nil,
meSort = "count",
meCraftOnly = false,
meLetter = nil,
meItemsPage = 1,
meNext = 0,
meForce = false,
pending = nil,
notes = {},
noteLog = {},
noteUnread = 0,
eventsPage = 1,
eventsFilter = "all",
drone = nil,
waypoints = {},
chatInbox = {},
chatOut = {},
access = { allowed = {} },
rideRequests = {},
turtles = {},
tOut = {},
tSel = nil,
tModem = nil,
tLastN = 0,
lastRide = {},
ownerUuid = nil,
t = {},
force = {},
rawItems = nil,
base = 1,
actionQueue = {},
busy = false,
running = true,
}


if fs.exists("ui_page.dat") then
local h = fs.open("ui_page.dat", "r")
local p = h and h.readAll() or ""
if h then h.close() end
if p:match("^%a+$") then state.page = p end
end

dimCache = {}

sortMode = "count"
selName = nil
hits = {}


function sortList()
table.sort(state.list, function(a, b)
if sortMode == "count" and a.count ~= b.count then
return a.count > b.count
elseif sortMode == "slot" and a.firstSlot ~= b.firstSlot then
return a.firstSlot < b.firstSlot
end
return a.display:lower() < b.display:lower()
end)
end


cleanCache = {}

function cleanName(n)
n = tostring(n)
local c = cleanCache[n]
if c then return c end
local r = n
r = r:gsub("\194\167.", ""):gsub("\167.", "")
r = r:gsub("[%[%]]", "")
r = r:gsub("^%s+", ""):gsub("%s+$", "")
cleanCache[n] = r
return r
end

prettyCache = {}

function prettify(id)
local c = prettyCache[id]
if c then return c end
local n = id:gsub("^[^:]*:", ""):gsub("_", " ")
local r = n:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
prettyCache[id] = r
return r
end



function readInventory()
if inv.getItems then
local ok, r, e = pcall(inv.getItems)
return ok, r, e, 0
elseif inv.list then
local ok, r, e = pcall(inv.list)
return ok, r, e, 1
end
return false, "Inventory Manager has neither getItems() nor list()", nil, 0
end

