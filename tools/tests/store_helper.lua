-- THE STORAGE HELPER PROGRAM ITSELF (store.lua, on the helper computers): the real file runs here against a
-- fake disk + cable; the base's requests come in one by one, the answers are checked.
--   lua5.3 tools/tests/store_helper.lua store.lua
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local SRC = io.open(arg[1] or "store.lua"):read("a")

local function world(files, cap)
  local W = { files = files or {}, dirs = {}, cap = cap or 1000000, sent = {}, reboots = 0 }
  local function used() local n = 0 for _, t in pairs(W.files) do n = n + #t end return n end
  local function under(d) for p in pairs(W.files) do if p:sub(1, #d + 1) == d .. "/" then return true end end end
  local env = {}
  env.fs = {
    exists = function(p) return W.files[p] ~= nil or W.dirs[p] ~= nil or under(p) end,
    isDir = function(p) return W.dirs[p] ~= nil or under(p) end,
    makeDir = function(p) W.dirs[p] = true end,
    delete = function(p) W.files[p] = nil W.dirs[p] = nil end,
    move = function(a, b) if not W.files[a] then error("no such file") end W.files[b] = W.files[a] W.files[a] = nil end,
    copy = function(a, b) W.files[b] = W.files[a] end,
    getSize = function(p) return #(W.files[p] or "") end,
    getFreeSpace = function() return W.cap - used() end,
    getCapacity = function() return W.cap end,
    combine = function(a, b) if a == "" then return b end return a .. "/" .. b end,
    getDir = function(p) return p:match("^(.*)/[^/]*$") or "" end,
    list = function(d)
      local out, seen = {}, {}
      for p in pairs(W.files) do
        local rest = p:sub(#d + 2)
        if p:sub(1, #d + 1) == d .. "/" then
          local first = rest:match("^([^/]+)")
          if first and not seen[first] then seen[first] = true out[#out + 1] = first end
        end
      end
      table.sort(out)
      return out
    end,
    open = function(p, mode)
      if mode == "r" then
        if W.files[p] == nil then return nil end
        local t = W.files[p]
        return { readAll = function() if t == "" then return nil end return t end, close = function() end }
      end
      W.files[p] = ""
      local buf = {}
      return { write = function(s) buf[#buf + 1] = s end,
               close = function()
                 local t = table.concat(buf)
                 local room = W.cap - used()
                 W.files[p] = t:sub(1, math.max(0, room))        -- (a full disk cuts it off)
               end }
    end,
  }
  local inbox = {}
  env.rednet = {
    open = function() end, host = function() end,
    send = function(id, msg) W.sent[#W.sent + 1] = { id = id, msg = msg } end,
    receive = function() return coroutine.yield() end,
  }
  env.peripheral = { getNames = function() return { "back" } end, hasType = function() return true end,
                     call = function(_, fn) if fn == "isWireless" then return false end end }
  env.os = { getComputerLabel = function() return "Store 7" end, setComputerLabel = function() end,
             getComputerID = function() return 7 end, clock = function() return W.clock or 0 end,
             reboot = function() W.reboots = W.reboots + 1 error("REBOOT") end }
  env.shell = { getRunningProgram = function() return "startup.lua" end }
  env.term = { clear = function() end, setCursorPos = function() end }
  env.print, env.printError, env.sleep = function() end, function() end, function() end
  env.settings = nil
  for _, k in ipairs({ "pairs", "ipairs", "tostring", "tonumber", "type", "pcall", "error", "load", "math", "string",
                       "table", "select", "next", "coroutine" }) do env[k] = _G[k] end
  W.files["startup.lua"] = W.files["startup.lua"] or SRC
  local fn = assert(load(SRC, "=store.lua", "t", env))
  W.co = coroutine.create(fn)
  local ok, err = coroutine.resume(W.co)
  W.started = ok and coroutine.status(W.co) == "suspended"
  W.err = err
  local n = 0
  function W.ask(from, req)
    n = n + 1
    req.n = n
    local before = #W.sent
    local okR, e = coroutine.resume(W.co, from, req)
    if not okR then W.err = e return nil end
    for i = before + 1, #W.sent do if W.sent[i].msg.re == n then return W.sent[i].msg end end
  end
  return W
end

-- 1) it starts, answers hello, belongs to the first base that writes
local W = world()
CHECK(W.started, "store.lua starts and waits for requests: " .. tostring(W.err))
local r = W.ask(5, { op = "hello" })
CHECK(r and r.ok and r.free and r.ver, "hello answered (free room, version)")
r = W.ask(5, { op = "put", name = "map/o0_0.dat", data = "M2\nV 0 0 abc\n" })
CHECK(r and r.ok, "a file is stored")
CHECK(W.files["store/map/o0_0.dat"] == "M2\nV 0 0 abc\n", "... in its store folder")
r = W.ask(6, { op = "get", names = { "map/o0_0.dat" } })
CHECK(r and not r.ok and tostring(r.err):find("belongs"), "another base is refused")
r = W.ask(5, { op = "get", names = { "map/o0_0.dat", "map/none.dat" } })
CHECK(r and r.ok and r.files["map/o0_0.dat"] == "M2\nV 0 0 abc\n" and r.files["map/none.dat"] == nil, "read back")
r = W.ask(5, { op = "list", dir = "map" })
CHECK(r and r.ok and r.files["o0_0.dat"], "listed")

-- 2) an EMPTY file (readAll gives nil in some versions) - the get used to crash the program
W.files["store/map/empty.dat"] = ""
r = W.ask(5, { op = "get", names = { "map/empty.dat", "map/o0_0.dat" } })
CHECK(r and r.ok and r.files["map/empty.dat"] == "" and r.files["map/o0_0.dat"], "an empty file does not stop it: " .. tostring(W.err))
CHECK(coroutine.status(W.co) == "suspended", "... still running")

-- 3) names outside its folder are refused
for _, bad in ipairs({ "../startup.lua", "/startup.lua", "map/../../x", "a b", "" }) do
  r = W.ask(5, { op = "put", name = bad, data = "x" })
  CHECK(r and not r.ok, "bad name refused: '" .. bad .. "'")
end
CHECK(W.files["startup.lua"] == SRC, "its own program untouched")

-- 4) a FULL disk: refused, the old file stays whole
W.cap = 0
for _, t in pairs(W.files) do W.cap = W.cap + #t end
W.cap = W.cap + 5000
r = W.ask(5, { op = "put", name = "map/o0_0.dat", data = string.rep("y", 4000) })
CHECK(r and not r.ok, "too big for the room left: refused")
CHECK(W.files["store/map/o0_0.dat"] == "M2\nV 0 0 abc\n", "... the old file is whole")

-- 5) a stop between "old one deleted" and "new one moved in": the .tmp is put back at the next start;
-- a .tmp next to a whole file (cut off while written) goes
local W2 = world({ ["store/map/o1_1.dat.tmp"] = "M2\nV 1 1 new\n", ["store/map/o2_2.dat"] = "old",
                   ["store/map/o2_2.dat.tmp"] = "half", ["store_owner.dat"] = "5" })
CHECK(W2.started, "starts with leftovers: " .. tostring(W2.err))
CHECK(W2.files["store/map/o1_1.dat"] == "M2\nV 1 1 new\n" and not W2.files["store/map/o1_1.dat.tmp"], "a lone .tmp is put back")
CHECK(W2.files["store/map/o2_2.dat"] == "old" and not W2.files["store/map/o2_2.dat.tmp"], "a .tmp next to its file is removed")
r = W2.ask(5, { op = "get", names = { "map/o1_1.dat" } })
CHECK(r and r.files["map/o1_1.dat"] == "M2\nV 1 1 new\n", "... and read back")

-- 6) one "get" answer stays under ~200 KB (the base asks again for the rest)
local W3 = world({ ["store_owner.dat"] = "5" })
local names = {}
for i = 1, 30 do
  W3.files["store/map/" .. i .. "_0.dat"] = string.rep("z", 20000)
  names[#names + 1] = "map/" .. i .. "_0.dat"
end
r = W3.ask(5, { op = "get", names = names })
local got = 0
for _ in pairs(r and r.files or {}) do got = got + 1 end
CHECK(got >= 9 and got < 30, "a big read comes in parts (" .. got .. " of 30)")
local inOrder = true
for i = 1, got do if not r.files[names[i]] then inOrder = false end end
CHECK(inOrder, "... the FIRST ones asked for (the base goes on with the rest)")

-- 7) an update: checked, installed, restart
local code = SRC .. "\n-- v2\n"
local function hash(str)
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end
r = W3.ask(5, { op = "upd", data = code, ver = "wrong" })
CHECK(r and not r.ok and W3.files["startup.lua"] == SRC, "a damaged update is refused")
r = W3.ask(5, { op = "upd", data = "this is not lua (", ver = hash("this is not lua (") })
CHECK(r and not r.ok and W3.files["startup.lua"] == SRC, "an update that does not compile is refused")
W3.ask(5, { op = "upd", data = code, ver = hash(code) })
CHECK(W3.files["startup.lua"] == code and W3.reboots >= 1, "a good update is installed and it restarts")

if FAILS > 0 then os.exit(1) end
print("store.lua: all checks passed")
