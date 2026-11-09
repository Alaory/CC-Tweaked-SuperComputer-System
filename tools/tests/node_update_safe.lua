-- A turtle program update on a FULL DISK must never leave the turtle without a
-- program: the new one is written to a temp file and checked first; if it does not
-- fit, the old program stays exactly as it was and the update is refused.
--   lua5.3 tools/tests/node_update_safe.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local a = src:find("function installUpdate(code)", 1, true)
local b = src:find("-- commands that answer at once", a, true)
load(src:sub(a, b - 1))()
-- a tiny fake disk with a size limit
local FILES, LIMIT = {}, 0
local function used() local n = 0 for _, v in pairs(FILES) do n = n + #v end return n end
fs = {
  exists = function(p) return FILES[p] ~= nil end,
  delete = function(p) FILES[p] = nil end,
  getSize = function(p) return #FILES[p] end,
  getFreeSpace = function() return LIMIT - used() end,
  copy = function(x, y) if used() + #FILES[x] > LIMIT then error("Out of space") end FILES[y] = FILES[x] end,
  move = function(x, y) FILES[y] = FILES[x] FILES[x] = nil end,
  open = function(p, mode)
    FILES[p] = ""                                     -- (opening for writing EMPTIES the file)
    return { write = function(t)
               local room = LIMIT - used()
               if #t > room then FILES[p] = FILES[p] .. t:sub(1, room) error("Out of space") end
               FILES[p] = FILES[p] .. t
             end, close = function() end }
  end }
MYPATH = "startup.lua"
local OLD, NEW = string.rep("o", 1000), string.rep("n", 1200)
-- enough room: installed, the old one kept as startup.old
FILES = { ["startup.lua"] = OLD } LIMIT = 5000
installUpdate(NEW)
CHECK(FILES["startup.lua"] == NEW and FILES["startup.old"] == OLD and not FILES["startup.new"], "room enough: new program in, old one kept")
-- room only without the old backup: the backup goes, the update still goes in
FILES = { ["startup.lua"] = OLD, ["startup.old"] = string.rep("x", 1000) } LIMIT = 3300
installUpdate(NEW)
CHECK(FILES["startup.lua"] == NEW, "tight: installed after dropping the old backup")
-- NO room at all: refused, the running program untouched (before: emptied / cut off)
FILES = { ["startup.lua"] = OLD, ["data"] = string.rep("d", 1500) } LIMIT = 3000
local ok, err = pcall(installUpdate, NEW)
CHECK(not ok and tostring(err):find("disk is too full", 1, true), "full disk: refused with a clear reason (" .. tostring(err) .. ")")
CHECK(FILES["startup.lua"] == OLD, "full disk: the old program is still complete (" .. #(FILES["startup.lua"] or "") .. " of 1000 bytes)")
CHECK(not FILES["startup.new"], "full disk: no half-written file left behind")
-- the dangerous case: the backup copy still fits, the NEW program does not - the old
-- code emptied startup.lua, wrote 1100 of 1200 bytes and failed: a turtle with a cut-off program
FILES = { ["startup.lua"] = OLD } LIMIT = 2100
local ok2 = pcall(installUpdate, NEW)
CHECK(not ok2 and FILES["startup.lua"] == OLD, "backup fits, update does not: the old program is untouched (" ..
      #(FILES["startup.lua"] or "") .. " bytes, first '" .. tostring((FILES["startup.lua"] or "?"):sub(1, 1)) .. "')")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
