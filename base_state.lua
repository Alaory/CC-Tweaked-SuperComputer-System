-- base_state.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   The shared `state` table: everything the screen shows is read from here
--   (workers fill it, drawing only reads it). Also reads the owner's inventory
--   (list() or getItems(), whichever this Advanced Peripherals version has).

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------
state = {
  status = "loading", -- loading | ok | nocard | offline
  owner = nil,
  slots = {},         -- [0..35] = item
  list = {},          -- aggregated {name, display, count, slots}
  total = 0,
  used = 0,
  dropped = 0,
  equip = {},         -- [1..5] = Helm, Chest, Legs, Boots, Offhand
  player = nil,       -- data of the owner from the Player Detector (optional)
  playerDim = nil,
  playerMsg = nil,
  players = {},       -- all online players {name, p, dim, isOwner, err}
  page = "inventory", -- visible tab: inventory players storage curios me drone access turtles map
  playersPage = 1,
  rawView = {},       -- [name] = true -> show raw data on that card
  storage = {},       -- backpacks, buckets, ... {display, where, size, used, contents, tanks}
  storageMsg = nil,
  storagePage = 1,
  curios = nil,       -- { {name, count, cells = {[pos] = item}} ... }
  curiosMsg = nil,
  me = nil,           -- last ME network read
  meVersion = 0,
  meSel = nil,        -- selected ME item (registry name)
  meSort = "count",
  meCraftOnly = false,
  meLetter = nil,
  meItemsPage = 1,
  meNext = 0,
  meForce = false,
  pending = nil,      -- two-tap confirmation {key, exp}
  notes = {},         -- message boxes on screen, newest first (pushNote in base_me.lua)
  noteLog = {},       -- the EVENTS list: the last messages, newest first
  noteUnread = 0,     -- messages since the EVENTS list was last opened
  noteHistory = false, -- is the EVENTS list open?
  drone = nil,        -- the drone selected on the DRONE tab (see the DRONE section)
  waypoints = {},     -- saved places {name, x, y, z}
  chatInbox = {},     -- chat messages waiting to be handled
  chatOut = {},       -- private replies waiting to be sent
  access = { allowed = {} },  -- chat allow list: [lowercase name] = {name, uuid}
  rideRequests = {},  -- chat ride requests waiting for the owner's approval
  turtles = {},       -- [computer id] = {label, fuel, pos, task, log, ...}
  tOut = {},          -- commands waiting to be sent to turtles
  tSel = nil,         -- selected turtle id
  tModem = nil,       -- name of the wireless/ender modem used for turtles
  tLastN = 0,
  lastRide = {},      -- [lowercase name] = time of their last chat ride
  ownerUuid = nil,
  t = {},             -- when each kind of data was last read (cache age)
  force = {},         -- "re-read this now" flags
  rawItems = nil,     -- last raw inventory read (for the storage page)
  base = 1,
  actionQueue = {},   -- confirmed transfers/crafts waiting to run
  busy = false,
  running = true,
}

dimCache = {}   -- from playerJoin / playerChangedDimension events

sortMode = "count"
selName = nil
hits = {}

-- sort the item list by the current SORT mode (count / name / slot)
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

-- "minecraft:iron_ingot" -> "Iron Ingot"
cleanCache = {}
-- a display name without colour codes and [ ] brackets (cached)
function cleanName(n)
  n = tostring(n)
  local c = cleanCache[n]
  if c then return c end
  local r = n
  r = r:gsub("\194\167.", ""):gsub("\167.", "")   -- colour codes
  r = r:gsub("[%[%]]", "")                           -- [ and ]
  r = r:gsub("^%s+", ""):gsub("%s+$", "")
  cleanCache[n] = r
  return r
end

prettyCache = {}
-- "minecraft:the_nether" -> "The Nether" (cached)
function prettify(id)
  local c = prettyCache[id]
  if c then return c end
  local n = id:gsub("^[^:]*:", ""):gsub("_", " ")
  local r = n:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
  prettyCache[id] = r
  return r
end

-- Newer Advanced Peripherals builds expose list() (1-based, chest style),
-- older ones expose getItems() (0-based). Support both.
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

