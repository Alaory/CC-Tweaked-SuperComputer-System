-- PING THAT IS HEARD (the owner: "some survey turtles do not respond to ping - specifically a copy that can load its
-- chunks"): a surveying turtle takes its modem off for every scan - one ping went nowhere. Sent again every 3 s until
-- it answers (10 tries), then ONE line that says why (the turtle reports what it refused - node m27).
local function mk(id)
  state.turtles[id] = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 5000, task = "scanning",
    pos = { x = 300, y = 70, z = 0 }, lastSeen = os.clock() }
  return state.turtles[id]
end
local function sent(id) local n = 0 for _, o in ipairs(state.tOut) do if o.id == id and o.msg.cmd == "ping" then n = n + 1 end end return n end
local function logHas(t, w) for _, l in ipairs(t.log) do if tostring(l.msg or l):find(w, 1, true) then return true end end return false end
state.tOut = {}
local t = mk(100023)
TT.send(100023, "ping", {})
CHECK(t.pingAsk and sent(100023) == 1, "PING from the card: sent, waiting for the answer")
for _ = 1, 3 do CLOCK = CLOCK + 3.1 TT.pingTick() end
CHECK(sent(100023) == 4, "not heard (modem off while scanning): sent again every 3 s (" .. sent(100023) .. ")")
-- the answer (its report: the copy tag maps to 100023)
local n0 = os.epoch("utc")
TT.receive(23, { t = "result", n = n0, sig = TT.sign(CONFIG.turtles.key, "result", n0), cmd = "ping", ok = true, msg = "pong", copy = 1, label = "T23 [c1]" })
CHECK(t.pingAsk == nil and logHas(t, "answered PING"), "the copy's answer ends it and says after how long")
-- no answer at all: 10 tries, then why
state.tOut = {}
local u = mk(31)
TT.send(31, "ping", {})
local n1 = os.epoch("utc") + 5
TT.receive(31, { t = "status", n = n1, sig = TT.sign(CONFIG.turtles.key, "status", n1), task = "idle", refused = "ping:ses" })
for _ = 1, 12 do CLOCK = CLOCK + 3.1 TT.pingTick() end
CHECK(u.pingAsk == nil and sent(31) == 10, "gives up after 10 tries (" .. sent(31) .. ")")
CHECK(logHas(u, "no answer to PING") and logHas(u, "REFUSED a command lately: ping - it was for another session"),
      "... and says why: the turtle refused it")
-- automatic pings (the chunk test) are not repeated
state.tOut = {}
local c = mk(41)
TT.send(41, "ping", {}, true)
CHECK(c.pingAsk == nil, "a quiet automatic ping is not followed")
-- node.lua: a signed command for me that I do not take is reported
local src = io.open(SRC_DIR .. "/node.lua"):read("a")
CHECK(src:find('m.refused = REFUSED', 1, true) and src:find('":ses"', 1, true), "node.lua reports what it refused")
