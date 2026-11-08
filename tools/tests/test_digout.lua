-- A STUCK turtle that carries a pickaxe (e.g. the rescuer in a cave after a
-- rescue) is sent home with "dig" (it may dig through natural blocks); one
-- without a pickaxe is not; at most every 10 min, 3 tries.
local now = os.epoch("utc")
local function T(id, f)
  local t = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 9000, pos = { x = 500, y = 40, z = 500 },
              home = { x = 0, y = 70, z = 0 }, task = "idle", lastSeen = os.clock(), seenEpoch = now }
  for k, v in pairs(f) do t[k] = v end
  state.turtles[id] = t
  return t
end
state.turtles = {}
T(40, { stuck = "no way found", gear = "diamond_pickaxe, drive", rescuerRole = true })
T(41, { stuck = "no way found", gear = "" })
local function sentHome()
  local r = {}
  for _, o in ipairs(state.tOut) do
    if o.msg and o.msg.cmd == "home" then r[o.id] = (o.msg.args or {})[1] or "" end
  end
  state.tOut = {}
  return r
end
state.tOut = {}
TT.homeTick()                                    -- (idle timer starts)
CLOCK = CLOCK + 40
TT.homeTick()
local s = sentHome()
CHECK(s[40] == "dig", "stuck turtle with a pickaxe: home, digging (" .. tostring(s[40]) .. ")")
CHECK(s[41] == nil, "stuck turtle without a pickaxe: not sent")
CLOCK = CLOCK + 60
TT.homeTick()
CHECK(sentHome()[40] == nil, "not again within 10 min")
for _ = 1, 4 do CLOCK = CLOCK + 610 state.turtles[40].lastSeen = os.clock() TT.homeTick() end
CHECK(state.turtles[40].digOutTries == 3, "3 tries at most (" .. tostring(state.turtles[40].digOutTries) .. ")")
state.turtles[40].stuck = nil
TT.homeTick()
CHECK(state.turtles[40].digOutTries == nil, "fine again: tries reset")
-- node.lua: a stuck home trip / "home dig" may dig
local src = io.open(SRC_DIR .. "/node.lua"):read("a")
CHECK(src:find('j.cmd == "home" and (S.stuck or a[1] == "dig") then DIG_JOB = true', 1, true), "node.lua: stuck home trips dig")
-- the MINE UP button on the TURTLES page: only for an online turtle with a pickaxe; tap twice -> "digup"
local function findDigup()
  for _, h in ipairs(hits or {}) do
    local v = h[6]
    if type(v) == "table" and v.kind == "tdigup" then return h end
  end
end
state.turtles[40].lastSeen = os.clock()
state.page, state.tSel = "turtles", 40
CHECK(pcall(draw), "TURTLES page draws with MINE UP")
CHECK(findDigup(), "MINE UP button for a turtle with a pickaxe")
state.tSel = 41
state.turtles[41].lastSeen = os.clock()
draw()
CHECK(not findDigup(), "no MINE UP without a pickaxe")
state.tOut = {}
state.turtles[40].pos = { x = 10, y = 30, z = 10 }
local get0 = MAP.get
MAP.get = function() return 64 end
state.tSel = 40
draw()
local hb = findDigup()
if hb then handleTouch(hb[1], hb[2]) draw() hb = findDigup() handleTouch(hb[1], hb[2]) end
MAP.get = get0
local d
for _, o in ipairs(state.tOut) do if o.id == 40 and o.msg.cmd == "digup" then d = o.msg.args[1] end end
CHECK(d == 65, "MINE UP: sent with the surface from the map (" .. tostring(d) .. ")")
