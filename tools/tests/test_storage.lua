-- THE MAP NEVER LOSES WHAT WAS SAVED (the owner: "check the storage code too - floppy drives, helpers, how the
-- map is saved"). The map is split over the data floppies, the storage helpers and the computer. What goes wrong
-- in a real world: a helper that does not answer at the start (a server restart: computers start late), one that
-- stops answering half way through being read, a floppy that is out of its drive at the start, a base restart
-- after each. Every chunk ever saved must still be in the map after the next start (its OVERVIEW cell is never
-- dropped - the detail may be). Before: the copy read first "counted" - a newer copy written elsewhere while the
-- old place was away was thrown away (or the old one), and files a helper did not hand over were taken as read.
CODE_SIZE = 800000
CONFIG.map.maxChunks = 20          -- (a full map: most chunks are in the OVERVIEW only - it must never lose one)
local REMOTE, DOWN, CALLS, DOWN_AFTER = {}, {}, {}, {}
local function helper(id) REMOTE[id] = { files = {}, cap = 1000000 } end
local function used(id) local n = 0 for _, t in pairs(REMOTE[id].files) do n = n + #t end return n end
-- what store.lua does (incl. its 200 KB cap on one "get" answer)
STORE.call = function(id, req)
  CALLS[id] = (CALLS[id] or 0) + 1
  local h = REMOTE[id]
  if DOWN_AFTER[id] then
    DOWN_AFTER[id] = DOWN_AFTER[id] - 1
    if DOWN_AFTER[id] < 0 then DOWN[id], DOWN_AFTER[id] = true, nil end
  end
  if not h or DOWN[id] then return nil, "no answer" end
  local free = h.cap - used(id)
  if req.op == "hello" then
    local n = 0 for _ in pairs(h.files) do n = n + 1 end
    return { ok = true, free = free, cap = h.cap, files = n }
  elseif req.op == "put" then
    if #req.data + 4096 > free then return nil, "full" end
    h.files[req.name] = req.data
    return { ok = true, free = h.cap - used(id) }
  elseif req.op == "get" then
    local out, size = {}, 0
    for _, n in ipairs(req.names) do
      if h.files[n] and size < 200000 then out[n] = h.files[n] size = size + #h.files[n] end
    end
    return { ok = true, files = out }
  elseif req.op == "list" then
    local out = {}
    for n, t in pairs(h.files) do
      local f = n:match("^" .. req.dir .. "/([^/]+)$")
      if f then out[f] = #t end
    end
    return { ok = true, files = out }
  elseif req.op == "del" then
    h.files[req.name] = nil
    return { ok = true }
  end
  return nil, "bad op"
end
PERIPHS["back"] = { types = { "modem" }, obj = { isWireless = function() return false end } }
rednet.isOpen = rednet.isOpen or function() return true end
rednet.lookup = function() local o = {} for id in pairs(REMOTE) do o[#o + 1] = id end return table.unpack(o) end

addDrive("drive_9", "disk9")
fs.open("disk9/base_data", "w").close()
local function eject(name) DRIVES[name] = nil end
local function insert(name, mount) DRIVES[name] = mount end

-- what was saved: every chunk of every scan that went into a successful save
local SAVED = {}
local pendingChunks = {}
local function scanAt(x, z, gen)
  local cols = {}
  for i = 1, 17 * 17 do cols[i] = { 60 + (x + z + gen) % 9, 1 } end
  MAP.addScan({ x = x, y = 70, z = z, r = 8, cols = cols, names = { "minecraft:grass_block" } })
  for dx = -8, 8, 8 do for dz = -8, 8, 8 do
    pendingChunks[math.floor((x + dx) / 16) .. "," .. math.floor((z + dz) / 16)] = true
  end end
end
local function save()
  MAP.save()
  if not next(MAP.dirty) then
    for k in pairs(pendingChunks) do SAVED[k] = true end
    pendingChunks = {}
  end
end
-- a base restart: memory gone, the map read again (as the map worker does it)
local function restart()
  MAP.ch, MAP.order, MAP.ov, MAP.where, MAP.dirty, MAP.rsize = {}, {}, {}, {}, {}, {}
  MAP.scans, MAP.tick, MAP.ovN = 0, 0, 0
  MAP.loaded, MAP.pendingScans = false, {}
  if MAP.readAt then MAP.readAt = {} end
  STORE.helpers = {}
  if next(STORE.known) then STORE.find(true) end
  MAP.loadNow()
end
-- the map worker's later turns (a helper / floppy that was away comes back)
local function workerTurns(n)
  for _ = 1, n or 3 do
    CLOCK = CLOCK + 61
    if MAP.readLate then MAP.readLate() end
    STORE.find(true)
    if MAP.readLate then MAP.readLate() end
    save()
  end
end
local function lost(tag)
  local miss, n = {}, 0
  for k in pairs(SAVED) do
    n = n + 1
    local cx, cz = k:match("^(%-?%d+),(%-?%d+)$")
    local h = MAP.getOverview(tonumber(cx) * 16 + 8, tonumber(cz) * 16 + 8)
    if not h then miss[#miss + 1] = k end
  end
  table.sort(miss)
  return #miss, n, table.concat(miss, " ", 1, math.min(#miss, 8))
end
local function where(p) local id = STORE.parse(p) return id and ("helper " .. id) or p:match("^([^/]+)") end

-- 0) the map on a floppy + two helpers
for id = 119, 120 do helper(id) end
STORE.find(true)
STORE.find()
MAP.loaded = true
for a = 0, 9 do for b = 0, 9 do scanAt(a * 17, b * 17, 0) end end
save()
restart()
local m, n = lost()
CHECK(n > 50 and m == 0, "a plain restart: every saved chunk is back (" .. (n - m) .. " of " .. n .. ")")
local byPlace = {}
for _, p in pairs(MAP.where) do byPlace[where(p)] = (byPlace[where(p)] or 0) + 1 end
CHECK(byPlace["helper 119"] and byPlace["helper 120"], "the map is on both helpers")

-- 1) a helper does NOT ANSWER at the start (it starts late after a server restart); new scans in places it
-- already holds; it answers again later
local function holder(k) return STORE.parse(MAP.where[k] or "") end
local H1 = holder("o0_0")
CHECK(H1, "(the overview file o0_0 is on a helper: " .. tostring(MAP.where["o0_0"]) .. ")")
DOWN[H1] = true
restart()
for a = 0, 9 do scanAt(a * 17, 300, 1) end              -- (new chunks in the same overview file)
save()
DOWN[H1] = nil
workerTurns()
restart()
m, n = lost()
CHECK(m == 0, "helper silent at the start, back later: nothing saved before is lost (" .. m .. " of " .. n ..
      " chunks gone: " .. select(3, lost()) .. ")")

-- 2) a helper stops answering HALF WAY through being read (after its file list + one batch)
local H2 = holder("o0_0")
DOWN_AFTER[H2] = 2                                       -- (hello, its file list - then nothing)
restart()
for a = 0, 9 do scanAt(a * 17, 360, 2) end
save()
DOWN[H2] = nil
workerTurns()
restart()
m, n = lost()
CHECK(m == 0, "helper gone half way through the reading: nothing is lost (" .. m .. " of " .. n .. " gone: " ..
      select(3, lost()) .. ")")

-- 3) a data FLOPPY out of its drive at the start; new scans; it is put back
STORE.helpers, STORE.known = {}, {}
for id in pairs(REMOTE) do REMOTE[id] = nil end
restart()
SAVED = {}
for a = 12, 15 do for b = 0, 3 do scanAt(a * 17, b * 17, 3) end end
save()
local onDisk = 0
for _, p in pairs(MAP.where) do if p:find("^disk9/") then onDisk = onDisk + 1 end end
CHECK(onDisk > 0, "(without helpers the map is on the floppy: " .. onDisk .. " files)")
eject("drive_9")
restart()
for a = 12, 15 do scanAt(a * 17, 420, 4) end
save()
insert("drive_9", "disk9")
workerTurns()
restart()
m, n = lost()
CHECK(m == 0, "floppy out at the start, put back: nothing is lost (" .. m .. " of " .. n .. " gone: " .. select(3, lost()) .. ")")

-- 4) a key found TWICE at the start (an old copy left behind) is read as one: both copies' chunks are kept,
-- the extra copy is deleted once the joined one is saved
local k1
for k, p in pairs(MAP.where) do if k:sub(1, 1) == "o" then k1 = k break end end
local text = FILES[MAP.where[k1]]
FILES["map/" .. k1 .. ".dat"] = text                    -- (the same file also on the computer)
restart()
save()
local copies = 0
for _, p in ipairs({ "map/" .. k1 .. ".dat", "disk9/map/" .. k1 .. ".dat" }) do if FILES[p] then copies = copies + 1 end end
CHECK(copies == 1, "a file found twice: one copy left after the save (" .. copies .. ")")
m, n = lost()
CHECK(m == 0, "... and nothing lost (" .. m .. " gone)")

-- 5) while a place is not read yet, nothing is WRITTEN there: a helper silent at the start holds an old
-- overview file (o5_5) of an area that gets new scans meanwhile; it answers again -> its old chunks and the new
-- ones are joined, nothing of either is lost
local function ovCount(ox, oz)
  local n = 0
  for cx = ox * 32, ox * 32 + 31 do for cz = oz * 32, oz * 32 + 31 do
    if MAP.getOverview(cx * 16 + 8, cz * 16 + 8) then n = n + 1 end
  end end
  return n
end
local oldText = FILES[MAP.where["o0_0"]] or ""
local nOld = ovCount(0, 0)
CHECK(nOld > 20 and oldText:find("\nV 0 0 "), "(an overview file to copy: " .. nOld .. " chunks)")
helper(130)
REMOTE[130].files["map/o5_5.dat"] = oldText:gsub("\nV 0 0 ", "\nV 5 5 ")
STORE.known[130] = true
DOWN[130] = true
restart()
CHECK(ovCount(5, 5) == 0, "(helper 130 silent: its old overview is not known yet)")
for a = 0, 3 do scanAt(5 * 512 + 300 + a * 17, 5 * 512 + 400, 5) end
save()
CHECK(REMOTE[130].files["map/o5_5.dat"] == oldText:gsub("\nV 0 0 ", "\nV 5 5 "),
      "a helper whose files were not read yet is not written to")
DOWN[130] = nil
STORE.find(true)
save()
CHECK(MAP.readAt["store:130/map"], "it answers again: read")
local nNew = ovCount(5, 5)
CHECK(nNew >= nOld + 4, "its old chunks and the new scans are JOINED (" .. nNew .. " chunks, old " .. nOld .. ")")
restart()
CHECK(ovCount(5, 5) == nNew, "... and after a restart still all there (" .. ovCount(5, 5) .. " of " .. nNew .. ")")
local copies = 0
for _, p in pairs({ "disk9/map/o5_5.dat", "map/o5_5.dat" }) do if FILES[p] then copies = copies + 1 end end
if REMOTE[130].files["map/o5_5.dat"] then copies = copies + 1 end
CHECK(copies == 1, "one copy of o5_5 left (" .. copies .. ")")

-- 6) a data file whose floppy was taken out (dataPath keeps its place for a minute): the save goes where the
-- file belongs NOW - not into a folder "disk9" made on the computer
addDrive("drive_8", "disk8")
fs.open("disk8/base_data", "w").close()
dataPathReset()
local p0 = dataPath("turtles_test.dat")
CHECK(p0:find("^disk"), "(the data file lives on a floppy: " .. p0 .. ")")
local mount = p0:match("^([^/]+)")
local drive = mount == "disk8" and "drive_8" or "drive_9"
eject(drive)
local ok, np = saveFileSafe(p0, "{ hello = 1 }")
CHECK(ok and np and not np:find("^" .. mount .. "/"), "floppy out: saved elsewhere (" .. tostring(np) .. ")")
CHECK(FILES[np or ""] == "{ hello = 1 }", "... whole")
insert(drive, mount)
-- the computer's copy moves to a floppy only when the floppy's copy is WHOLE
FILES["bigdata.dat"] = string.rep("q", 3000)
local realCopy = fs.copy
fs.copy = function(a, b) FILES[b] = FILES[a]:sub(1, 100) end      -- (a full floppy cuts the copy off)
local dp = dataFile("bigdata.dat")
fs.copy = realCopy
CHECK(FILES["bigdata.dat"] and #FILES["bigdata.dat"] == 3000, "a cut-off copy: the computer's copy is kept")
CHECK(dp == "bigdata.dat", "... and used (" .. tostring(dp) .. ")")
