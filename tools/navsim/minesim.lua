-- Runs the real miner.lua on two simulated turtles (MINER + LOADER) and the
-- real base_mining.lua as the base, in a voxel world. Not game code.
--   lua5.3 tools/navsim/minesim.lua [hours] [scenario]
-- Checks: the miner never works outside the 3x3 chunks the loader keeps
-- loaded (chunkyTurtleRadius = 1), never digs a turtle / near the station,
-- unload trips deliver items, the loader follows.
local HOURS = tonumber(arg[1]) or 3
local SCEN = arg[2] or ""
local ROOT = (arg[0]:match("^(.*)/tools/navsim/") or ".") .. "/"

---------------------------------------------------------------- world
local T = 0                                 -- sim seconds
local W = {}                                -- ["x,y,z"] = name (changes)
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function hash(x, y, z)
  local h = (x * 73856093 + y * 19349663 + z * 83492791) % 1000003
  return h
end
local function natural(x, y, z)
  if y > 64 then return nil end
  if y <= -60 then return "minecraft:bedrock" end
  local h = hash(x, y, z)
  if h < 900 then return y < 0 and "minecraft:deepslate_iron_ore" or "minecraft:iron_ore" end
  if h < 1500 then return "minecraft:coal_ore" end
  if h < 1700 and y < 16 then return y < 0 and "minecraft:deepslate_diamond_ore" or "minecraft:diamond_ore" end
  if h < 2600 then return "minecraft:gravel" end
  if h < 3200 then return "minecraft:tuff" end
  return y < 0 and "minecraft:deepslate" or "minecraft:stone"
end
local function block(x, y, z)
  local v = W[key(x, y, z)]
  if v == false then return nil end
  if v ~= nil then return v end
  return natural(x, y, z)
end
local function setBlock(x, y, z, n) W[key(x, y, z)] = n or false end
local DROPS = {
  ["minecraft:iron_ore"] = { "minecraft:raw_iron", 3 }, ["minecraft:deepslate_iron_ore"] = { "minecraft:raw_iron", 3 },
  ["minecraft:coal_ore"] = { "minecraft:coal", 4 }, ["minecraft:diamond_ore"] = { "minecraft:diamond", 4 },
  ["minecraft:deepslate_diamond_ore"] = { "minecraft:diamond", 4 }, ["minecraft:stone"] = { "minecraft:cobblestone", 1 },
  ["minecraft:deepslate"] = { "minecraft:cobbled_deepslate", 1 }, ["minecraft:gravel"] = { "minecraft:gravel", 1 },
  ["minecraft:tuff"] = { "minecraft:tuff", 1 },
}
local FAIL = {}
local function fail(msg) FAIL[#FAIL + 1] = string.format("[%.0fs] %s", T, msg) end

local turtles = {}                          -- id -> unit
local STATION = { x = 0, y = 70, z = 0 }
local DUMP = { x = 1, y = 70, z = 0 }       -- the empty block in front of the station (Import Bus)
local delivered, busDrained = {}, 0
local function chunk(x) return math.floor(x / 16) end
local function loaded(x, z)
  if math.abs(chunk(x) - chunk(STATION.x)) <= 0 and math.abs(chunk(z) - chunk(STATION.z)) <= 0 then return true end
  for _, u in pairs(turtles) do
    if u.role == "loader" and math.abs(chunk(x) - chunk(u.pos.x)) <= 1 and math.abs(chunk(z) - chunk(u.pos.z)) <= 1 then
      return true
    end
  end
  return false
end
local function occupied(x, y, z)
  for _, u in pairs(turtles) do if u.pos.x == x and u.pos.y == y and u.pos.z == z then return u end end
end

---------------------------------------------------------------- scheduler
local queue = {}                            -- coroutines waiting: { co, wake, unit }
local function wait(dt)
  coroutine.yield(T + (dt or 0))
end

---------------------------------------------------------------- a turtle
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local function newTurtle(id, role, x, y, z, f, inv, left, right)
  local u = { id = id, role = role, pos = { x = x, y = y, z = z }, f = f, inv = inv, sel = 1,
              left = left, right = right, files = {}, inbox = {}, open = {}, points = {}, fuel = 50000 }
  turtles[id] = u
  setBlock(x, y, z, nil)
  return u
end
local function act(u)
  -- a turtle in an unloaded chunk does not run
  if not loaded(u.pos.x, u.pos.z) then
    fail(u.role .. " acting in an UNLOADED chunk at " .. u.pos.x .. " " .. u.pos.y .. " " .. u.pos.z)
  end
  wait(0.4)
end
local function front(u, d)
  local p = u.pos
  if d == "u" then return p.x, p.y + 1, p.z end
  if d == "d" then return p.x, p.y - 1, p.z end
  return p.x + DX[u.f], p.y, p.z + DZ[u.f]
end
local function addItem(u, name, count, extra)
  for i = 1, 16 do
    local it = u.inv[i]
    if it and it.name == name and not it.contents and not extra and it.count < 64 then
      local n = math.min(count, 64 - it.count)
      it.count, count = it.count + n, count - n
      if count == 0 then return true end
    end
  end
  for i = 1, 16 do
    if not u.inv[i] then
      u.inv[i] = { name = name, count = count, contents = extra }
      return true
    end
  end
  return false
end
local UPTYPE = { ["advancedperipherals:end_automata_core"] = "endAutomata",
                 ["computercraft:wireless_modem_advanced"] = "modem",
                 ["advancedperipherals:geo_scanner"] = "geoScanner",
                 ["advancedperipherals:chunk_controller"] = "chunky" }
local SHULKERS = {}                          -- ["x,y,z"] = { contents }

local function turtleApi(u)
  local t = {}
  local function mv(d)
    act(u)
    local x, y, z = front(u, d)
    if d == "b" then x, z = u.pos.x - DX[u.f], u.pos.z - DZ[u.f] end
    local b = block(x, y, z)
    if (b and not b:find("water")) or occupied(x, y, z) or u.fuel < 1 then return false, "Movement obstructed" end
    if not loaded(x, z) and not loaded(u.pos.x, u.pos.z) then return false, "Cannot leave loaded world" end
    u.pos.x, u.pos.y, u.pos.z = x, y, z
    u.fuel = u.fuel - 1
    -- gravel above falls
    local ab = block(x, y + 1, z)
    if ab == "minecraft:gravel" then end
    return true
  end
  t.forward = function() return mv("f") end
  t.back = function() return mv("b") end
  t.up = function() return mv("u") end
  t.down = function() return mv("d") end
  t.turnLeft = function() act(u) u.f = (u.f + 3) % 4 return true end
  t.turnRight = function() act(u) u.f = (u.f + 1) % 4 return true end
  local function det(d) local x, y, z = front(u, d) return block(x, y, z) ~= nil or occupied(x, y, z) ~= nil end
  t.detect = function() return det("f") end
  t.detectUp = function() return det("u") end
  t.detectDown = function() return det("d") end
  local function insp(d)
    local x, y, z = front(u, d)
    local o = occupied(x, y, z)
    if o then return true, { name = "computercraft:turtle_advanced" } end
    local b = block(x, y, z)
    if b then return true, { name = b } end
    return false, "No block to inspect"
  end
  t.inspect = function() return insp("f") end
  t.inspectUp = function() return insp("u") end
  t.inspectDown = function() return insp("d") end
  local function hasPick() return (u.left == "minecraft:netherite_pickaxe") or (u.right == "minecraft:netherite_pickaxe") end
  local function dig(d)
    act(u)
    if not hasPick() then return false, "No tool to dig with" end
    local x, y, z = front(u, d)
    if occupied(x, y, z) then fail(u.role .. " tried to DIG A TURTLE") return false end
    local b = block(x, y, z)
    if not b then return false, "Nothing to dig here" end
    if b == "minecraft:bedrock" then return false, "Cannot break unbreakable block" end
    local k = key(x, y, z)
    if not SHULKERS[k] and math.sqrt((x - STATION.x) ^ 2 + (z - STATION.z) ^ 2) < 24 then
      fail("dug NEAR THE STATION " .. x .. " " .. z)
    end
    if SHULKERS[k] then
      addItem(u, b, 1, SHULKERS[k])
      SHULKERS[k] = nil
      setBlock(x, y, z, nil)
      return true
    end
    setBlock(x, y, z, nil)
    local dr = DROPS[b] or { b, 1 }
    addItem(u, dr[1], dr[2])
    -- gravel above the dug block falls into it
    if block(x, y + 1, z) == "minecraft:gravel" then setBlock(x, y + 1, z, nil) setBlock(x, y, z, "minecraft:gravel") end
    return true
  end
  t.dig = function() return dig("f") end
  t.digUp = function() return dig("u") end
  t.digDown = function() return dig("d") end
  t.attack = function() act(u) return false end
  t.attackUp, t.attackDown = t.attack, t.attack
  t.getFuelLevel = function() return u.fuel end
  t.getFuelLimit = function() return 100000 end
  t.select = function(i) u.sel = i return true end
  t.getSelectedSlot = function() return u.sel end
  t.getItemCount = function(i) local it = u.inv[i or u.sel] return it and it.count or 0 end
  t.getItemDetail = function(i) local it = u.inv[i or u.sel] return it and { name = it.name, count = it.count } or nil end
  t.refuel = function(n)
    local it = u.inv[u.sel]
    if not it or not (it.name == "minecraft:coal" or it.name == "minecraft:coal_block") then return false end
    n = math.min(n or it.count, it.count)
    u.fuel = u.fuel + 80 * n
    it.count = it.count - n
    if it.count == 0 then u.inv[u.sel] = nil end
    return true
  end
  local function equip(side)
    act(u)
    local it = u.inv[u.sel]
    local old = u[side]
    u[side] = it and it.name or nil
    u.inv[u.sel] = old and { name = old, count = 1 } or nil
    if old and UPTYPE[old] == "modem" then u.open = {} end
    return true
  end
  t.equipLeft = function() return equip("left") end
  t.equipRight = function() return equip("right") end
  local function place(d)
    act(u)
    local it = u.inv[u.sel]
    local x, y, z = front(u, d)
    if not it or block(x, y, z) or occupied(x, y, z) then return false end
    if not it.name:find("shulker") then return false end
    setBlock(x, y, z, it.name)
    SHULKERS[key(x, y, z)] = it.contents or {}
    if math.abs(x - STATION.x) > 4 then
      FIELD = (FIELD or 0) + 1
      if block(x, y + 1, z) then fail("shulker placed UNDER A BLOCK at " .. x .. " " .. y .. " " .. z) end
    end
    u.inv[u.sel] = nil
    return true
  end
  t.place = function() return place("f") end
  t.placeUp = function() return place("u") end
  local function drop(d, n)
    act(u)
    local it = u.inv[u.sel]
    if not it then return false end
    n = math.min(n or it.count, it.count)
    local x, y, z = front(u, d)
    local sh = SHULKERS[key(x, y, z)]
    if sh then
      sh[it.name] = (sh[it.name] or 0) + n
    end
    it.count = it.count - n
    if it.count == 0 then u.inv[u.sel] = nil end
    return true
  end
  t.drop = function(n) return drop("f", n) end
  t.dropUp = function(n) return drop("u", n) end
  t.dropDown = function(n) return drop("d", n) end
  t.suckUp = function(n)
    act(u)
    local x, y, z = front(u, "u")
    local sh = SHULKERS[key(x, y, z)]
    if not sh then return false end
    for name, c in pairs(sh) do
      local take = math.min(c, n or 64)
      if addItem(u, name, take) then
        sh[name] = c - take
        if sh[name] == 0 then sh[name] = nil end
        return true
      end
      return false
    end
    return false
  end
  return t
end

local function peripheralApi(u)
  local P = {}
  local function upType(side)
    local it = (side == "left" and u.left) or (side == "right" and u.right)
    return it and UPTYPE[it]
  end
  local function frontInv(side)
    if side ~= "front" then return nil end
    local x, y, z = front(u, "f")
    return SHULKERS[key(x, y, z)]
  end
  P.getType = function(side) if frontInv(side) then return "inventory" end return upType(side) end
  P.hasType = function(side, ty)
    if frontInv(side) then return ty == "inventory" end
    local t = upType(side)
    return t ~= nil and (t == ty)
  end
  P.isPresent = function(side) return P.getType(side) ~= nil end
  P.getNames = function()
    local out = {}
    for _, s in ipairs({ "left", "right" }) do if upType(s) then out[#out + 1] = s end end
    return out
  end
  P.wrap = function(side)
    local inv = frontInv(side)
    if inv then
      return { list = function()
        local l, i = {}, 0
        for name, c in pairs(inv) do i = i + 1 l[i] = { name = name, count = c } end
        return l
      end }
    end
    local ty = upType(side)
    if ty == "endAutomata" then
      return {
        savePoint = function(n) u.points[n] = { x = u.pos.x, y = u.pos.y, z = u.pos.z } return true end,
        deletePoint = function(n) u.points[n] = nil return true end,
        getPoints = function() local l = {} for n in pairs(u.points) do l[#l + 1] = n end return l end,
        estimateWarpCost = function(n)
          local p = u.points[n]
          if not p then return nil, "no point" end
          return math.floor(math.sqrt((p.x - u.pos.x) ^ 2 + (p.y - u.pos.y) ^ 2 + (p.z - u.pos.z) ^ 2) / 4)
        end,
        warpToPoint = function(n)
          local p = u.points[n]
          if not p then return nil, "no point" end
          if not loaded(p.x, p.z) then return nil, "target not loaded" end
          if occupied(p.x, p.y, p.z) then return nil, "occupied" end
          act(u)
          u.fuel = u.fuel - math.floor(math.sqrt((p.x - u.pos.x) ^ 2 + (p.z - u.pos.z) ^ 2) / 4)
          u.pos.x, u.pos.y, u.pos.z = p.x, p.y, p.z
          u.warps = (u.warps or 0) + 1
          return true
        end,
      }
    elseif ty == "geoScanner" then
      return { scan = function(r)
        act(u)
        local out = {}
        for dx = -r, r do for dy = -r, r do for dz = -r, r do
          local b = block(u.pos.x + dx, u.pos.y + dy, u.pos.z + dz)
          if b then
            out[#out + 1] = { x = dx, y = dy, z = dz, name = b,
                              tags = b:find("_ore") and { "minecraft:block/c:ores" } or {} }
          end
        end end end
        return out
      end }
    end
  end
  P.call = function(side, m, ...) local w = P.wrap(side) return w[m](...) end
  return P
end

local BASE_ID = 0
local function deliver(from, to, msg, proto)
  local u = turtles[to]
  if to == BASE_ID then
    if proto == "basectl" and type(msg) == "table" and msg.mine then BASE_IN[#BASE_IN + 1] = { from, msg } end
    return
  end
  if u and next(u.open) then
    -- deep copy (messages are serialised in the game)
    u.inbox[#u.inbox + 1] = { from, textutils.unserialize(textutils.serialize(msg)), proto }
  end
end
local function rednetApi(u)
  local R = {}
  R.open = function(side) if u[side] and UPTYPE[u[side]] == "modem" then u.open[side] = true end end
  R.close = function() u.open = {} end
  R.isOpen = function(side) if side then return u.open[side] == true end return next(u.open) ~= nil end
  R.send = function(to, msg, proto) if next(u.open) then deliver(u.id, to, msg, proto) end return true end
  R.broadcast = function(msg, proto)
    if not next(u.open) then return end
    for id in pairs(turtles) do if id ~= u.id then deliver(u.id, id, msg, proto) end end
  end
  R.lookup = function() return BASE_ID end
  R.receive = function(proto, timeout)
    local t0 = T
    while true do
      for i, m in ipairs(u.inbox) do
        if not proto or m[3] == proto then table.remove(u.inbox, i) return m[1], m[2], m[3] end
      end
      if timeout and T - t0 >= timeout then return nil end
      wait(0.1)
    end
  end
  return R
end

---------------------------------------------------------------- environments
BASE_IN = {}
local function envFor(u)
  local env = {}
  local files = u.files
  env.fs = {
    exists = function(p) return files[p] ~= nil end,
    open = function(p, mode)
      if mode == "r" then
        if not files[p] then return nil end
        local data = files[p]
        return { readAll = function() return data end, close = function() end }
      end
      local buf = {}
      return { write = function(s) buf[#buf + 1] = s end, close = function() files[p] = table.concat(buf) end }
    end,
    delete = function(p) files[p] = nil end,
    move = function(a, b) files[b] = files[a] files[a] = nil end,
  }
  env.os = {
    epoch = function() return 1700000000000 + math.floor(T * 1000) end,
    clock = function() return T end,
    time = function() return 12 end,
    getComputerLabel = function() return (u.role == "miner" and "Miner " or "Loader ") .. u.id end,
    setComputerLabel = function() end,
    getComputerID = function() return u.id end,
    reboot = function() error("REBOOT") end,
  }
  env.sleep = function(s) wait(s or 0) end
  env.turtle = turtleApi(u)
  env.peripheral = peripheralApi(u)
  env.rednet = rednetApi(u)
  env.term = { clear = function() end, setCursorPos = function() end, getSize = function() return 39, 13 end,
               getCursorPos = function() return 1, 1 end, clearLine = function() end, write = function() end }
  env.textutils = { formatTime = function() return "12:00" end, serialize = textutils.serialize, unserialize = textutils.unserialize }
  env.print = function(...) local t = {} for i, v in ipairs({ ... }) do t[i] = tostring(v) end u.lastPrint = table.concat(t, " ") end
  env.printError = env.print
  env.write = function() end
  env.read = function() return "" end
  env.shell = { getRunningProgram = function() return "miner.lua" end }
  setmetatable(env, { __index = _G })
  return env
end

---------------------------------------------------------------- textutils (lua5.3)
textutils = {}
local function ser(v, ind)
  local t = type(v)
  if t == "table" then
    local parts = {}
    for k, val in pairs(v) do
      local ks = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
      parts[#parts + 1] = ks .. "=" .. ser(val)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return string.format("%q", v)
  else return tostring(v) end
end
textutils.serialize = ser
textutils.unserialize = function(s)
  local f = load("return " .. s, "u", "t", {})
  if not f then return nil end
  local ok, v = pcall(f)
  return ok and v or nil
end

---------------------------------------------------------------- the two turtles
local MINER, LOADER = 11, 12
local KEY = "test-key"
local m = newTurtle(MINER, "miner", 100, 40, 0, 1, {
  [1] = { name = "computercraft:wireless_modem_advanced", count = 1 },
  [2] = { name = "advancedperipherals:geo_scanner", count = 1 },
  [3] = { name = "sophisticatedstorage:netherite_shulker_box", count = 1, contents = {} },
  [4] = { name = "minecraft:coal", count = 32 },
}, "advancedperipherals:end_automata_core", "minecraft:netherite_pickaxe")
if SCEN == "corein" then
  -- the core in the inventory, not equipped (seen in game)
  m.left = nil
  m.inv[6] = { name = "advancedperipherals:end_automata_core", count = 1 }
end
if SCEN == "modemon" then
  -- the modem already equipped at start (closed, like after any restart)
  m.left, m.right = "computercraft:wireless_modem_advanced", "advancedperipherals:end_automata_core"
  m.inv[1] = { name = "minecraft:netherite_pickaxe", count = 1 }
end
if SCEN == "nofuel" then m.fuel = 0 m.inv[4] = nil end
if SCEN == "full" then
  for i = 5, 13 do m.inv[i] = { name = "minecraft:torch", count = 64 } end
end
if SCEN == "direct" then
  setBlock(DUMP.x, DUMP.y, DUMP.z, "ae2:interface")
  SHULKERS[key(DUMP.x, DUMP.y, DUMP.z)] = {}
end
local l = newTurtle(LOADER, "loader", 99, 40, 0, 1, {},
  "advancedperipherals:chunk_controller", "computercraft:wireless_modem_advanced")
-- the station: miner was set up there (point saved, station known)
m.points.station = { x = STATION.x, y = STATION.y, z = STATION.z }
setBlock(STATION.x, STATION.y, STATION.z, nil)
setBlock(DUMP.x, DUMP.y, DUMP.z, nil)
m.files.miner_state = textutils.serialize({ role = "miner", key = KEY, dim = "overworld",
  pos = { x = 100, y = 40, z = 0, f = 1 }, station = { x = STATION.x, y = STATION.y, z = STATION.z, f = 1 } })
l.files.miner_state = textutils.serialize({ role = "loader", key = KEY, dim = "overworld",
  pos = { x = 99, y = 40, z = 0, f = 1 } })

local SRC = io.open(ROOT .. "miner.lua"):read("a")
local cos = {}
for _, u in ipairs({ m, l }) do
  local env = envFor(u)
  local fn = assert(load(SRC, "miner.lua", "t", env))
  cos[#cos + 1] = { co = coroutine.create(fn), wake = 0, u = u }
end

---------------------------------------------------------------- the base (real base_mining.lua)
CONFIG = { turtles = { key = KEY }, mining = { rowLength = 3, dumpEvery = 900, noMine = 64,
           want = SCEN == "want" and { "minecraft:tuff" } or nil } }
state = { tOut = {}, tLastN = 0 }
C = setmetatable({}, { __index = function(_, k) return k end })
local NOTES = {}
function pushNote(kind, msg) NOTES[#NOTES + 1] = kind .. ": " .. msg end
function sysLog() end
function saveFileSafe() return true end
os.queueEvent = function() end
TT = { ago = function() return "?" end }
local nsrc = io.open(ROOT .. "base_turtles.lua"):read("a")
local a = nsrc:find("function TT.sign", 1, true)
local b = nsrc:find("\n%-%- a wireless or ender modem", a)
assert(load(nsrc:sub(a, b)))()
fs = { exists = function() return false end }
assert(loadfile(ROOT .. "base_mining.lua"))()
local realClock = os.clock
os.clock = function() return T end
os.epoch = function() return 1700000000000 + math.floor(T * 1000) end

---------------------------------------------------------------- run
local started = false
local lastLog = 0
local maxT = HOURS * 3600
while T < maxT do
  -- base: handle reports, send queued commands
  while #BASE_IN > 0 do
    local x = table.remove(BASE_IN, 1)
    local mm = x[2]
    if mm.sig == TT.sign(KEY, mm.t, mm.n) then MINE.receive(x[1], mm) end
  end
  while #state.tOut > 0 do
    local o = table.remove(state.tOut, 1)
    deliver(BASE_ID, o.id, o.msg, "basectl")
  end
  if not started and MINE.units[MINER] and MINE.units[MINER].partner then
    started = true
    MINE.cmd(MINER, "start", {})
  end
  -- the Import Bus drains the shulker in front of the station
  local sh = SHULKERS[key(DUMP.x, DUMP.y, DUMP.z)]
  if sh then
    for name, c in pairs(sh) do
      local n = math.min(c, 200)
      sh[name] = c - n
      if sh[name] == 0 then sh[name] = nil end
      delivered[name] = (delivered[name] or 0) + n
      break
    end
  end
  -- scenario reboot: the miner's program restarts (server restart / chunk unload)
  if SCEN == "reboot" and not REBOOTED and T > 2400 then
    REBOOTED = true
    for _, c in ipairs(cos) do
      if c.u.role == "miner" then
        c.u.open = {}                          -- a restart closes the modems
        c.co = coroutine.create(assert(load(SRC, "miner.lua", "t", envFor(c.u))))
        c.wake = T + 5
        io.write("** miner rebooted at " .. c.u.pos.x .. " " .. c.u.pos.y .. " " .. c.u.pos.z .. "\n")
      end
    end
  end
  -- next coroutine to run
  table.sort(cos, function(p, q) return p.wake < q.wake end)
  local c = cos[1]
  if c.wake > T then T = c.wake end
  if coroutine.status(c.co) == "dead" then fail(c.u.role .. " program ENDED") break end
  local ok, w = coroutine.resume(c.co)
  if not ok then fail(c.u.role .. " CRASHED: " .. tostring(w)) break end
  c.wake = tonumber(w) or T
  if T - lastLog > 600 then
    lastLog = T
    local mu = MINE.units[MINER]
    io.write(string.format("t=%5.0fmin miner %s | loader %s\n", T / 60,
      mu and tostring(mu.task) or "?", MINE.units[LOADER] and tostring(MINE.units[LOADER].task) or "?"))
  end
  if #FAIL > 5 then break end
end

local mu = MINE.units[MINER]
print("---")
print("miner pos", m.pos.x, m.pos.y, m.pos.z, "fuel", m.fuel, "warps", m.warps or 0)
print("loader pos", l.pos.x, l.pos.y, l.pos.z)
print("chunk index", mu and mu.ci, "stats", mu and mu.stats and textutils.serialize(mu.stats))
print("delivered by the bus:", textutils.serialize(delivered))
print("base says delivered:", mu and textutils.serialize(mu.got))
print("in shulker:", mu and textutils.serialize(mu.carry))
print("shulker used in the field:", FIELD or 0)
for _, n in ipairs(NOTES) do print("NOTE", n) end
if mu then print("base shows:", MINE.status(mu)) end
for _, e in ipairs(mu and mu.log or {}) do print("LOG", e.msg) end
if #FAIL > 0 then
  print("FAILURES:")
  for _, f in ipairs(FAIL) do print("  " .. f) end
  os.exit(1)
end
print("OK")
