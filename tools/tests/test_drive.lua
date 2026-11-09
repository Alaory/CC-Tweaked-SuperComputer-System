-- DRIVE page: pick a turtle, every button sends ONE step ("drive"), the turtle's
-- "look" answer fills the 3 grids (world positions, so they stay right as it
-- moves), a refused dig offers DIG ANYWAY (two taps -> force), the page draws.
local SEQ = 0
local function report(id, m)
  SEQ = SEQ + 1
  m.n = os.epoch("utc") + 1000 + SEQ
  m.t = m.t or "status"
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
state.turtles = {}
report(30, { label = "Digger", pos = { x = 100, y = 40, z = 100, f = "east" }, task = "idle", fuel = 5000,
             gear = "L=minecraft:diamond_pickaxe R=computercraft:wireless_modem_advanced" })
local t = state.turtles[30]
CHECK(t, "turtle known")
t.held = true
local function hitsOf(kind)
  local r = {}
  for _, h in ipairs(hits or {}) do if h[5] == kind then r[#r + 1] = h end end
  return r
end
local function sentDrive()
  local r = {}
  for _, o in ipairs(state.tOut) do if o.msg.cmd == "drive" then r[#r + 1] = o.msg.args end end
  state.tOut = {}
  return r
end
state.page, state.tSel, state.tOut = "drive", nil, {}
CHECK(pcall(draw), "DRIVE page draws")
-- FORWARD
local fwd
for _, h in ipairs(hitsOf("tdrive")) do if h[6][2] == "minef" then fwd = h end end
CHECK(fwd and fwd[6][1] == 30, "AHEAD tile for the first online turtle")
handleTouch(fwd[1], fwd[2])
local s = sentDrive()
CHECK(s[1] and s[1][1] == "minef" and s[1][2] == nil, "tap AHEAD: one step (dig if needed + go)")
local acts = {}
for _, h in ipairs(hitsOf("tdrive")) do acts[h[6][2]] = true end
CHECK(acts.l and acts.r and acts.mineu and acts.mined and acts.look and acts.b,
      "buttons: turn left / right, up / down, scan, back")
CHECK(acts.gon and acts.goe and acts.gos and acts.gow, "the 4 blocks next to the turtle on ITS LEVEL can be tapped to go there")
CHECK(not t.held, "driving ends a STOP hold")
-- the answer: what it sees, with a scan (relative, world directions)
report(30, { t = "look", pos = { x = 101, y = 40, z = 100, f = "east" }, front = "minecraft:stone", up = "minecraft:air",
             down = "minecraft:deepslate_iron_ore", scan = "1,0,0,stone;0,-1,0,deepslate_iron_ore;0,1,1,lava" })
local c = t.view and t.view.cells or {}
CHECK(c["102,40,100"] == "stone" and c["101,39,100"] == "deepslate_iron_ore" and c["101,41,101"] == "lava",
      "the scan is kept in world positions")
CHECK(c["101,41,100"] == false, "UP air is known as air")
CHECK(c["99,40,98"] == false and c["104,40,100"] == false, "inside the scan, blocks it did not list are AIR (the scanner leaves air out)")
CHECK(c["105,40,100"] == nil, "outside the scan: not seen yet")
-- it moves on: the old cells stay where they are in the world
report(30, { t = "look", pos = { x = 102, y = 40, z = 100, f = "east" }, front = "minecraft:air", up = "minecraft:air", down = "minecraft:stone" })
c = t.view.cells
CHECK(c["101,39,100"] == "deepslate_iron_ore" and c["102,40,100"] == false and c["103,40,100"] == false,
      "after a step: earlier blocks stay, where it stands is free, front updated")
CHECK(pcall(draw), "DRIVE page draws with a view")
-- a refused dig: DIG ANYWAY (two taps) sends the same step with force
t.driveLast = "digf"
report(30, { t = "result", cmd = "drive", pos = { x = 102, y = 40, z = 100, f = "east" }, ok = false, msg = "oak_planks is not a natural block - DIG ANYWAY (two taps) if you are sure" })
CHECK(t.driveAnyway == "digf", "refused dig: DIG ANYWAY offered")
draw()
local any
for _, h in ipairs(hitsOf("act")) do if h[6].kind == "tdriveforce" then any = h end end
CHECK(any, "DIG ANYWAY button shown")
if any then
  handleTouch(any[1], any[2]) draw()
  for _, h in ipairs(hitsOf("act")) do if h[6].kind == "tdriveforce" then any = h end end
  handleTouch(any[1], any[2])
end
s = sentDrive()
CHECK(s[1] and s[1][1] == "digf" and s[1][2] == "force", "two taps: dig with force")
-- no answer for a while: the page says so (never just hangs)
t.driveSent, t.driveMsg = os.clock() - 20, nil
CHECK(pcall(draw), "page draws while waiting for an answer")
-- node.lua: the drive command exists, busy turtles refuse
local src = io.open(SRC_DIR .. "/node.lua"):read("a")
CHECK(src:find('elseif cmd == "drive" then', 1, true) and src:find('if job then return false, "busy: "', 1, true),
      "node.lua: drive steps are immediate and refused while a job runs")

-- the same six rows everywhere: direction, what is there, key, what it does
local rows = driveRows(t)
local byDir = {}
for _, r in ipairs(rows) do byDir[r.dir] = r end
CHECK(#rows == 6 and byDir.AHEAD.key == "W" and byDir.ABOVE.key == "SPACE" and byDir.BELOW.key == "SHIFT"
      and byDir.LEFT.key == "A" and byDir.RIGHT.key == "D" and byDir.BEHIND.key == "S", "six rows with their keys")
CHECK(driveWord(byDir.BELOW.name) == "STONE" and byDir.BELOW.does == "DIG + GO DOWN",
      "BELOW: stone, DIG + GO DOWN (" .. driveWord(byDir.BELOW.name) .. " / " .. byDir.BELOW.does .. ", pos " ..
      tostring(t.pos and (t.pos.x .. " " .. t.pos.y .. " " .. tostring(t.pos.f))) .. ")")
-- keyboard driving on the base computer: W, then A, then Q leaves
local evs = { { "key", keys.w }, { "key", keys.a }, { "key", keys.space }, { "key", keys.q } }
local pe = os.pullEvent
os.pullEvent = function() local e = table.remove(evs, 1) or { "key", keys.q } return e[1], e[2] end
state.tOut = {}
t.lastSeen = os.clock()
local term0 = term
term = setmetatable({}, { __index = function() return function() return 51, 19 end end })
local print0 = print
print = function() end
local okT, errT = pcall(driveTerminal, 30)
os.pullEvent, term, print = pe, term0, print0
local steps = {}
for _, a in ipairs(sentDrive()) do steps[#steps + 1] = a[1] end
CHECK(okT, "drive <id> on the computer runs: " .. tostring(errT))
CHECK(table.concat(steps, ",") == "look,minef,l,mineu", "drive <id> looks around at once, keys W / A / SPACE drive it (" ..
      table.concat(steps, ",") .. ")")
-- a step's small scan (radius 1) keeps what a bigger scan saw further away
t.view.cells["105,40,100"] = "coal_ore"
report(30, { t = "look", pos = { x = 102, y = 40, z = 100, f = "east" }, front = "minecraft:air", up = "minecraft:air",
             down = "minecraft:stone", scan = "0,-1,0,stone", scanR = 1 })
CHECK(t.view.cells["105,40,100"] == "coal_ore" and t.view.cells["103,40,101"] == false and t.view.cells["102,39,100"] == "stone",
      "radius-1 scan: near blocks updated, farther ones kept")
-- picking a turtle on the monitor looks around at once
state.tOut = {}
draw()
local pick
for _, h in ipairs(hitsOf("tdsel")) do if h[6] == 30 then pick = h end end
if pick then handleTouch(pick[1], pick[2]) end
local la = sentDrive()
CHECK(la[1] and la[1][1] == "look", "picking the turtle on the monitor: it looks around at once")

-- YOUR commands are marked (the turtle pauses its job for them); automatic ones not
do
  local function lastMsg() return state.tOut[#state.tOut].msg end
  TT.drive(30, "f")
  CHECK(lastMsg().hand == true, "DRIVE step: marked as yours")
  TT.send(30, "home", {})
  CHECK(lastMsg().hand == nil, "an automatic home: not marked")
  USER_ACTION = true
  TT.send(30, "home", {})
  CHECK(lastMsg().hand == true, "GO HOME you pressed: marked as yours")
  TT.send(30, "stop", {})
  CHECK(lastMsg().hand == nil, "STOP: never marked (it is a stop)")
  USER_ACTION = false
  HAND_CMD = true
  TT.send(30, "goto", { 1, 2, 3 })
  CHECK(lastMsg().hand == true, "a console command: marked as yours")
  HAND_CMD = false
end

-- the base never switches digging ON for a turtle by itself (a rescue with a
-- pickaxe used to) and sends every turtle the base's NO-DIG zone
do
  local fh = io.open("base_turtles.lua") or io.open("../../base_turtles.lua")
  local src = fh and fh:read("a") or ""
  CHECK(src ~= "", "base_turtles.lua read")
  CHECK(not src:find('"setting", { "dig", "true" }', 1, true), "a rescue never switches digging on")
  state.tOut = {}
  CONFIG.drone.home = { x = -5271, y = 64, z = 10845 }
  CONFIG.turtles.noDigBase = 96
  if state.turtles[30] then state.turtles[30].zoneSent = nil end
  report(30, { task = "idle" })
  local got = {}
  for _, o in ipairs(state.tOut) do
    if o.id == 30 and o.msg.cmd == "setting" then got[o.msg.args[1]] = o.msg.args[2] end
  end
  CHECK(got.baseAt == "-5271,64,10845" and got.noDigBase == "96", "the turtle gets the base no-dig zone (" ..
        tostring(got.baseAt) .. " / " .. tostring(got.noDigBase) .. ")")
  CHECK(got.dig == "false" or got.dig == "true", "and the dig setting itself")
  state.tOut = {}
  report(30, { task = "idle" })
  local again = 0
  for _, o in ipairs(state.tOut) do if o.msg.cmd == "setting" then again = again + 1 end end
  CHECK(again == 0, "sent once, not with every report")
end
