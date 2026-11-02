-- STOP test: node.lua with real coroutines/events (listener, worker, heartbeat); a STOP is sent at STOPAT s
-- usage: lua world.lua <node.lua> <scenario>
local NODE, SCEN = arg[1], arg[2]
local SOLID = {}                       -- extra blocks ["x,y,z"] = name
local AIR = {}                         -- holes in the terrain
local function ground(x, z)            -- rolling hills, 64..78
  return math.floor(70 + 4 * math.sin(x / 23) + 3 * math.cos(z / 17))
end
local function solid(x, y, z)
  local k = x .. "," .. y .. "," .. z
  if SOLID[k] then return SOLID[k] end
  if AIR[k] then return nil end
  if y <= ground(x, z) then return "minecraft:stone" end
end
-- scenarios
if SCEN == "pocket" then
  -- a U-shaped cliff 40 high, open towards the turtle: walking straight east runs into it
  for y = 60, 115 do
    for z = -6, 6 do SOLID[(30) .. "," .. y .. "," .. z] = "minecraft:stone" end      -- the back wall
    for x = 18, 30 do SOLID[x .. "," .. y .. ",-6"] = "minecraft:stone" SOLID[x .. "," .. y .. ",6"] = "minecraft:stone" end
  end
end
if SCEN == "wall" then
  -- a long wall: 120 wide, up to Y 130 - too wide to plan around nearby
  for y = 55, 130 do for z = -60, 60 do SOLID["30," .. y .. "," .. z] = "minecraft:stone" end end
end
local pos = { x = 0, y = 0, z = 0 }
pos.y = ground(0, 0) + 1
local f = 3                             -- facing: 0 +z, 1 -x, 2 -z, 3 +x
local DX, DZ = { [0] = 0, [1] = -1, [2] = 0, [3] = 1 }, { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local fuel, moves, clock = 100000, 0, 0
local waitTicks
local function try(nx, ny, nz)
  local okm = not (solid(nx, ny, nz) or fuel < 1)
  if okm then pos.x, pos.y, pos.z = nx, ny, nz fuel, moves = fuel - 1, moves + 1 end
  waitTicks(0.4)            -- the move happened; the answer comes later (like the game)
  return okm
end
turtle = {
  forward = function() return try(pos.x + DX[f], pos.y, pos.z + DZ[f]) end,
  back = function() return try(pos.x - DX[f], pos.y, pos.z - DZ[f]) end,
  up = function() return try(pos.x, pos.y + 1, pos.z) end,
  down = function() return try(pos.x, pos.y - 1, pos.z) end,
  turnLeft = function() f = (f + 3) % 4 waitTicks(0.4) return true end,
  turnRight = function() f = (f + 1) % 4 waitTicks(0.4) return true end,
  detect = function() return solid(pos.x + DX[f], pos.y, pos.z + DZ[f]) ~= nil end,
  detectUp = function() return solid(pos.x, pos.y + 1, pos.z) ~= nil end,
  detectDown = function() return solid(pos.x, pos.y - 1, pos.z) ~= nil end,
  inspect = function() local n = solid(pos.x + DX[f], pos.y, pos.z + DZ[f]) if n then return true, { name = n } end return false end,
  inspectUp = function() local n = solid(pos.x, pos.y + 1, pos.z) if n then return true, { name = n } end return false end,
  inspectDown = function() local n = solid(pos.x, pos.y - 1, pos.z) if n then return true, { name = n } end return false end,
  dig = function() return false end, digUp = function() return false end, digDown = function() return false end,
  getFuelLevel = function() return fuel end, getFuelLimit = function() return 100000 end,
  getItemDetail = function() return nil end, getItemCount = function() return 0 end, getSelectedSlot = function() return 1 end,
  select = function() return true end, refuel = function() return false end, getItemSpace = function() return 64 end,
  equipLeft = function() return false end, equipRight = function() return false end,
}
local files = {}
if os.getenv("LOADF") then files = dofile(os.getenv("LOADF")) end
fs = { exists = function(p) return files[p] ~= nil end,
  open = function(p, m) if m == "r" then local t = files[p] if not t then return nil end local done = false
      return { readAll = function() return t end, readLine = function() if done then return nil end done = true return t end, close = function() end } end
    local b = {} return { write = function(s) b[#b + 1] = s end, writeLine = function(s) b[#b + 1] = s end, close = function() files[p] = table.concat(b) end, flush = function() end } end,
  delete = function(p) files[p] = nil end, copy = function() end, move = function() end, getSize = function() return 0 end,
  combine = function(a, b) return a .. "/" .. b end, getDir = function() return "" end, list = function() return {} end, isDir = function() return false end }
os.getComputerID = function() return 9 end
os.getComputerLabel = function() return "Sim" end
os.setComputerLabel = function() end
os.epoch = function() return 1700000000000 + math.floor(clock * 1000) end
os.clock = function() return clock end

-- real events + coroutines
local timers, tid, queue = {}, 0, {}
os.startTimer = function(t) tid = tid + 1 timers[tid] = clock + (t or 0) return tid end
os.queueEvent = function(...) queue[#queue + 1] = table.pack(...) end
os.pullEventRaw = function(f) return coroutine.yield(f) end
os.pullEvent = function(f)
  local e = table.pack(coroutine.yield(f))
  if e[1] == "terminate" then error("Terminated", 0) end
  return table.unpack(e, 1, e.n)
end
sleep = function(t) local id = os.startTimer(t) repeat local _, i = os.pullEvent("timer") until i == id end
waitTicks = function(t) sleep(t) end
-- CC's parallel
local function runCos(cos, any)
  local filters = {}
  local ev = { n = 0 }
  while true do
    for i, co in pairs(cos) do
      if filters[co] == nil or filters[co] == ev[1] or ev[1] == "terminate" then
        local r = table.pack(coroutine.resume(co, table.unpack(ev, 1, ev.n)))
        if not r[1] then error(r[2], 0) end
        filters[co] = r[2]
        if coroutine.status(co) == "dead" then
          if any then return end
          cos[i] = nil
        end
      end
    end
    if not any and next(cos) == nil then return end
    ev = table.pack(os.pullEventRaw())
  end
end
parallel = {
  waitForAny = function(...) local c = {} for i, f in ipairs({ ... }) do c[i] = coroutine.create(f) end runCos(c, true) end,
  waitForAll = function(...) local c = {} for i, f in ipairs({ ... }) do c[i] = coroutine.create(f) end runCos(c, false) end }
os.getComputerID = function() return 9 end
os.getComputerLabel = function() return "Sim" end
os.setComputerLabel = function() end
os.epoch = function() return 1700000000000 + math.floor(clock * 1000) end
os.clock = function() return clock end
os.reboot = function() REBOOTED = clock error("REBOOT", 0) end
shell = { getRunningProgram = function() return "startup.lua" end }

local function ser(v)
  if type(v) == "table" then local o = {} for k, x in pairs(v) do o[#o + 1] = "[" .. ser(k) .. "]=" .. ser(x) end return "{" .. table.concat(o, ",") .. "}" end
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end
textutils = { serialize = ser, unserialize = function(t) local f = load("return " .. (t or "")) if not f then return nil end local ok, r = pcall(f) return ok and r or nil end }

rs = { getSides = function() return { "left", "right" } end }
peripheral = { getType = function(s) return s == "left" and "modem" or nil end, call = function(s, m) if m == "isWireless" then return true end end,
  getNames = function() return { "left" } end, isPresent = function(s) return s == "left" end, wrap = function() return {} end,
  hasType = function(s, t) return s == "left" and t == "modem" end, getMethods = function() return {} end, find = function() return nil end }
gps = { locate = function() return nil end }
local SENT = {}
KEY, PROTO = "change-me", "basectl"
local LASTTASK
rednet = { open = function() end, isOpen = function() return true end, lookup = function() return 1 end, host = function() end,
  receive = function(proto) while true do local _, id, m, p = os.pullEvent("rednet_message") if p == proto then return id, m end end end,
  send = function(id, m) if type(m) == "table" and (m.t == "result") then SENT[#SENT + 1] = string.format("%5.1f result %s %s %s", clock, tostring(m.cmd), tostring(m.ok), tostring(m.msg)) end
    if type(m) == "table" and m.task then LASTTASK = m.task end
    if type(m) == "table" and m.t == "need" then os.queueEvent("rednet_message", 1, { t = "x" }, "none") end return true end }
term = { clear = function() end, setCursorPos = function() end, write = function() end, getSize = function() return 39, 13 end,
  setTextColor = function() end, setBackgroundColor = function() end, isColor = function() return false end }
colors = setmetatable({}, { __index = function() return 1 end })
print = function() end
printError = function() end
local MODE = os.getenv("MODE") or "goto"
local STOPAT = tonumber(os.getenv("STOPAT") or 15)
local ENDAT = tonumber(os.getenv("ENDAT") or 60)
if os.getenv("POS") then local a,b,c = os.getenv("POS"):match("(%-?%d+) (%-?%d+) (%-?%d+)") pos.x,pos.y,pos.z = tonumber(a),tonumber(b),tonumber(c) end
local N = 0
local function cmd(c, a)
  N = N + 1
  local m = { t = "cmd", n = N, cmd = c, args = a }
  m.sig = sign(KEY, "cmd", N, c, a)
  os.queueEvent("rednet_message", 1, m, PROTO)
end
-- the driver: the turtle program is one coroutine, events go to it in time order
local main = coroutine.create(function()
  local realWFA = parallel.waitForAny
  local first = true
  parallel.waitForAny = function(...)
    if first then
      first = false
      if MODE == "crash" then trailSave = function() error("test crash in trailSave") end end
      if MODE == "badcmd" then local orig = immediate immediate = function(c, a) if c == "ping" then error("boom in ping") end return orig(c, a) end end
      if MODE == "deaf" then
        -- a job that never looks at the STOP flag
        runJob = function() task = "deaf loop" while true do if not fwd() then right() end end end
      end
    end
    return realWFA(...)
  end
  assert(loadfile(NODE))()
end)
local plan = {}
if MODE ~= "reload" then plan[#plan + 1] = { 1, function() immediate("setpos", { pos.x, pos.y, pos.z, "east" }) cmd(MODE == "deaf" and "home" or "goto", { 200, ground(200, 0) + 1, 0 }) end } end
if MODE == "reload" then N = 1000 end
if MODE == "badcmd" then plan[#plan + 1] = { 5, function() cmd("ping", {}) end } plan[#plan + 1] = { 8, function() cmd("move", { "up", 1 }) end } end
if STOPAT > 0 then plan[#plan + 1] = { STOPAT, function() cmd("stop", {}) end } end
-- AGAIN=<s>: a new job after the STOP (like a survey batch for a stopped turtle)
if os.getenv("AGAIN") then plan[#plan + 1] = { tonumber(os.getenv("AGAIN")), function() cmd("goto", { 40, ground(40, 0) + 1, 0 }) end } end
local filter
local r = { coroutine.resume(main) } filter = r[2]
while clock < ENDAT do
  if plan[1] and clock >= plan[1][1] then table.remove(plan, 1)[2]() end
  local ev = table.remove(queue, 1)
  if not ev then
    local best, bi
    for i, t in pairs(timers) do if not best or t < best then best, bi = t, i end end
    local nextPlan = plan[1] and plan[1][1]
    if nextPlan and (not best or nextPlan < best) then clock = nextPlan
    elseif best then clock = math.max(clock, best) timers[bi] = nil ev = { "timer", bi, n = 2 }
    else break end
  end
  if ev and (filter == nil or filter == ev[1]) then
    r = { coroutine.resume(main, table.unpack(ev, 1, ev.n)) }
    if not r[1] then print = _G.print io.stdout:write("CRASH ", tostring(r[2]), "\n") break end
    filter = r[2]
  end
end
if os.getenv("SAVEF") then local h = io.open(os.getenv("SAVEF"), "w") h:write("return " .. ser(files)) h:close() end
if MODE == "badcmd" then end
io.stdout:write("rebooted at: " .. tostring(REBOOTED) .. "  crash file: " .. tostring(files["node_crash"]) .. "\n")
for _, l in ipairs(SENT) do io.stdout:write(l, "\n") end
io.stdout:write(string.format("end t=%.1f task=%s real pos %d %d %d  saved %s  moves %d\n", clock, tostring(LASTTASK),
  pos.x, pos.y, pos.z, fmt(), moves))
