-- UPDATE TURTLES (button / console `update` / pocket) sends the new node.lua NOW:
-- also while the owner plays (updates normally wait) and with automatic updates
-- off; a busy turtle that already has it waiting gets a STOP (no hold) so it
-- installs at once. A lost LOADER can be dropped (forgotten) too.
TT.codeLoad = function() CODE = CODE or { ver = "NEWVER", pieces = { "a", "b" }, text = "x" } end
TT.codeLoad()
local now = os.epoch("utc")
state.turtles = {}
local function T(id, f)
  local t = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 9000, pos = { x = id, y = 70, z = 0 },
              task = "idle", lastSeen = os.clock(), seenEpoch = now, ver = "OLD" }
  for k, v in pairs(f or {}) do t[k] = v end
  state.turtles[id] = t
end
T(1) T(2) T(3, { task = "survey: spot 4/64", updReady = "NEWVER" }) T(4, { ver = "NEWVER" })
CONFIG.turtles.autoUpdate = false
state.owner = "Alaory"
state.online, state.onlineT = { alaory = true }, os.clock()
TT.updateForce = nil
TT.sending = {}
state.tOut = {}
TT.updateTick()
CHECK(next(TT.sending) == nil, "without UPDATE TURTLES nothing is sent (automatic updates off)")
local out = handleCommand("update") or {}
TT.updateTick()
CHECK(TT.sending[1] and TT.sending[2], "console update: sent at once, also while the owner plays")
CHECK(not TT.sending[4], "an up-to-date turtle gets nothing")
local stopped = false
for _, o in ipairs(state.tOut) do if o.id == 3 and o.msg.cmd == "stop" then stopped = true end end
CHECK(stopped and not state.turtles[3].held, "busy turtle with the update waiting: STOP (no hold) so it installs now")
CHECK(table.concat(out, "\n"):find("get it now", 1, true), "console says they get it now")
-- the list label says why an update waits
TT.updateForce = nil
TT.updWaiting = true
state.page = "turtles"
CHECK(pcall(draw), "TURTLES page draws")
-- a lost loader: mine drop forgets it
MINE.units[90] = { id = 90, role = "loader", dim = "overworld", log = {}, queue = {} }
local msg = table.concat(handleCommand("mine drop 90") or {}, " ")
CHECK(MINE.units[90] == nil and msg:find("new loader", 1, true), "mine drop <loader>: forgotten, tells what to do")
-- miner.lua: miners leave a loader that is silent 10 min when a new one says hello
local src = io.open(SRC_DIR .. "/miner.lua"):read("a")
CHECK(src:find('os.clock() - (LEADER_SEEN or 0) > 600', 1, true), "miner.lua: joins a new loader after 10 min")

-- MANY turtles that each miss the first try (scanning: the modem is off) -> a
-- retry 2 min later each. Before: UPDATE TURTLES forced only 10 minutes, the
-- last ones never got it while you played. Now: until every online turtle has
-- it (max 1 h). A turtle reporting version "?" gets it too.
state.turtles, TT.sending, state.tOut = {}, {}, {}
TT.updWaiting = false
for id = 21, 30 do T(id) end
T(31, { ver = "?" })
local pushes, sentAt = {}, {}
local realPush = TT.pushCode
TT.pushCode = function(id)
  pushes[id] = (pushes[id] or 0) + 1
  sentAt[id] = CLOCK
  return true
end
handleCommand("update")
for _ = 1, 20 * 30 do                                  -- 20 minutes, a tick every 2 s
  CLOCK = CLOCK + 2
  for id, t in pairs(state.turtles) do
    t.lastSeen = os.clock()                            -- (all online)
    if pushes[id] and pushes[id] >= 2 and sentAt[id] and CLOCK - sentAt[id] > 10 then t.ver = "NEWVER" end
  end
  TT.updateTick()
end
TT.pushCode = realPush
local left = {}
for id, t in pairs(state.turtles) do if t.ver ~= "NEWVER" then left[#left + 1] = id end end
table.sort(left)
CHECK(#left == 0, "UPDATE TURTLES: every turtle updated, also after 10 min (left: " .. table.concat(left, ",") .. ")")
CHECK(pushes[31], "a turtle with version '?' gets the update too")
CHECK(not TT.updateForce, "all done: the forced update ends by itself")
