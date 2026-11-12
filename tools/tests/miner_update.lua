-- miner.lua m21 updates from the base (MINE UPDATE): pieces put together, a damaged
-- or non-compiling one never installed, a full disk keeps the old program, a good one
-- written safely (old -> .old), state saved, restart.
--   lua5.3 tools/tests/miner_update.lua miner.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "miner.lua"):read("a")
local function piece(from, to)
  local a = src:find(from, 1, true)
  local b = src:find(to, a + 1, true)
  assert(a and b, "not found: " .. from)
  return src:sub(a, b - 1)
end
local FILES, CAP = { ["miner.lua"] = "OLD PROGRAM" }, 1e9
fs = {
  exists = function(p) return FILES[p] ~= nil end,
  getSize = function(p) return #(FILES[p] or "") end,
  delete = function(p) FILES[p] = nil end,
  move = function(a, b) FILES[b] = FILES[a] FILES[a] = nil end,
  open = function(p, mode)
    if mode == "r" or mode == "rb" then
      if not FILES[p] then return nil end
      local d = FILES[p]
      return { readAll = function() return d end, close = function() end }
    end
    local buf = {}
    return { write = function(s) buf[#buf + 1] = s end,
             close = function() FILES[p] = table.concat(buf):sub(1, CAP) end }   -- (a full disk cuts it off)
  end,
}
shell = { getRunningProgram = function() return "miner.lua" end }
os.epoch = function() return 1700000000000 end
local REBOOTS, SAVED, NOTES = 0, 0, {}
os.reboot = function() REBOOTS = REBOOTS + 1 end
sleep = function() end
function note(m) NOTES[#NOTES + 1] = m end
function save() SAVED = SAVED + 1 end
function sendBase() end
S = {}
load(piece("function codeHash(text)", "function setTask(t)"))()
CHECK(CODEVER == codeHash("OLD PROGRAM"), "reports the checksum of its own program")
CHECK(src:find("m.code = CODEVER", 1, true), "the checksum goes into every report")
local NEW = "-- new\nMYVER = \"m99\"\nlocal x = 1\nreturn x\n"
local V = codeHash(NEW)
local function send(text, ver, size)
  local n = math.ceil(#text / size)
  for i = n, 1, -1 do updPiece({ ver or codeHash(text), tostring(i), tostring(n), text:sub((i - 1) * size + 1, i * size) }) end
end
-- damaged (a piece swapped)
send(NEW, V, 7)
CHECK(UPD_READY and UPD_READY.ver == V and UPD_READY.text == NEW, "pieces in any order -> the program, ready")
UPD_READY = nil
updPiece({ V, "1", "2", "-- broken " }) updPiece({ V, "2", "2", "text" })
CHECK(UPD_READY == nil and NOTES[#NOTES]:find("damaged"), "a checksum that does not match is not used")
send("this does not ( compile", nil, 5)
CHECK(UPD_READY == nil and NOTES[#NOTES]:find("compile"), "a program that does not compile is not used")
-- the running version again: nothing
UPD_READY = nil
send("OLD PROGRAM", nil, 4)
CHECK(UPD_READY == nil, "the program it runs already: nothing to do")
-- full disk: old program untouched
send(NEW, V, 9)
CAP = 10
CHECK(installMinerUpdate() == false and FILES["miner.lua"] == "OLD PROGRAM" and not FILES["miner.new"], "a full disk: the old program stays, no temp file")
CHECK(REBOOTS == 0, "and no restart")
-- good one
CAP = 1e9
send(NEW, V, 9)
installMinerUpdate()
CHECK(FILES["miner.lua"] == NEW and FILES["miner.lua.old"] == "OLD PROGRAM", "installed; the old one kept as miner.lua.old")
CHECK(SAVED >= 1 and REBOOTS == 1, "state saved, then restart")
-- only while paused
local mr = piece("function minerRun()", "function loaderRun()")
CHECK(mr:find("if UPD_READY and not S.dumping then installMinerUpdate() end", 1, true), "miners install only in the paused branch")
CHECK(src:find("if UPD_READY and not (S.plan and (S.running or S.plan.goSent == S.plan.ci or S.plan.phase == \"cross\")) then", 1, true),
      "the loader never installs while running or in a crossing")
print(FAILS == 0 and "OK" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
