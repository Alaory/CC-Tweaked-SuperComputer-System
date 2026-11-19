-- STORAGE HELPERS ARE USED (the owner's `disks`: 4 helpers with 953 KB free and
-- 0 files each, the data floppy and the computer full - "DISK ALMOST FULL:
-- disk/drone_logs.dat not saved"). The map filled the floppies to the last KB and
-- only spilled onto the helpers after that. Now: helpers FIRST, map files already
-- on the floppies move onto them, the floppies keep room for the data files, a data
-- file that no longer fits on its floppy moves to another one, a helper that goes
-- quiet is skipped, and an old copy left on a quiet helper is never read again.
CODE_SIZE = 800000
MAP.loaded = true

-- fake helper computers: what store.lua does, in memory
local REMOTE, DOWN, CALLS = {}, {}, {}
local function helper(id) REMOTE[id] = { files = {}, cap = 1000000 } end
local function used(id) local n = 0 for _, t in pairs(REMOTE[id].files) do n = n + #t end return n end
STORE.call = function(id, req, timeout)
  CALLS[id] = (CALLS[id] or 0) + 1
  local h = REMOTE[id]
  if not h or DOWN[id] then return nil, "no answer" end
  local free = h.cap - used(id)
  if req.op == "hello" then
    local n = 0 for _ in pairs(h.files) do n = n + 1 end
    return { ok = true, free = free, cap = h.cap, files = n }
  elseif req.op == "put" then
    if #req.data > free then return nil, "disk full" end
    h.files[req.name] = req.data
    return { ok = true, free = h.cap - used(id) }
  elseif req.op == "get" then
    local out = {}
    for _, n in ipairs(req.names) do out[n] = h.files[n] end
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
local function lookHelpers()
  STORE.helpers = {}
  for id in pairs(REMOTE) do
    local r = STORE.call(id, { op = "hello" })
    if r then STORE.helpers[id] = { id = id, free = r.free, cap = r.cap, files = r.files } end
  end
end
local function count(where)
  local n = 0
  for _, p in pairs(MAP.where) do if where(p) then n = n + 1 end end
  return n
end
local function onHelper(p) return p:find("^store:") ~= nil end
local function onFloppy(p) return p:find("^disk") ~= nil end
local function scanAt(x, z)
  local cols = {}
  for i = 1, 17 * 17 do cols[i] = { 64 + (x + z) % 7, 1 } end
  MAP.addScan({ x = x, y = 70, z = z, r = 8, cols = cols, names = { "minecraft:grass_block" } })
end

addDrive("drive_9", "disk9")
fs.open("disk9/base_data", "w").close()

-- 1) before the helpers: the map on the data floppy (as it was)
for a = 0, 7 do for b = 0, 7 do scanAt(a * 17, b * 17) end end
MAP.save()
local nFiles = count(function() return true end)
CHECK(nFiles > 4 and count(onFloppy) == nFiles, "no helpers: the map on the data floppy (" .. count(onFloppy) .. " of " .. nFiles .. ")")

-- 2) four helpers appear: the map files on the floppy MOVE onto them
for id = 119, 122 do helper(id) end
lookHelpers()
CHECK(MAP.helpersFirst(), "helpers with room: the map uses them first")
local moved, left = MAP.offload()
CHECK(moved == nFiles and left == 0, "every floppy map file moved onto the helpers (" .. tostring(moved) .. " of " .. nFiles ..
      ", " .. tostring(left) .. " left)")
CHECK(count(onHelper) == nFiles, "MAP.where points at the helpers (" .. count(onHelper) .. ")")
local floppyMap = 0
for p in pairs(FILES) do if p:find("^disk9/map/") then floppyMap = floppyMap + 1 end end
CHECK(floppyMap == 0, "no map files left on the floppy (" .. floppyMap .. ")")
local remoteN = 0
for id = 119, 122 do for _ in pairs(REMOTE[id].files) do remoteN = remoteN + 1 end end
CHECK(remoteN == nFiles, "the helpers hold the files (" .. remoteN .. ")")
local _, _, _, rbytes, rfiles = MAP.diskUse()
CHECK(rfiles == nFiles and rbytes > 0, "MAP.diskUse counts the helpers' files")
CHECK(select(1, MAP.offload()) == 0, "nothing more to move")

-- 3) new scans go straight to the helpers, not the floppy
for a = 8, 11 do scanAt(a * 17, 0) end
MAP.save()
CHECK(count(onFloppy) == 0 and count(onHelper) == count(function() return true end), "new map files go to the helpers")

-- 4) a helper goes quiet: skipped after one try, the files go to the others
local victim
for k, p in pairs(MAP.where) do
  local id = STORE.parse(p)
  if id then victim = id break end
end
DOWN[victim] = true
CALLS[victim] = 0
local onVictim = {}
for k, p in pairs(MAP.where) do if STORE.parse(p) == victim then onVictim[#onVictim + 1] = k MAP.dirty[k] = true end end
MAP.save()
CHECK(#onVictim > 0 and not next(MAP.dirty), "saved although helper " .. victim .. " is quiet (" .. #onVictim .. " files)")
local still = 0
for _, k in ipairs(onVictim) do if STORE.parse(MAP.where[k]) == victim then still = still + 1 end end
CHECK(still == 0, "its files went to the other helpers")
-- one put, then (moving its files away) one delete per file that could not reach it
CHECK(CALLS[victim] <= 1 + #onVictim, "the quiet helper is not asked again for every file (" .. CALLS[victim] .. " calls, " .. #onVictim .. " files)")
local nStale = 0
for _ in pairs(MAP.stale) do nStale = nStale + 1 end
CHECK(nStale == #onVictim, "its old copies are remembered as STALE (" .. nStale .. ")")

-- 5) it answers again: the stale copies are deleted, never read (the newer ones elsewhere count)
DOWN[victim] = nil
local key1 = onVictim[1]
local newPath = MAP.where[key1]
-- an old copy has OTHER content: if it were read it would be the one kept
local stalePath = "store:" .. victim .. "/map/" .. key1 .. ".dat"
CHECK(REMOTE[victim].files["map/" .. key1 .. ".dat"] ~= nil, "the old copy is still on the quiet helper")
lookHelpers()
MAP.where, MAP.rsize = {}, {}
MAP.load()
CHECK(MAP.where[key1] == newPath, "after a reload the NEW copy counts (" .. tostring(MAP.where[key1]) .. ")")
CHECK(REMOTE[victim].files["map/" .. key1 .. ".dat"] == nil, "the stale copy was deleted")
CHECK(not MAP.stale[stalePath], "and forgotten")

-- 6) helpersFirst off (setting): the floppy first again (the old order)
CONFIG.map.helpersFirst = false
for a = 0, 3 do scanAt(a * 17, 300) end
MAP.save()
local onF = 0
for k, p in pairs(MAP.where) do if onFloppy(p) then onF = onF + 1 end end
CHECK(onF > 0, "helpersFirst = false: new files on the floppy")
CONFIG.map.helpersFirst = nil

-- 7) the floppy keeps room for data files: the map never takes the last 48 KB
STORE.helpers = {}                                     -- (no helpers: 16 KB)
CHECK(MAP.floppyKeep() == 16 * 1024, "no helpers: 16 KB kept free")
lookHelpers()
CHECK(MAP.floppyKeep() == 48 * 1024, "with helpers: 48 KB kept free")

-- 8) a data file that no longer fits on its floppy moves to another data floppy
addDrive("drive_10", "disk10")
fs.open("disk10/base_data", "w").close()
local pad = fs.getFreeSpace("disk9") - 6000
FILES["disk9/junk.bin"] = string.rep("x", pad)
local logs = string.rep("drone log line ", 2000)          -- ~30 KB
local ok, np = saveFileSafe("disk9/drone_logs.dat", logs)
CHECK(ok and np == "disk10/drone_logs.dat" and FILES["disk10/drone_logs.dat"] == logs,
      "drone_logs.dat did not fit on disk9: saved on disk10 (" .. tostring(np) .. ")")
CHECK(not FILES["disk9/drone_logs.dat"], "the old copy is gone")
CHECK(dataFile("drone_logs.dat") == "disk10/drone_logs.dat", "dataFile finds it there")
-- program files / logs / folders are never moved like that
local okL = saveFileSafe("disk9/events.log", logs)
CHECK(not okL and not FILES["disk10/events.log"], "a log is not moved (it keeps its .old partner)")
local okM = saveFileSafe("disk9/map/zz.dat", logs)
CHECK(not okM and not FILES["disk10/zz.dat"], "a map file is not moved by saveFileSafe")
FILES["disk9/junk.bin"] = nil

