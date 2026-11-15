-- node.lua writeFile on a FULL disk: the old state file (position, home, facing) stays whole
-- (before: opening it for writing emptied it -> everything forgotten at the next start);
-- a ".new" left by a stop between delete and move is read back.
--   lua5.3 tools/tests/node_save_safe.lua node.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local src = io.open(arg[1] or "node.lua"):read("a")
local a = src:find("function writeFile(path, value)", 1, true)
local b = src:find("\ndo\n  local t = readTable(STATE_FILE)", a, true)
local code = src:sub(a, b)
local FILES, CAP = {}, 1e9
local function used() local n = 0 for _, v in pairs(FILES) do n = n + #v end return n end
fs = {
  exists = function(p) return FILES[p] ~= nil end,
  getSize = function(p) return #(FILES[p] or "") end,
  delete = function(p) FILES[p] = nil end,
  move = function(x, y) FILES[y] = FILES[x] FILES[x] = nil end,
  open = function(p, mode)
    if mode == "r" then
      if not FILES[p] then return nil end
      local d = FILES[p]
      return { readAll = function() return d end, close = function() end }
    end
    FILES[p] = ""                                   -- (opening for writing empties it)
    local buf = {}
    return { write = function(s) buf[#buf + 1] = s end,
             close = function() local t = table.concat(buf) local room = CAP - used()
                                FILES[p] = t:sub(1, math.max(0, room)) end }
  end,
}
textutils = { serialize = function(t) local o = {} for k, v in pairs(t) do o[#o + 1] = k .. "=" .. tostring(v) end
                                     table.sort(o) return "{" .. table.concat(o, ",") .. "}" end,
              unserialize = function(s) if s:sub(1, 1) == "{" and s:sub(-1) == "}" then return { raw = s } end end }
DUP = false
printError = function() end
assert(load(code, "=writeFile"))()
CHECK(writeFile("node_state", { x = 1, y = 2, home = "base" }), "a normal save works")
local good = FILES["node_state"]
CAP = used() + 5                                     -- the disk is (almost) full
CHECK(writeFile("node_state", { x = 99, y = 2, home = "base", more = "something long" }) == false, "full disk: the save says it failed")
CHECK(FILES["node_state"] == good, "full disk: the OLD state file is still whole (" .. tostring(FILES["node_state"]) .. ")")
CHECK(not FILES["node_state.new"], "no half-written .new left")
-- stopped between delete and move: only the .new is there -> read back
CAP = 1e9
FILES = { ["node_state.new"] = "{home=base,x=5}" }
local t = readTable("node_state")
CHECK(t and t.raw == "{home=base,x=5}", "a .new left behind is read back")
print(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
os.exit(FAILS == 0 and 0 or 1)
