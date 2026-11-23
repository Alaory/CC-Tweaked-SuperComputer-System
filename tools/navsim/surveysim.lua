-- SURVEY IN CHAOS TERRAIN (not game code). The owner: "when a turtle goes through a path but gets stuck, the path
-- was changed (gravel / sand falling, amethyst growing, players placing blocks); the world is chaos - large
-- structures, modded blocks - don't rely on normal terrain". Runs node.lua's REAL survey job ("surveypts", the
-- base's batches) over a grid of scan spots in a voxel world with:
--   hills, forests (normal + huge modded trees, leaves block like any block), tall modded towers, ROOFS on pillars
--   (overhangs), ravines, and the WORLD CHANGING behind the turtle: blocks appear in cells it moved through
--   (CHANGE = chance per move).
-- usage: SEED=1 SPOTS=36 CHANGE=0.02 lua5.3 tools/navsim/surveysim.lua node.lua
-- prints: spots scanned, result, moves, game time, s per spot, fuel.
local NODE = arg[1]
local SEED = tonumber(os.getenv("SEED") or 1)
local NSPOTS = tonumber(os.getenv("SPOTS") or 36)
local CHANGE = tonumber(os.getenv("CHANGE") or 0.02)
local seed = SEED * 7919 + 13
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
local SOLID, AIR = {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function ground(x, z)
  return math.floor(70 + 6 * math.sin(x / 23) + 5 * math.cos(z / 17) + 3 * math.sin((x + z) / 9))
end
local function solid(x, y, z)
  local k = key(x, y, z)
  if SOLID[k] then return SOLID[k] end
  if AIR[k] then return nil end
  if y <= ground(x, z) then return "minecraft:stone" end
end
local function put(x, y, z, n) SOLID[key(x, y, z)] = n end
-- the area: spots on a grid of 17 from (8, 8); the world around it
local side = math.ceil(math.sqrt(NSPOTS))
local GAP = tonumber(os.getenv("GAP") or 17)         -- blocks between spots (> 48: every hop is a long trip)
local X1, X2, Z1, Z2 = -20, side * GAP + 20, -20, side * GAP + 20
local function clearSpawn(x, z) return math.abs(x) <= 3 and math.abs(z) <= 3 end
-- forests: normal trees and huge modded ones (leaves = a block like any other: no digging)
for x = X1, X2, 3 do
  for z = Z1, Z2, 3 do
    local r = rnd()
    if r < 0.18 and not clearSpawn(x, z) then
      local big = rnd() < 0.12
      local h = big and (18 + math.floor(rnd() * 14)) or (5 + math.floor(rnd() * 4))
      local g = ground(x, z)
      for y = g + 1, g + h do put(x, y, z, big and "biomesoplenty:redwood_log" or "minecraft:oak_log") end
      local R = big and 4 or 2
      for dx = -R, R do for dz = -R, R do for dy = -1, big and 3 or 1 do
        if math.abs(dx) + math.abs(dz) <= R + 1 and not (dx == 0 and dz == 0 and dy <= 0) then
          local k = key(x + dx, g + h + dy, z + dz)
          if not SOLID[k] then SOLID[k] = big and "biomesoplenty:redwood_leaves" or "minecraft:oak_leaves" end
        end
      end end end
    end
  end
end
-- modded towers (a 4x4 block 25-45 high) and ROOFS on pillars (an overhang: no way straight up underneath)
for _ = 1, math.floor((X2 - X1) * (Z2 - Z1) / 2500) do
  local x, z = X1 + math.floor(rnd() * (X2 - X1)), Z1 + math.floor(rnd() * (Z2 - Z1))
  if not (math.abs(x) < 12 and math.abs(z) < 12) then
    if rnd() < 0.5 then
      local g, h = ground(x, z), 25 + math.floor(rnd() * 20)
      for dx = 0, 3 do for dz = 0, 3 do for y = g - 2, g + h do put(x + dx, y, z + dz, "mekanism:steel_casing") end end end
    else
      local g = ground(x, z) + 7
      for dx = 0, 13 do for dz = 0, 13 do put(x + dx, g, z + dz, "create:andesite_casing") end end
      for _, c in ipairs({ { 0, 0 }, { 13, 0 }, { 0, 13 }, { 13, 13 } }) do
        for y = ground(x + c[1], z + c[2]), g do put(x + c[1], y, z + c[2], "create:andesite_casing") end
      end
    end
  end
end
-- a ravine across the area: 3 wide, 25 deep
local rz = math.floor(Z1 + (Z2 - Z1) * (0.3 + rnd() * 0.4))
for x = X1, X2 do for dz = 0, 2 do
  local g = ground(x, rz + dz)
  for y = g - 25, g do AIR[key(x, y, rz + dz)] = true SOLID[key(x, y, rz + dz)] = nil end
end end

-- the turtle API
local pos = { x = 0, y = ground(0, 0) + 1, z = 0 }
local f = 3
local DX, DZ = { [0] = 0, [1] = -1, [2] = 0, [3] = 1 }, { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local fuel, moves, clock, turns = 100000, 0, 0, 0
local recent = {}                        -- cells it moved through (the world changes there later)
local changed = 0
local function try(nx, ny, nz)
  clock = clock + 0.4
  if solid(nx, ny, nz) or fuel < 1 then return false end
  recent[#recent + 1] = { pos.x, pos.y, pos.z }
  if #recent > 400 then table.remove(recent, 1) end
  pos.x, pos.y, pos.z = nx, ny, nz
  fuel, moves = fuel - 1, moves + 1
  if moves > 60000 then error("MOVE LIMIT") end
  -- the world changes behind it: gravel falls / a player places a block / amethyst grows in a cell it used
  if CHANGE > 0 and #recent > 30 and rnd() < CHANGE then
    local c = recent[math.floor(rnd() * (#recent - 20)) + 1]
    if not (c[1] == pos.x and c[2] == pos.y and c[3] == pos.z) then
      local names = { "minecraft:gravel", "minecraft:sand", "minecraft:cobblestone", "minecraft:amethyst_cluster" }
      put(c[1], c[2], c[3], names[math.floor(rnd() * 4) + 1])
      changed = changed + 1
    end
  end
  return true
end
turtle = {
  forward = function() return try(pos.x + DX[f], pos.y, pos.z + DZ[f]) end,
  back = function() return try(pos.x - DX[f], pos.y, pos.z - DZ[f]) end,
  up = function() return try(pos.x, pos.y + 1, pos.z) end,
  down = function() return try(pos.x, pos.y - 1, pos.z) end,
  turnLeft = function() f = (f + 3) % 4 turns = turns + 1 clock = clock + 0.4 return true end,
  turnRight = function() f = (f + 1) % 4 turns = turns + 1 clock = clock + 0.4 return true end,
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
  combine = function(a, b) return a .. "/" .. b end, getDir = function() return "" end, list = function() return {} end,
  isDir = function() return false end, getFreeSpace = function() return 900000 end }
os.getComputerID = function() return 9 end
os.getComputerLabel = function() return "Sim" end
os.setComputerLabel = function() end
os.epoch = function() return 1700000000000 + math.floor(clock * 1000) end
REALCLOCK = REALCLOCK or os.clock
os.clock = function() return clock end
os.startTimer = function() return 1 end
os.queueEvent = function() end
os.pullEvent = function(fl) clock = clock + 0.05 return fl end
os.pullEventRaw = os.pullEvent
sleep = function(t) clock = clock + (t or 0) end
shell = { getRunningProgram = function() return "startup.lua" end }
textutils = { serialize = function() return "{}" end, unserialize = function() return nil end,
              serializeJSON = function() return "{}" end }
rs = { getSides = function() return { "left", "right" } end }
peripheral = { getType = function(s) return s == "left" and "modem" or nil end, call = function(s, m) if m == "isWireless" then return true end end,
  getNames = function() return { "left" } end, isPresent = function(s) return s == "left" end, wrap = function() return {} end,
  hasType = function(s, t) return s == "left" and t == "modem" end, getMethods = function() return {} end, find = function() return nil end }
gps = { locate = function() return nil end }
-- the base: the frontier is NOT mapped (MAP=known for a mapped area)
local MAPKNOWN = (os.getenv("MAP") == "known")
rednet = { open = function() end, isOpen = function() return true end, lookup = function() return 1 end, host = function() end,
  receive = function() return nil end,
  send = function(_, m)
    if type(m) == "table" and m.t == "need" then
      if MAPKNOWN then
        local top = -64
        for x = math.min(m.fx, m.tx), math.max(m.fx, m.tx), 2 do top = math.max(top, ground(x, m.fz) + 3) end
        for z = math.min(m.fz, m.tz), math.max(m.fz, m.tz), 2 do top = math.max(top, ground(m.tx, z) + 3) end
        immediate("know", { "", "", "none", 0, top })
      else immediate("know", { "", "", "none", 0, "none" }) end
    end
    return true end }
term = { clear = function() end, setCursorPos = function() end, write = function() end, getSize = function() return 39, 13 end,
  setTextColor = function() end, setBackgroundColor = function() end, isColor = function() return false end }
colors = setmetatable({}, { __index = function() return 1 end })
parallel = { waitForAny = function() end, waitForAll = function(...) for _, g in ipairs({ ... }) do g() end end }
print = function() end
assert(loadfile(NODE))()
immediate("setpos", { pos.x, pos.y, pos.z, "east" })
-- the Geo Scanner: every block in the cube (1 s of game time per scan)
local SCANS = 0
local SC = { scan = function(r)
  clock = clock + 1
  local out = {}
  for dx = -r, r do for dy = -r, r do for dz = -r, r do
    local n = solid(pos.x + dx, pos.y + dy, pos.z + dz)
    if n then out[#out + 1] = { x = dx, y = dy, z = dz, name = n } end
  end end end
  SCANS = SCANS + 1
  return out
end }
withScanner = function(fn) local ok, r = pcall(fn, SC) if ok then return r end return nil, r end
findItem = function(n) if tostring(n):find("geo_scanner", 1, true) then return 16 end return nil end
-- the spots (the base's batch)
local args = { 8 }
local n = 0
for i = 0, side - 1 do for j = 0, side - 1 do
  if n < NSPOTS then n = n + 1 args[#args + 1] = 8 + GAP * i args[#args + 1] = 8 + GAP * j end
end end
immediate("sethome", {})
local ok, res, msg = xpcall(function() return runJob({ cmd = "surveypts", args = args }) end, debug.traceback)
local hm0, hc0 = moves, clock
local okH, resH, msgH = xpcall(function() return runJob({ cmd = "home", args = {} }) end, debug.traceback)
HOMELINE = string.format("    home: %s moves %d  game %d s  (%s)", tostring(okH and resH), moves - hm0, math.floor(clock - hc0),
                         tostring(okH and msgH or resH):sub(1, 140))
io.stdout:write(string.format("seed %2d  %-6s scans %3d/%d  moves %6d  turns %5d  game %6d s  %5.1f s/spot  changed %3d  %s\n",
  SEED, os.getenv("WHO") or "", SCANS, NSPOTS, moves, turns, math.floor(clock), clock / math.max(1, SCANS), changed,
  tostring(ok and (tostring(res) .. " " .. tostring(msg)) or res):sub(1, 160)))
io.stdout:write(HOMELINE .. "\n")
