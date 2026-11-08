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
for _, h in ipairs(hitsOf("tdrive")) do if h[6][2] == "f" then fwd = h end end
CHECK(fwd and fwd[6][1] == 30, "FORWARD button for the first online turtle")
handleTouch(fwd[1], fwd[2])
local s = sentDrive()
CHECK(s[1] and s[1][1] == "f" and s[1][2] == nil, "tap FORWARD: one drive step sent")
CHECK(not t.held, "driving ends a STOP hold")
-- the answer: what it sees, with a scan (relative, world directions)
report(30, { t = "look", pos = { x = 101, y = 40, z = 100, f = "east" }, front = "minecraft:stone", up = "minecraft:air",
             down = "minecraft:deepslate_iron_ore", scan = "1,0,0,stone;0,-1,0,deepslate_iron_ore;0,1,1,lava" })
local c = t.view and t.view.cells or {}
CHECK(c["102,40,100"] == "stone" and c["101,39,100"] == "deepslate_iron_ore" and c["101,41,101"] == "lava",
      "the scan is kept in world positions")
CHECK(c["101,41,100"] == false, "UP air is known as air")
-- it moves on: the old cells stay where they are in the world
report(30, { t = "look", pos = { x = 102, y = 40, z = 100, f = "east" }, front = "minecraft:air", up = "minecraft:air", down = "minecraft:stone" })
c = t.view.cells
CHECK(c["101,39,100"] == "deepslate_iron_ore" and c["102,40,100"] == false and c["103,40,100"] == false,
      "after a step: earlier blocks stay, where it stands is free, front updated")
CHECK(pcall(draw), "DRIVE page draws with a view")
-- a refused dig: DIG ANYWAY (two taps) sends the same step with force
t.driveLast = "digf"
report(30, { t = "result", cmd = "drive", ok = false, msg = "oak_planks is not a natural block - DIG ANYWAY (two taps) if you are sure" })
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
