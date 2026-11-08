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
