-- a voxel world + the turtle API, for running node.lua's real navigation
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
if SCEN == "maze" or SCEN == "maze2" then
  -- a comb of tall walls between start and target (TX=44): the planner has to
  -- weave through the gaps - nothing to climb over
  local function wall(x, z1, z2) for y = 50, 140 do for z = z1, z2 do SOLID[x .. "," .. y .. "," .. z] = "minecraft:stone" end end end
  wall(10, -30, 6) wall(20, -6, 30) wall(30, -30, 6)
  if SCEN == "maze2" then wall(38, -6, 30) for x = 10, 38 do for y = 50, 140 do SOLID[x .. "," .. y .. ",-31"] = "minecraft:stone" SOLID[x .. "," .. y .. ",31"] = "minecraft:stone" end end end
end
local pos = { x = 0, y = 0, z = 0 }
pos.y = ground(0, 0) + 1
local f = 3                             -- facing: 0 +z, 1 -x, 2 -z, 3 +x
local DX, DZ = { [0] = 0, [1] = -1, [2] = 0, [3] = 1 }, { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local fuel, moves, clock = 100000, 0, 0
local function try(nx, ny, nz)
  clock = clock + 0.4
  if solid(nx, ny, nz) or fuel < 1 then return false end
  pos.x, pos.y, pos.z = nx, ny, nz
  fuel, moves = fuel - 1, moves + 1
  if moves > 20000 then error("MOVE LIMIT") end
  return true
end
turtle = {
  forward = function() return try(pos.x + DX[f], pos.y, pos.z + DZ[f]) end,
  back = function() return try(pos.x - DX[f], pos.y, pos.z - DZ[f]) end,
  up = function() return try(pos.x, pos.y + 1, pos.z) end,
  down = function() return try(pos.x, pos.y - 1, pos.z) end,
  turnLeft = function() f = (f + 3) % 4 TURNS = (TURNS or 0) + 1 clock = clock + 0.4 return true end,
  turnRight = function() f = (f + 1) % 4 TURNS = (TURNS or 0) + 1 clock = clock + 0.4 return true end,
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
REALCLOCK = REALCLOCK or os.clock
os.clock = function() return clock end
os.startTimer = function() return 1 end
os.queueEvent = function() end
os.pullEvent = function(f) clock = clock + 0.05 return f end
sleep = function(t) clock = clock + (t or 0) end
shell = { getRunningProgram = function() return "startup.lua" end }
textutils = { serialize = function() return "{}" end, unserialize = function() return nil end }
rs = { getSides = function() return { "left", "right" } end }
peripheral = { getType = function(s) return s == "left" and "modem" or nil end, call = function(s, m) if m == "isWireless" then return true end end,
  getNames = function() return { "left" } end, isPresent = function(s) return s == "left" end, wrap = function() return {} end,
  hasType = function(s, t) return s == "left" and t == "modem" end, getMethods = function() return {} end, find = function() return nil end }
gps = { locate = function() return nil end }
-- the base: answers "need" with the cruise height (MAPKNOWN = the map knows the terrain)
local MAPKNOWN = (os.getenv("MAP") ~= "unknown")
rednet = { open = function() end, isOpen = function() return true end, lookup = function() return 1 end, host = function() end,
  receive = function() return nil end,
  send = function(id, m)
    if type(m) == "table" and m.t == "need" and MAPKNOWN then
      local top = -64
      for x = math.min(m.fx, m.tx), math.max(m.fx, m.tx), 2 do top = math.max(top, ground(x, m.fz) + 3) end
      for z = math.min(m.fz, m.tz), math.max(m.fz, m.tz), 2 do top = math.max(top, ground(m.tx, z) + 3) end
      immediate("know", { "", "", "none", 0, top })
    elseif type(m) == "table" and m.t == "need" then immediate("know", { "", "", "none", 0, "none" }) end
    return true end }
term = { clear = function() end, setCursorPos = function() end, write = function() end, getSize = function() return 39, 13 end,
  setTextColor = function() end, setBackgroundColor = function() end, isColor = function() return false end }
colors = setmetatable({}, { __index = function() return 1 end })
parallel = { waitForAny = function() end, waitForAll = function(...) for _, g in ipairs({ ... }) do g() end end }
print = function() end
assert(loadfile(NODE))()
immediate("setpos", { pos.x, pos.y, pos.z, "east" })
-- count the route planning (calls, cells in the routes, real CPU time)
local A0 = astar
PLANS, PLANLEN, PLANCPU = 0, 0, 0
astar = function(...)
  local t0 = REALCLOCK()
  local p, e = A0(...)
  PLANCPU = PLANCPU + (REALCLOCK() - t0)
  PLANS = PLANS + 1
  if p then PLANLEN = PLANLEN + #p end
  return p, e
end
if SCEN == "astar" then
  -- the planner alone: a maze in its memory, routes between far corners
  local function turnsOf(path, sx, sz)
    local n, last, px, pz = 0, nil, sx, sz
    for _, p in ipairs(path) do
      local dx, dz = p[1] - px, p[3] - pz
      if dx ~= 0 or dz ~= 0 then
        local d = dx .. "," .. dz
        if last and d ~= last then n = n + 1 end
        last = d
      end
      px, pz = p[1], p[3]
    end
    return n
  end
  local seed = 7
  local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
  local totalT, totalL, totalCpu, fails = 0, 0, 0, 0
  for run = 1, 6 do
    -- forget the last maze (the planner's memory is private: clear cell by cell)
    for x = -5, 45 do for z = -25, 25 do for y = 98, 102 do memClear(x, y, z) end end end
    -- random pillars and walls on one layer (the turtle stays at y 100)
    for x = -5, 45 do for z = -25, 25 do
      if rnd() < 0.18 then for y = 99, 101 do memWall(x, y, z, "hard", "scan") end end
    end end
    for x = -5, 45 do for z = -25, 25 do memWall(x, 102, z, "hard", "scan") memWall(x, 98, z, "hard", "scan") end end
    local t0 = REALCLOCK()
    local path, err = astar(0, 100, -20, 40, 100, 20)
    totalCpu = totalCpu + (REALCLOCK() - t0)
    if path then totalL, totalT = totalL + #path, totalT + turnsOf(path, 0, -20) else fails = fails + 1 io.stdout:write("  fail: " .. tostring(err) .. "\n") end
  end
  io.stdout:write(string.format("astar: 6 mazes  route cells %d  turns %d  failed %d  cpu %.2f s\n", totalL, totalT, fails, totalCpu))
  os.exit(0)
end
local tx, tz = tonumber(os.getenv("TX") or 300), tonumber(os.getenv("TZ") or 0)
local ty = ground(tx, tz) + 1
local ok, res, msg = xpcall(function() return runJob({ cmd = "goto", args = { tx, ty, tz } }) end, debug.traceback)
io.stdout:write(string.format("%-10s %-8s arrived %-5s moves %5d  turns %4d  game time %4d s  (%s)\n", SCEN, os.getenv("WHO") or "",
  tostring(ok and res and pos.x == tx and pos.z == tz), moves, TURNS or 0, math.floor(clock), tostring(ok and msg or res):sub(1, 400)))
io.stdout:write(string.format("           plans %d (route cells %d, cpu %.2f s)\n", PLANS, PLANLEN, PLANCPU))
