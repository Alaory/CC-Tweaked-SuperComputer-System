--[[
  MINING TEAM turtle for a mining dimension (e.g. Just Another Mining
  Dimension). Two turtles work together:

    MINER   End Automata Core equipped (stays on) + a pickaxe on the other side.
            Carries: Ender Modem, Geo Scanner, a (netherite) shulker box.
            The pickaxe, modem and Geo Scanner take turns on the free side.
    LOADER  Chunky upgrade + Ender Modem. Keeps the miner's area loaded and
            follows it through the tunnel it digs. It never digs.

  NEEDS the Advanced Peripherals server config  chunkyTurtleRadius = 1
  (config/advancedperipherals/peripherals.toml): the loader then keeps 3x3
  chunks loaded, so the miner can work in the chunk next to it.

  The miner works one chunk at a time, in rows of CONFIG.rowLength chunks
  forward from where it starts (the way it faces), each next row to its right.
  In every chunk it scans layers (Y = start height, then every 17 blocks down)
  with the Geo Scanner and digs only ORES (and the blocks in CONFIG.want);
  stone, dirt ... are thrown away (CONFIG.junk). Full -> everything goes into
  the shulker (placed, filled, picked up again). Every CONFIG.dumpEvery seconds
  it teleports to the UNLOAD STATION (End Automata Core), empties itself and
  the shulker there, and teleports back.

  Unload station (in the mining dimension, near your base there; that chunk
  must stay loaded): the miner stands on it, facing either
    * an EMPTY block with air above it and an AE2 Import Bus touching it
      (the shulker is put there and the bus empties it), or
    * an inventory (ME Interface, linked chest ...) - then the shulker is put
      ABOVE the miner (keep 2 blocks of air above the station).

  Install: copy this file onto both turtles and run  miner  - it asks a few
  questions (role, key, position, facing) and starts by itself from then on.
    miner setup     ask everything again
    miner here      the turtle was moved: type its new position
    miner station   (miner) THIS spot is the unload station
]]

CONFIG = {
  protocol   = "basectl",     -- = CONFIG.turtles.protocol on the base
  baseName   = "base",        -- = CONFIG.turtles.hostname on the base
  team       = "basemine",    -- miner <-> loader
  dumpEvery  = 600,           -- s between trips to the unload station (base setting)
  rowLength  = 16,            -- chunks per row (base setting)
  noMine     = 64,            -- no ore mining within this many blocks of the station (base setting)
  noDig      = 24,            -- never dig at all this close to the station
  minY       = -56,           -- lowest layer centre (bedrock below)
  layerStep  = 17,
  scanR      = 8,             -- Geo Scanner radius (8 = free)
  checkIn    = 30,            -- s between reports to the base (the modem is swapped in)
  lowFuel    = 2000,
  fuelTarget = 20000,
  keepCoal   = 64,            -- coal kept for fuel, the rest is delivered
  wantMax    = 64,            -- max blocks of a CONFIG.want type per layer
  -- items thrown away (exact names; "*x" = ends in x)
  junk = { "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate",
           "minecraft:dirt", "minecraft:gravel", "minecraft:sand", "minecraft:red_sand", "minecraft:andesite",
           "minecraft:diorite", "minecraft:granite", "minecraft:tuff", "minecraft:calcite",
           "minecraft:netherrack", "minecraft:basalt", "minecraft:smooth_basalt", "minecraft:blackstone",
           "minecraft:end_stone", "minecraft:dripstone_block", "minecraft:pointed_dripstone",
           "minecraft:rooted_dirt", "minecraft:mud", "minecraft:soul_sand", "minecraft:soul_soil",
           "minecraft:moss_block", "minecraft:clay", "minecraft:flint" },
  -- blocks to go and dig besides ores (stone types you need) - set on the base
  want = {},
  ores = { "*_ore", "minecraft:ancient_debris" },
  -- never dug (turtles, storage, AE2 ...)
  protect = { "computercraft:*", "*shulker*", "ae2:*", "*chest*", "*barrel*", "sophisticatedstorage:*",
              "*spawner*", "minecraft:bedrock", "*interface*", "*drive*" },
}

STATE_FILE = "miner_state"
MYVER = "m1"
DX = { [0] = 0, 1, 0, -1 }
DZ = { [0] = -1, 0, 1, 0 }
FNAME = { [0] = "north", "east", "south", "west" }
NOTES = {}
S = {}
task = "starting"
LAST_CHECK = -1000
LAST_STATUS = -1000
ARRIVED = nil
DUMP_NOW = false
STASHING = false
lastN = 0

---------------------------------------------------------------------- state
function now() return math.floor(os.epoch("utc") / 1000) end
function save()
  local h = fs.open(STATE_FILE .. ".tmp", "w")
  if not h then return end
  local ok = pcall(function() h.write(textutils.serialize(S)) end)
  h.close()
  if ok then
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    fs.move(STATE_FILE .. ".tmp", STATE_FILE)
  end
end
function loadState()
  if fs.exists(STATE_FILE) then
    local h = fs.open(STATE_FILE, "r")
    local t = textutils.unserialize(h.readAll() or "")
    h.close()
    if type(t) == "table" then S = t end
  end
  S.stats = S.stats or { dug = 0, ores = 0, dumps = 0 }
  S.carry = S.carry or {}
  S.got = S.got or {}
  -- settings from the base
  for k, v in pairs(S.cfg or {}) do CONFIG[k] = v end
end
function note(msg)
  print(msg)
  NOTES[#NOTES + 1] = msg
  while #NOTES > 8 do table.remove(NOTES, 1) end
end
function setTask(t)
  task = t
end

-- name patterns: exact, after the colon, "*x" ends in, "x*" starts with, "*x*" contains
function match(name, list)
  name = tostring(name or "")
  local short = name:match(":(.+)$") or name
  for _, p in ipairs(list or {}) do
    local a, z = p:sub(1, 1) == "*", p:sub(-1) == "*"
    if a and z then
      if name:find(p:sub(2, -2), 1, true) then return true end
    elseif a then
      local s = p:sub(2)
      if name:sub(-#s) == s then return true end
    elseif z then
      local s = p:sub(1, -2)
      if name:sub(1, #s) == s then return true end
    elseif p == name or p == short then
      return true
    end
  end
  return false
end
function isProtected(name) return match(name, CONFIG.protect) end
function isLiquid(name) return match(name, { "*water*", "*lava*" }) end
TOOLS = { "pickaxe", "modem", "geo_scanner", "geoscanner", "shulker", "automata", "chunk" }
function isTool(name) return match(name, { "*pickaxe*", "*modem*", "*geo_scanner*", "*geoscanner*", "*shulker*",
                                            "*automata*", "*chunk*" }) end
function isCoal(name) return name == "minecraft:coal" or name == "minecraft:charcoal" or name == "minecraft:coal_block" end
function isJunk(name)
  if match(name, CONFIG.want) or match(name, CONFIG.keep or {}) then return false end
  return match(name, CONFIG.junk)
end
function isLoot(name) return not isTool(name) and not isJunk(name) end

---------------------------------------------------------------------- messages
function sign(key, t, n, cmd, args)
  local parts = {}
  for i, v in ipairs(args or {}) do parts[i] = tostring(v) end
  local str = key .. "|" .. tostring(t) .. "|" .. tostring(n) .. "|" .. tostring(cmd or "") ..
              "|" .. table.concat(parts, ",")
  local h1, h2 = 5381, 52711
  for i = 1, #str do
    local c = str:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c * 7 + i) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end
function nextN()
  local n = os.epoch("utc")
  if n <= lastN then n = lastN + 1 end
  lastN = n
  return n
end
function modemSide()
  for _, side in ipairs({ "left", "right" }) do
    if peripheral.hasType(side, "modem") then return side end
  end
end
function baseId()
  if S.baseId then return S.baseId end
  local ok, id = pcall(rednet.lookup, CONFIG.protocol, CONFIG.baseName)
  if ok and id then S.baseId = id end
  return S.baseId
end
function topN(t, n)
  local list = {}
  for k, v in pairs(t or {}) do list[#list + 1] = { k, v } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local out = {}
  for i = 1, math.min(n, #list) do out[list[i][1]] = list[i][2] end
  return out
end
-- the bottom line of the turtle's screen: can it reach the base?
function showLink(msg)
  LINK = msg
  local okS, w, h = pcall(term.getSize)
  if not okS or not h then return end
  local x, y = term.getCursorPos()
  term.setCursorPos(1, h - 1)
  term.clearLine()
  term.write(("> " .. (task or "")):sub(1, w))
  term.setCursorPos(1, h)
  term.clearLine()
  term.write(msg:sub(1, w))
  term.setCursorPos(x, math.min(y, h - 2))
end
function sendBase(t, extra)
  if not modemSide() then showLink("NO MODEM EQUIPPED - cannot report to the base") return end
  if not rednet.isOpen(modemSide()) then pcall(rednet.open, modemSide()) end
  local id = baseId()
  if not id then
    showLink("BASE NOT FOUND - is the base's Ender Modem on? (protocol " .. CONFIG.protocol .. ")")
    return
  end
  local m = {}
  for k, v in pairs(extra or {}) do m[k] = v end
  m.t, m.n = t, nextN()
  m.sig = sign(S.key or "change-me", m.t, m.n)
  m.mine = true
  m.role, m.dim, m.ver = S.role, S.dim, MYVER
  m.label = os.getComputerLabel() or ("Turtle " .. os.getComputerID())
  m.task = task
  local fuel = turtle.getFuelLevel()
  m.fuel = fuel
  m.free = freeSlots()
  m.pos = S.pos and { x = S.pos.x, y = S.pos.y, z = S.pos.z, f = FNAME[S.pos.f or 0] } or nil
  m.partner = S.partner
  m.lastCmd = S.lastCmd
  m.running = S.running
  m.err = S.err
  if S.role == "miner" then
    local P = S.plan
    m.ci = P and P.ci or nil
    m.li, m.nl = P and P.li or nil, P and #layers(P.yt) or nil
    m.phase = P and P.phase or nil
    m.station = S.station and true or false
    m.nextDump = S.lastDump and math.max(0, CONFIG.dumpEvery - (now() - S.lastDump)) or nil
    m.carry = topN(S.carry, 12)
    m.got = topN(S.got, 12)
    m.stats = S.stats
  end
  if #NOTES > 0 then m.notes = NOTES NOTES = {} end
  local okS, errS = pcall(rednet.send, id, m, CONFIG.protocol)
  showLink(okS and ("reported to base #" .. id .. " at " .. textutils.formatTime(os.time(), true) ..
                    " (key " .. tostring(S.key) .. ")")
               or ("SEND FAILED: " .. tostring(errS)))
  LAST_STATUS = os.clock()
end
function sendTeam(to, t, extra)
  if not modemSide() then return end
  if not rednet.isOpen(modemSide()) then pcall(rednet.open, modemSide()) end
  local m = {}
  for k, v in pairs(extra or {}) do m[k] = v end
  m.t, m.n = t, nextN()
  m.sig = sign(S.key or "change-me", m.t, m.n)
  m.dim = S.dim
  if to then pcall(rednet.send, to, m, CONFIG.team) else pcall(rednet.broadcast, m, CONFIG.team) end
end

-- a message arrived (base command or the team partner)
function handle(id, m, proto)
  if type(m) ~= "table" then return end
  if proto == CONFIG.protocol and m.t == "cmd" then
    if type(m.n) ~= "number" or m.n <= (S.lastCmd or 0) then return end
    if m.sig ~= sign(S.key or "change-me", "cmd", m.n, m.cmd, m.args) then return end
    S.lastCmd = m.n
    S.baseId = id
    doCmd(tostring(m.cmd), m.args or {})
    save()
  elseif proto == CONFIG.team then
    if type(m.n) ~= "number" or m.sig ~= sign(S.key or "change-me", m.t, m.n) then return end
    if m.dim ~= S.dim then return end
    if m.t == "loaderhere" and S.role == "miner" and (not S.partner or S.partner == id) then
      -- (again when the loader did not hear the first "paired")
      if S.partner ~= id then
        S.partner = id
        save()
        note("Paired with loader " .. id)
      end
      sendTeam(id, "paired")
    elseif m.t == "paired" and S.role == "loader" and (not S.partner or S.partner == id) then
      S.partner = id
      save()
      note("Paired with miner " .. id)
    elseif m.t == "follow" and S.role == "loader" and (id == S.partner or not S.partner) then
      if not S.partner then S.partner = id note("Paired with miner " .. id) end
      if not (S.follow and S.follow.ref == m.ref) then
        S.follow = { ref = m.ref, pts = m.pts, i = 1 }
        save()
      elseif S.follow.done then
        sendTeam(id, "arrived", { ref = m.ref })
      end
    elseif m.t == "arrived" and S.role == "miner" and id == S.partner then
      ARRIVED = m.ref
    end
  end
end
function doCmd(cmd, args)
  if cmd == "start" then
    if S.role == "miner" then
      S.running, S.err = true, nil
      note("START")
    end
  elseif cmd == "pause" then
    S.running = false
    note("PAUSED")
  elseif cmd == "unload" then
    DUMP_NOW = true
    note("Unload asked")
  elseif cmd == "newfield" then
    S.plan = nil
    S.running = false
    note("New mining field: starts here (the way it faces) on the next START")
  elseif cmd == "unpair" then
    S.partner = nil
    note("Unpaired")
  elseif cmd == "cfg" then
    -- "key=value" strings; lists as a,b,c
    S.cfg = S.cfg or {}
    for _, a in ipairs(args) do
      local k, v = tostring(a):match("^([%w_]+)=(.*)$")
      if k then
        local val
        if k == "want" or k == "keep" then
          val = {}
          for w in v:gmatch("[^,]+") do val[#val + 1] = w end
        else
          val = tonumber(v)
        end
        if val ~= nil then CONFIG[k] = val S.cfg[k] = val end
      end
    end
  elseif cmd == "status" then
    -- answered below
  end
  sendBase("status")
end
-- listen for a while (messages are handled as they come)
function listen(secs)
  local t0 = os.clock()
  while true do
    local left = secs - (os.clock() - t0)
    if left <= 0 then break end
    local id, m, proto = rednet.receive(nil, left)
    if id then handle(id, m, proto) end
  end
end

---------------------------------------------------------------------- inventory
function freeSlots()
  local n = 0
  for i = 1, 16 do if turtle.getItemCount(i) == 0 then n = n + 1 end end
  return n
end
function findSlot(test)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and test(d.name) then return i, d end
  end
end
function dropJunk()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isJunk(d.name) then
      turtle.select(i)
      if not turtle.dropUp() then turtle.dropDown() end
    end
  end
  turtle.select(1)
end
-- fuel from the coal it mines
function burnCoal()
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" or fuel >= CONFIG.lowFuel then return end
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isCoal(d.name) then
      turtle.select(i)
      while turtle.getFuelLevel() < CONFIG.fuelTarget and turtle.getItemCount(i) > 0 do
        if not turtle.refuel(1) then break end
      end
    end
  end
  turtle.select(1)
end
-- move the loot (not tools, not the coal kept for fuel) with a drop function;
-- returns { name = count } of what went
function dropLoot(dropFn)
  local moved, keptCoal = {}, 0
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isLoot(d.name) then
      local give = d.count
      if isCoal(d.name) and keptCoal < CONFIG.keepCoal then
        local keep = math.min(d.count, CONFIG.keepCoal - keptCoal)
        keptCoal = keptCoal + keep
        give = d.count - keep
      end
      if give > 0 then
        turtle.select(i)
        local before = turtle.getItemCount(i)
        dropFn(give)
        local went = before - turtle.getItemCount(i)
        if went > 0 then moved[d.name] = (moved[d.name] or 0) + went end
      end
    end
  end
  turtle.select(1)
  return moved
end
function addTo(t, moved)
  for k, v in pairs(moved) do t[k] = (t[k] or 0) + v end
end

---------------------------------------------------------------------- equipment (miner)
function coreSide()
  for _, side in ipairs({ "left", "right" }) do
    local t = peripheral.getType(side)
    if t and tostring(t):lower():gsub("[^%a]", ""):find("automata", 1, true) then return side end
  end
end
function toolSide()
  local c = coreSide()
  if c == "left" then return "right" end
  return "left"
end
-- what is on the free side now: "modem", "geo" or "pickaxe" (no peripheral)
function toolNow()
  local t = peripheral.getType(toolSide())
  if not t then return "pickaxe" end
  t = tostring(t):lower()
  if t:find("modem", 1, true) then return "modem" end
  if t:find("geo", 1, true) then return "geo" end
  return t
end
TOOL_ITEM = { pickaxe = "*pickaxe*", modem = "*modem*", geo = "*geo_scanner*" }
function equipTool(kind)
  if toolNow() == kind then
    -- already on (e.g. after a restart): the modem must still be OPENED
    if kind == "modem" and not rednet.isOpen(toolSide()) then pcall(rednet.open, toolSide()) end
    return true
  end
  local slot = findSlot(function(n) return match(n, { TOOL_ITEM[kind] }) end)
  if not slot then
    return false, "no " .. kind .. " in the inventory"
  end
  turtle.select(slot)
  local side = toolSide()
  local ok = (side == "left") and turtle.equipLeft() or turtle.equipRight()
  turtle.select(1)
  if not ok then return false, "could not equip the " .. kind end
  if kind == "modem" then
    for _ = 1, 10 do if peripheral.hasType(side, "modem") then break end sleep(0.05) end
    pcall(rednet.open, side)
  end
  return true
end
function ensurePick()
  if S.role ~= "miner" then return false end
  return equipTool("pickaxe")
end

---------------------------------------------------------------------- moving
function turnTo(f)
  f = f % 4
  local d = (f - S.pos.f) % 4
  if d == 1 then turtle.turnRight()
  elseif d == 2 then turtle.turnRight() turtle.turnRight()
  elseif d == 3 then turtle.turnLeft() end
  S.pos.f = f
end
-- the cell a move goes to
function cellFor(d)
  local p = S.pos
  if d == "u" then return p.x, p.y + 1, p.z end
  if d == "d" then return p.x, p.y - 1, p.z end
  return p.x + DX[p.f], p.y, p.z + DZ[p.f]
end
function nearStation(x, z, r)
  local st = S.station
  if not st then return false end
  return math.sqrt((x - st.x) ^ 2 + (z - st.z) ^ 2) < r
end
-- dig in direction d ("f", "u", "d"); true when the way is free
function digDir(d)
  local insp = (d == "u" and turtle.inspectUp) or (d == "d" and turtle.inspectDown) or turtle.inspect
  local okI, b = insp()
  if not okI then return true end
  if isLiquid(b.name) then return true end
  if isProtected(b.name) then return false, "will not dig " .. b.name end
  local x, _, z = cellFor(d)
  if nearStation(x, z, CONFIG.noDig) then return false, "too close to the unload station - no digging there" end
  local okP, errP = ensurePick()
  if not okP then return false, errP end
  local dig = (d == "u" and turtle.digUp) or (d == "d" and turtle.digDown) or turtle.dig
  local okD, err = dig()
  if not okD then return false, tostring(err or "cannot dig") end
  S.stats.dug = S.stats.dug + 1
  return true
end
-- one step ("f", "u", "d"), digging when allowed (miner) or waiting (loader)
function step(d)
  local mv = (d == "u" and turtle.up) or (d == "d" and turtle.down) or turtle.forward
  local det = (d == "u" and turtle.detectUp) or (d == "d" and turtle.detectDown) or turtle.detect
  local att = (d == "u" and turtle.attackUp) or (d == "d" and turtle.attackDown) or turtle.attack
  for try = 1, 60 do
    if mv() then
      local x, y, z = cellFor(d)
      S.pos.x, S.pos.y, S.pos.z = x, y, z
      afterMove()
      return true
    end
    if turtle.getFuelLevel() == 0 then return false, "out of fuel" end
    if det() then
      if S.role == "miner" then
        local ok, err = digDir(d)
        if not ok then return false, err end
      else
        -- the loader never digs: wait (a mob, the miner, fallen gravel)
        if try % 10 == 0 then setTask("blocked at " .. fmtPos() .. " - waiting") sendBase("status") end
        sleep(1)
      end
    else
      if S.role == "miner" then ensurePick() pcall(att) end
      sleep(0.3)
    end
  end
  return false, "blocked at " .. fmtPos()
end
-- straight moves: up/down first when going up, last when going down; x, then z.
-- trail (optional) gets the corners (for the loader)
function goTo(x, y, z, trail)
  local function addPt()
    if trail then
      local l = trail[#trail]
      if not l or l.x ~= S.pos.x or l.y ~= S.pos.y or l.z ~= S.pos.z then
        trail[#trail + 1] = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
      end
    end
  end
  local function vert()
    while S.pos.y < y do local ok, e = step("u") if not ok then return false, e end end
    while S.pos.y > y do local ok, e = step("d") if not ok then return false, e end end
    addPt()
    return true
  end
  if y > S.pos.y then local ok, e = vert() if not ok then return false, e end end
  if x ~= S.pos.x then
    turnTo(x > S.pos.x and 1 or 3)
    while S.pos.x ~= x do local ok, e = step("f") if not ok then return false, e end end
    addPt()
  end
  if z ~= S.pos.z then
    turnTo(z > S.pos.z and 2 or 0)
    while S.pos.z ~= z do local ok, e = step("f") if not ok then return false, e end end
    addPt()
  end
  if y ~= S.pos.y then local ok, e = vert() if not ok then return false, e end end
  return true
end
function fmtPos()
  local p = S.pos or {}
  return tostring(p.x) .. " " .. tostring(p.y) .. " " .. tostring(p.z)
end

-- after every step (miner): fuel, junk out, full -> shulker, report
function afterMove()
  if S.role ~= "miner" then
    save()
    if os.clock() - LAST_STATUS > 10 then sendBase("status") end
    return
  end
  save()
  if STASHING then return end
  -- long tunnels / shafts: still report every CONFIG.checkIn s
  if os.clock() - LAST_CHECK > CONFIG.checkIn then
    LAST_CHECK = os.clock()
    if equipTool("modem") then
      sendBase("status")
      listen(1.5)
    end
  end
  burnCoal()
  if freeSlots() <= 2 then
    dropJunk()
    if freeSlots() <= 2 then
      local ok, err = stash()
      if not ok then note("Could not use the shulker: " .. tostring(err)) DUMP_NOW = true end
    end
  end
end

---------------------------------------------------------------------- shulker
-- everything into the shulker: put it down in front (with air above it - a
-- shulker does not open under a block), fill it, pick it up again
function stash()
  local slot = findSlot(function(n) return n:find("shulker", 1, true) ~= nil end)
  if not slot then return false, "no shulker box" end
  STASHING = true
  local okP, okR, errR = pcall(function()
    -- room: the block in front and the one above it
    local ok, e = digDir("f")
    if not ok then return false, e end
    ok, e = step("u")
    if not ok then return false, e end
    ok, e = digDir("f")
    local okD, eD = step("d")
    if not ok then return false, e end
    if not okD then return false, eD end
    slot = findSlot(function(n) return n:find("shulker", 1, true) ~= nil end)
    turtle.select(slot)
    if not turtle.place() then turtle.select(1) return false, "could not place the shulker" end
    local moved = dropLoot(function(n) return turtle.drop(n) end)
    addTo(S.carry, moved)
    local left = 0
    for i = 1, 16 do
      local d = turtle.getItemDetail(i)
      if d and isLoot(d.name) and not isCoal(d.name) then left = left + 1 end
    end
    ensurePick()
    turtle.select(1)
    local okG = turtle.dig()
    if not okG then return false, "could not pick the shulker up again!" end
    save()
    if left > 0 then DUMP_NOW = true return true end    -- the shulker is full: unload now
    return true
  end)
  STASHING = false
  if not okP then okR, errR = false, tostring(okR) end
  turtle.select(1)
  return okR, errR
end

---------------------------------------------------------------------- warps (miner)
function core() local s = coreSide() return s and peripheral.wrap(s) end
function hasPoint(c, name)
  local okP, pts = pcall(c.getPoints)
  if not okP or type(pts) ~= "table" then return nil end
  for k, v in pairs(pts) do if v == name or k == name then return true end end
  return false
end
function savePoint(name)
  local c = core()
  if not c then return false, "no End Automata Core equipped" end
  pcall(c.deletePoint, name)
  local ok, a, b = pcall(c.savePoint, name)
  if not ok or a == false or a == nil then return false, tostring(b or a) end
  return true
end
function warp(name, pt)
  local c = core()
  if not c then return false, "no End Automata Core equipped" end
  if hasPoint(c, name) == false then return false, "warp point '" .. name .. "' is not in the core any more" end
  local okC, cost = pcall(c.estimateWarpCost, name)
  cost = okC and tonumber(cost) or 0
  local fuel = turtle.getFuelLevel()
  if fuel ~= "unlimited" and cost > fuel - 100 then return false, "not enough fuel to teleport (" .. cost .. ")" end
  local ok, a, b = pcall(c.warpToPoint, name)
  if not ok or a == false or a == nil then return false, "teleport failed: " .. tostring(b or a) end
  S.pos.x, S.pos.y, S.pos.z = pt.x, pt.y, pt.z
  save()
  return true
end
-- where are we after a restart during a teleport? (the cheaper point is here)
function whereAmI()
  local c = core()
  if not c then return nil end
  local okA, a = pcall(c.estimateWarpCost, "station")
  local okB, b = pcall(c.estimateWarpCost, "work")
  a, b = okA and tonumber(a), okB and tonumber(b)
  if a and b then return (a <= b) and "station" or "work" end
end
function stationHere()
  local ok, err = savePoint("station")
  if not ok then print("Could not save the station: " .. tostring(err)) return false end
  S.station = { x = S.pos.x, y = S.pos.y, z = S.pos.z, f = S.pos.f }
  save()
  print("Unload station saved here: " .. fmtPos() .. " facing " .. FNAME[S.pos.f])
  return true
end

-- empty everything at the station (we stand on it, facing its front)
function unloadHere()
  turnTo(S.station.f)
  local total = {}
  addTo(total, S.carry)
  local front = peripheral.isPresent("front") and peripheral.hasType("front", "inventory")
  local sh = findSlot(function(n) return n:find("shulker", 1, true) ~= nil end)
  if front then
    -- an inventory in front: own items straight in, the shulker goes ABOVE
    local moved = dropLoot(function(n) return turtle.drop(n) end)
    addTo(total, moved)
    if sh and next(S.carry) then
      if turtle.detectUp() then
        note("Unload: no room above the station for the shulker - its items stay in it")
      else
        turtle.select(sh)
        if turtle.placeUp() then
          setTask("unloading the shulker")
          local stuck = 0
          while true do
            local free
            for i = 1, 16 do if turtle.getItemCount(i) == 0 then free = i break end end
            if not free then break end
            turtle.select(free)
            if not turtle.suckUp(64) then break end
            if not turtle.drop() then
              stuck = stuck + 1
              turtle.dropUp()
              note("Unload: the inventory in front is full")
              break
            end
          end
          ensurePick()
          turtle.select(1)
          if not turtle.digUp() then note("Could not pick the shulker up at the station!") end
          if stuck == 0 then S.carry = {} end
        end
      end
    elseif not next(S.carry) then
      S.carry = {}
    end
  else
    -- empty block in front: put the shulker there, the Import Bus empties it
    if not sh then return false, "no shulker box to unload with" end
    if turtle.detect() then return false, "the block in front of the station is not empty" end
    turtle.select(sh)
    if not turtle.place() then turtle.select(1) return false, "could not place the shulker at the station" end
    local moved = dropLoot(function(n) return turtle.drop(n) end)
    addTo(total, moved)
    local p = peripheral.wrap("front")
    local t0 = os.clock()
    while p and os.clock() - t0 < 600 do
      local okL, list = pcall(p.list)
      local n = 0
      if okL and type(list) == "table" then for _, it in pairs(list) do n = n + (it.count or 0) end end
      if n == 0 then break end
      setTask("waiting for the Import Bus (" .. n .. " items left)")
      if os.clock() - LAST_STATUS > 10 then sendBase("status") end
      sleep(2)
    end
    ensurePick()
    turtle.select(1)
    if not turtle.dig() then note("Could not pick the shulker up at the station!") end
    S.carry = {}
  end
  addTo(S.got, total)
  local n = 0
  for _, v in pairs(total) do n = n + v end
  S.stats.dumps = S.stats.dumps + 1
  note("Unloaded " .. n .. " items")
  turtle.select(1)
  return true
end
function doDump()
  DUMP_NOW = false
  if not S.station then
    note("No unload station set - everything stays in the shulker")
    S.lastDump = now()
    return true
  end
  setTask("teleporting to the unload station")
  local ok, err = savePoint("work")
  if not ok then return false, "cannot save the work spot: " .. tostring(err) end
  S.workPt = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
  S.dumping = "warping"
  save()
  ok, err = warp("station", S.station)
  if not ok then S.dumping = nil save() return false, err end
  S.dumping = "at"
  save()
  return finishDump()
end
function finishDump()
  local ok, err = unloadHere()
  if not ok then note("Unload failed: " .. tostring(err)) end
  burnCoal()
  setTask("teleporting back to work")
  local okW, errW = warp("work", S.workPt)
  if not okW then return false, "cannot teleport back: " .. tostring(errW) end
  S.dumping = nil
  S.lastDump = now()
  save()
  return true
end

---------------------------------------------------------------------- the plan (miner)
function layers(yt)
  local out = {}
  local y = yt
  while y >= CONFIG.minY do out[#out + 1] = y y = y - CONFIG.layerStep end
  return out
end
function chunkAt(P, i)
  local L = math.max(1, CONFIG.rowLength)
  local r, k = math.floor(i / L), i % L
  local along = (r % 2 == 0) and k or (L - 1 - k)
  local rf = (P.f + 1) % 4
  local cx = P.sx + DX[P.f] * along + DX[rf] * r
  local cz = P.sz + DZ[P.f] * along + DZ[rf] * r
  return cx, cz
end
function center(cx, cz) return cx * 16 + 8, cz * 16 + 8 end
function newPlan()
  local p = S.pos
  S.plan = { sx = math.floor(p.x / 16), sz = math.floor(p.z / 16), f = p.f, yt = p.y, ci = 0, phase = "go",
             done = 0 }
  S.trail = { { x = p.x, y = p.y, z = p.z } }    -- the loader starts next to this spot
  S.lastDump = S.lastDump or now()
  save()
end
-- a safe point: report, fuel, unload when it is time
function checkpoint()
  if os.clock() - LAST_CHECK > CONFIG.checkIn then
    LAST_CHECK = os.clock()
    if equipTool("modem") then
      sendBase("status")
      listen(1.5)
    end
  end
  if not S.running then return false, "paused" end
  if DUMP_NOW or (S.lastDump and now() - S.lastDump > CONFIG.dumpEvery) then
    local ok, err = doDump()
    if not ok then return false, err end
  end
  return true
end
-- the ores (and wanted blocks) of one layer inside this chunk
function scanLayer(cx, cz)
  local ok, err = equipTool("geo")
  if not ok then return nil, err end
  local g = peripheral.wrap(toolSide())
  local res
  for _ = 1, 10 do
    local okS, a, b = pcall(g.scan, CONFIG.scanR)
    if okS and type(a) == "table" then res = a break end
    err = okS and b or a
    sleep(1)
  end
  if not res then return nil, "scan failed: " .. tostring(err) end
  local x0, z0 = cx * 16, cz * 16
  local out, wantN = {}, {}
  for _, b in ipairs(res) do
    local ax, ay, az = S.pos.x + b.x, S.pos.y + b.y, S.pos.z + b.z
    if ax >= x0 and ax <= x0 + 15 and az >= z0 and az <= z0 + 15 and not isProtected(b.name) then
      local ore = match(b.name, CONFIG.ores)
      if not ore and type(b.tags) == "table" then
        for k, v in pairs(b.tags) do
          local tg = (type(k) == "string" and k) or tostring(v)
          if tg:find("ores", 1, true) and not tg:find("ores_in_ground", 1, true) then ore = true break end
        end
      end
      if ore then
        out[#out + 1] = { x = ax, y = ay, z = az }
      elseif match(b.name, CONFIG.want) and (wantN[b.name] or 0) < CONFIG.wantMax then
        wantN[b.name] = (wantN[b.name] or 0) + 1
        out[#out + 1] = { x = ax, y = ay, z = az }
      end
    end
  end
  return out
end
function nearest(list)
  local bi, bd
  for i, t in ipairs(list) do
    local d = math.abs(t.x - S.pos.x) + math.abs(t.y - S.pos.y) + math.abs(t.z - S.pos.z)
    if not bd or d < bd then bi, bd = i, d end
  end
  return bi
end
-- the loader comes to the centre of the chunk just finished
function handoff(P, cxp, czp)
  local pts = {}
  for _, p in ipairs(S.trail or {}) do pts[#pts + 1] = p end
  -- the last point is where the miner stands now (the chunk edge): the loader stops before
  if #pts > 1 then table.remove(pts) end
  local ref = P.ci
  ARRIVED = nil
  local t0, sent = os.clock(), -1000
  while ARRIVED ~= ref do
    if not S.running then return false, "paused" end
    if os.clock() - sent > 60 then
      equipTool("modem")
      sendTeam(S.partner, "follow", { ref = ref, pts = pts })
      sent = os.clock()
    end
    setTask("waiting for the loader (" .. math.floor(os.clock() - t0) .. " s)")
    if os.clock() - LAST_STATUS > 15 then sendBase("status") end
    listen(2)
  end
  local last = S.trail[#S.trail]
  S.trail = { pts[#pts], last }
  return true
end
-- one piece of work; false, why = stop (paused or a problem)
function workStep()
  local okC, errC = checkpoint()
  if not okC then return false, errC end
  local P = S.plan
  local cx, cz = chunkAt(P, P.ci)
  local mx, mz = center(cx, cz)
  if P.phase == "go" then
    setTask("tunnel to chunk " .. P.ci .. " (" .. mx .. " " .. mz .. ")")
    local ok, err = goTo(mx, P.yt, mz, S.trail)
    if not ok then return false, err end
    if S.station and nearStation(mx, mz, CONFIG.noMine) then
      P.phase = "exit"                     -- near the station: only passing through
    else
      P.phase, P.li, P.targets = "layers", 1, nil
    end
    save()
    return true
  elseif P.phase == "layers" then
    local L = layers(P.yt)
    if P.li > #L then
      setTask("back up the shaft")
      local ok, err = goTo(mx, P.yt, mz)
      if not ok then return false, err end
      P.phase, P.done = "exit", (P.done or 0) + 1
      save()
      return true
    end
    local ly = L[P.li]
    if not P.targets then
      setTask("shaft to layer " .. P.li .. "/" .. #L .. " (Y " .. ly .. ")")
      local ok, err = goTo(mx, ly, mz)
      if not ok then return false, err end
      setTask("scanning layer " .. P.li .. "/" .. #L)
      local list, e2 = scanLayer(cx, cz)
      if not list then return false, e2 end
      P.targets = list
      save()
    end
    while #P.targets > 0 do
      local okC, errC = checkpoint()
      if not okC then return false, errC end
      local i = nearest(P.targets)
      local t = P.targets[i]
      setTask("chunk " .. P.ci .. " layer " .. P.li .. "/" .. #L .. ": " .. #P.targets .. " ores left")
      local ok = goTo(t.x, t.y, t.z)
      if ok then S.stats.ores = S.stats.ores + 1 end
      table.remove(P.targets, i)          -- reached or not (bedrock, protected): next
      save()
    end
    local ok, err = goTo(mx, ly, mz)
    if not ok then return false, err end
    P.li, P.targets = P.li + 1, nil
    save()
    return true
  elseif P.phase == "exit" then
    local nx, nz = chunkAt(P, P.ci + 1)
    -- the last cell of this chunk on the way to the next centre
    local bx, bz = mx, mz
    if nx > cx then bx = cx * 16 + 15 elseif nx < cx then bx = cx * 16 end
    if nz > cz then bz = cz * 16 + 15 elseif nz < cz then bz = cz * 16 end
    setTask("tunnel to the edge of chunk " .. P.ci)
    local ok, err = goTo(mx, P.yt, mz, S.trail)
    if not ok then return false, err end
    ok, err = goTo(bx, P.yt, bz, S.trail)
    if not ok then return false, err end
    ok, err = handoff(P, cx, cz)
    if not ok then return false, err end
    P.ci, P.phase = P.ci + 1, "go"
    save()
    return true
  end
  P.phase = "go"
  return true
end

---------------------------------------------------------------------- roles
-- the End Automata Core in the inventory but not equipped: put it on a side
-- (whatever was on that side goes into its slot - the tools take turns anyway)
function equipCore()
  if coreSide() then return true end
  local slot = findSlot(function(n) return match(n, { "*automata*" }) end)
  if not slot then return false, "no End Automata Core (equipped or in the inventory)" end
  turtle.select(slot)
  -- the side without a modem first (the modem keeps working while we do this)
  local first = peripheral.hasType("left", "modem") and "right" or "left"
  local ok = (first == "left") and turtle.equipLeft() or turtle.equipRight()
  turtle.select(1)
  for _ = 1, 10 do if coreSide() then break end sleep(0.1) end
  if not coreSide() then return false, "could not equip the End Automata Core" end
  return true
end
function minerRun()
  local okE, errE = equipCore()
  if okE then
    note("End Automata Core equipped on the " .. coreSide() .. " side")
  else
    note("! " .. tostring(errE) .. " - the miner needs one (it stays on)")
  end
  -- the station point lives in the core: still there? (it may be lost when the
  -- turtle is picked up and put down again)
  if S.station and coreSide() and hasPoint(core(), "station") == false then
    S.station = nil
    save()
    note("The unload station was lost from the End Automata Core (picked up?). Put the miner on the station, " ..
         "type  miner station, then carry it back and type  miner here")
  end
  -- a restart during an unload trip
  if S.dumping then
    local where = (S.dumping == "at") and "station" or whereAmI()
    if where == "station" then
      S.pos.x, S.pos.y, S.pos.z = S.station.x, S.station.y, S.station.z
      S.dumping = "at"
      local ok, err = finishDump()
      if not ok then S.running = false S.err = err note("Unload trip: " .. tostring(err)) end
    else
      S.dumping = nil
    end
    save()
  end
  if S.running then
    note("Restarted - continuing in 6 s")
    sleep(6)
  end
  while true do
    if not S.running or not S.partner then
      equipTool("modem")
      if not S.partner then setTask("waiting for a loader turtle (same dimension)")
      elseif S.err then setTask("PAUSED: " .. S.err)
      else setTask(S.plan and "paused" or "ready - press START on the base") end
      if os.clock() - LAST_STATUS > 10 then sendBase("status") end
      listen(3)
    else
      if not S.plan then newPlan() end
      burnCoal()
      if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 100 then
        S.running, S.err = false, "NO FUEL - put coal (or other fuel) in it and type  refuel all"
        note(S.err)
        save()
      end
      local okR, ok, err = pcall(workStep)
      if not okR then ok, err = false, "error: " .. tostring(ok) end
      if not ok then
        if err ~= "paused" then
          S.running, S.err = false, tostring(err)
          note("STOPPED: " .. tostring(err))
        end
        save()
        equipTool("modem")
        sendBase("status")
      end
    end
  end
end
function loaderRun()
  local side = modemSide()
  if side then pcall(rednet.open, side) else note("No modem on the loader!") end
  local lastHello = -1000
  while true do
    if not S.partner and os.clock() - lastHello > 5 then
      lastHello = os.clock()
      sendTeam(nil, "loaderhere")
    end
    local F = S.follow
    if F and not F.done then
      while F.i <= #F.pts do
        local p = F.pts[F.i]
        setTask("following the miner (" .. F.i .. "/" .. #F.pts .. ")")
        local ok, err = goTo(p.x, p.y, p.z)
        if not ok then
          setTask("STUCK following the miner: " .. tostring(err))
          note("Loader: " .. tostring(err))
          sendBase("status")
          sleep(5)
          break
        end
        F.i = F.i + 1
        save()
      end
      if F.i > #F.pts then
        F.done = true
        save()
        sendTeam(S.partner, "arrived", { ref = F.ref })
        setTask("keeping the miner's area loaded")
      end
    else
      setTask(S.partner and "keeping the miner's area loaded" or "waiting for a miner (same dimension)")
    end
    if os.clock() - LAST_STATUS > 10 then sendBase("status") end
    listen(2)
  end
end

---------------------------------------------------------------------- setup
function ask(q, default)
  write(q .. (default and (" [" .. default .. "]") or "") .. ": ")
  local a = read()
  if a == "" and default then return default end
  return a
end
function askPos()
  print("Position of THIS turtle (look at it, F3 'Targeted Block').")
  while true do
    local a = ask("x y z", S.pos and (S.pos.x .. " " .. S.pos.y .. " " .. S.pos.z) or nil)
    local x, y, z = tostring(a):match("^%s*(-?%d+)[%s,]+(-?%d+)[%s,]+(-?%d+)%s*$")
    if x then
      local f
      while not f do
        local s = ask("Which way does its FRONT face? (n/e/s/w)", S.pos and FNAME[S.pos.f]:sub(1, 1) or nil)
        f = ({ n = 0, e = 1, s = 2, w = 3 })[tostring(s):sub(1, 1):lower()]
      end
      S.pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z), f = f }
      save()
      return
    end
    print("Three numbers, like: 120 64 -35")
  end
end
function setup()
  term.clear()
  term.setCursorPos(1, 1)
  print("MINING TEAM setup")
  local r = ""
  while r ~= "m" and r ~= "l" do r = tostring(ask("Is this the MINER or the LOADER? (m/l)", S.role and S.role:sub(1, 1) or nil)):sub(1, 1):lower() end
  S.role = (r == "m") and "miner" or "loader"
  S.key = ask("Turtle key (CONFIG.turtles.key in base_config.lua)", S.key)
  local d = ""
  while d ~= "o" and d ~= "n" and d ~= "e" do
    d = tostring(ask("Which mining dimension? (o = overworld, n = nether, e = end)", S.dim and S.dim:sub(1, 1) or "o")):sub(1, 1):lower()
  end
  S.dim = ({ o = "overworld", n = "nether", e = "end" })[d]
  askPos()
  if not os.getComputerLabel() then os.setComputerLabel((S.role == "miner" and "Miner " or "Loader ") .. os.getComputerID()) end
  if S.role == "miner" then
    local okE, errE = equipCore()
    if okE then print("End Automata Core: equipped (" .. coreSide() .. " side)")
    else print("! " .. tostring(errE)) end
    for _, k in ipairs({ "pickaxe", "modem", "geo" }) do
      if toolNow() ~= k and not findSlot(function(n) return match(n, { TOOL_ITEM[k] }) end) then
        print("! Missing: " .. k)
      end
    end
    if not findSlot(function(n) return n:find("shulker", 1, true) ~= nil end) then print("! Missing: a shulker box") end
    local st = tostring(ask("Is it standing on the UNLOAD STATION now, facing its front? (y/n)", "n")):lower()
    if st:sub(1, 1) == "y" then stationHere() end
  else
    if not modemSide() then print("! No modem equipped - the loader needs an Ender Modem") end
    if not peripheral.getType("left") and not peripheral.getType("right") then print("! Equip the Chunky upgrade") end
  end
  save()
  print("Done. It starts by itself from now on.")
  if S.role == "miner" then print("Press START on the base (TURTLES > MINING).") end
  sleep(2)
end

---------------------------------------------------------------------- start
loadState()
local args = { ... }
if not fs.exists("startup.lua") then
  local h = fs.open("startup.lua", "w")
  h.write('shell.run("' .. (shell and shell.getRunningProgram() or "miner.lua") .. '")\n')
  h.close()
end
if args[1] == "setup" or not S.role or not S.pos then setup() end
if args[1] == "here" then
  askPos()
  -- moved by hand: the old plan and the loader's trail no longer fit
  S.plan, S.trail, S.follow, S.running = nil, nil, nil, false
  save()
  print("Old mining plan cleared - press START on the base when both turtles are placed.")
  if S.role == "miner" and S.station then
    local c = core()
    if c and hasPoint(c, "station") == false then
      print("! The unload station is NOT in the core any more (lost when it was picked up).")
    elseif c then
      print("Unload station still known: " .. S.station.x .. " " .. S.station.y .. " " .. S.station.z)
    end
  end
end
if args[1] == "station" then
  if S.role == "miner" then stationHere() else print("Only the miner has a station.") end
  return
end
term.clear()
term.setCursorPos(1, 1)
print(string.upper(S.role) .. " - " .. S.dim .. " mining dimension - " .. fmtPos())
print("Ctrl+T stops it.  'miner setup' asks everything again.")
local okRun, err = pcall(function()
  if S.role == "miner" then minerRun() else loaderRun() end
end)
if not okRun and tostring(err) ~= "Terminated" then
  local h = fs.open("miner_crash", "w")
  if h then h.write(tostring(err)) h.close() end
  printError("miner.lua stopped: " .. tostring(err))
  S.err = "crashed: " .. tostring(err)
  save()
  print("Restarting in 5 s ...")
  sleep(5)
  os.reboot()
end
