-- The pocket remote: the REAL pocket.lua and the real base (base_pocket.lua)
-- talking through a fake rednet. Pairing (code from the monitor), status,
-- every tab draws, actions arrive, forged / replayed / unpaired messages are
-- refused, warnings reach the pocket.
local BASE_ID = os.getComputerID()
local PID = 55
-- the pocket's own little world: screen, rednet, GPS, its id
local SCREEN = {}
local cx, cy = 1, 1
local fakeTerm = {
  getSize = function() return 26, 20 end, clear = function() SCREEN = {} end,
  setCursorPos = function(x, y) cx, cy = x, y end, setTextColor = function() end, setBackgroundColor = function() end,
  write = function(s) local l = SCREEN[cy] or string.rep(" ", 26)
    SCREEN[cy] = (l:sub(1, cx - 1) .. s .. l:sub(cx + #s)):sub(1, 26) cx = cx + #s end,
}
local function screenText() local t = {} for y = 1, 20 do t[#t + 1] = SCREEN[y] or "" end return table.concat(t, "\n") end
local penv = setmetatable({}, { __index = _G })
penv.term = fakeTerm
penv.os = setmetatable({ getComputerID = function() return PID end, getComputerLabel = function() return "MyPocket" end },
                       { __index = os })
local GPSPOS = { 120, 71, -40 }
penv.gps = { locate = function() return GPSPOS[1], GPSPOS[2], GPSPOS[3] end }
penv.rednet = {
  lookup = function() return BASE_ID end,
  send = function(id, m) if id == BASE_ID then POCKET.receive(PID, m) end end,
}
_G.POCKET_TEST = true
local chunk = assert(loadfile(SRC_DIR .. "/pocket.lua", "t", penv))
local P = chunk()
_G.POCKET_TEST = nil
CHECK(type(P) == "table", "pocket.lua loads (test mode)")
local function pump()
  local out = POCKET.out
  POCKET.out = {}
  for _, o in ipairs(out) do if o.id == PID then penv.handle(BASE_ID, o.msg) end end
end

-- pairing: a wrong code is refused, the right one pairs
POCKET.pockets = {}
penv.sendBase("pairreq", nil, nil, { name = "MyPocket" })
local code = POCKET.pairing and POCKET.pairing.code
CHECK(code and #code == 6, "the base made a 6-digit code (shown on the monitor)")
P.code, P.waitPair = "000000", true
if code == "000000" then P.code = "111111" end
penv.sendBase("pair", nil, nil, { proof = penv.sign(P.code, "pair", PID) })
pump()
CHECK(not P.key and P.pairError == "wrong code", "a wrong code is refused (" .. tostring(P.pairError) .. ")")
P.code, P.waitPair = code, true
penv.sendBase("pair", nil, nil, { proof = penv.sign(code, "pair", PID) })
pump()
CHECK(P.key and POCKET.pockets[PID] and P.key == POCKET.pockets[PID].key, "paired: the pocket has the base's key for it")
CHECK(P.key ~= CONFIG.turtles.key, "its own key (not the turtles' key)")

-- status
state.turtles[7].fuel = 4210
penv.refresh()
pump()
CHECK(type(P.data) == "table" and P.data.turtles and #P.data.turtles >= 1, "status arrives")
-- every tab draws on a 26 x 20 screen
for _, tab in ipairs({ "home", "ride", "bots", "mine", "msg", "more" }) do
  P.tab = tab
  local ok, err = pcall(penv.draw)
  CHECK(ok, "tab " .. tab .. " draws: " .. tostring(err))
end
P.tab = "home" penv.draw()
CHECK(screenText():find("TURTLES", 1, true) and screenText():find("idle", 1, true), "HOME shows the turtles")
-- a full fleet (like the owner's: 17 turtles, many offline) - nothing is cut off at the edge,
-- the BOTS list scrolls down to the last turtle, the ones that need you come first
local fleet = {}
for i = 1, 17 do
  fleet[i] = { id = 100 + i, label = "Survey" .. i, lab = i <= 11 and "OFFLINE" or "IDLE", key = i <= 11 and "offline" or "idle",
               fuel = 900 * i, task = "idle", why = "" }
end
fleet[17] = { id = 117, label = "Stucky", lab = "STUCK", key = "stuck", fuel = 3000, task = "idle", why = "blocked by bedrock below" }
local d0 = P.data
P.data = { counts = { idle = 6, offline = 11 }, needs = { { id = 117, label = "Stucky", lab = "STUCK" } }, turtles = fleet,
           mining = { { dim = "overworld", label = "STOPPED", running = false, miners = 2, ci = 12, rate = 0, ores = 0,
                        loader = 10, gone = { { id = 11, label = "Digger" } } } },
           factory = "off (SETTINGS > FACTORY: fleet size 0)", auto = true, area = "whole world", places = {}, drones = {} }
P.got = os.clock()
P.tab, P.scroll = "home", {}
penv.draw()
local wholeWords = true
for y = 2, 19 do
  local l = SCREEN[y] or ""
  -- a cut-off line ends in a letter right at the edge and the text goes on (old: "need a loo")
  if #l >= 26 and l:sub(26, 26):match("%a") and l:sub(25, 25):match("%a") and not l:match("^%s*%S+%s*$") then
    if not l:match("^ [A-Z +]+ *>?%s*$") then wholeWords = false end
  end
end
CHECK(wholeWords, "HOME: no line cut off at the right edge\n" .. screenText())
CHECK(screenText():find("11 offline", 1, true) and screenText():find("Stucky", 1, true), "HOME: offline count and who needs a look")
P.tab = "bots" penv.draw()
CHECK(screenText():find("Stucky", 1, true), "BOTS: the stuck turtle is at the top")
for _ = 1, 10 do
  local down
  for _, h in ipairs(P.hits) do if h.y == 2 and h.x > 20 then down = h end end
  if down then penv.click(down.x, down.y) end
  penv.draw()
end
CHECK(P.scroll.bots and P.scroll.bots > 0, "BOTS scrolls with the v button")
local all = screenText()
CHECK(all:find("Survey11", 1, true), "BOTS: scrolled to the end of the list\n" .. all)
P.scroll.bots = 999 penv.draw()
CHECK(P.scroll.bots == P.maxOff.bots, "scrolling stops at the end")
if GETENV("DUMP") then
  for _, tab in ipairs({ "home", "bots", "mine", "more", "ride" }) do
    for _, o in ipairs({ 0, 99 }) do
      P.tab = tab P.scroll = { [tab] = o } penv.draw() if P.scroll[tab] > (P.maxOff[tab] or 0) then P.scroll[tab] = P.maxOff[tab] end penv.draw()
      io.stderr:write("+--------------------------+ " .. tab .. " scroll " .. P.scroll[tab] .. "\n")
      for y = 1, 20 do io.stderr:write("|" .. (SCREEN[y] or "") .. string.rep(" ", 26 - #(SCREEN[y] or "")) .. "|\n") end
    end
  end
end
P.data, P.tab, P.scroll = d0, "home", {}
if GETENV("DUMP") then
  for _, tab in ipairs({ "home", "ride", "bots", "more" }) do
    P.tab = tab penv.draw()
    io.stderr:write("+--------------------------+ " .. tab .. "\n")
    for y = 1, 20 do io.stderr:write("|" .. (SCREEN[y] or "") .. string.rep(" ", 26 - #(SCREEN[y] or "")) .. "|\n") end
  end
end

-- actions: STOP ALL needs two taps
local sent = {}
local send0 = TT.send
TT.send = function(id, c, ...) sent[#sent + 1] = id .. ":" .. c return send0(id, c, ...) end
state.turtles[7].lastSeen = os.clock()
P.tab = "bots" penv.draw()
local stopAll
for _, h in ipairs(P.hits) do if h.confirm == "STOP ALL" then stopAll = h end end
CHECK(stopAll, "BOTS has STOP ALL")
penv.click(stopAll.x, stopAll.y)
pump()
CHECK(#sent == 0, "one tap: nothing yet (TAP AGAIN)")
penv.click(stopAll.x, stopAll.y)
pump()
CHECK(table.concat(sent, ","):find("7:stop", 1, true), "second tap: STOP sent to the turtles")
CHECK(P.toast and P.toast:find("^OK"), "the answer is shown: " .. tostring(P.toast))
-- one turtle: HOME
sent = {}
penv.act("turtle", { 7, "home" })
pump()
CHECK(sent[1] == "7:home", "turtle 7: HOME")
penv.act("turtle", { 7, "dig" })
pump()
CHECK(P.toast and P.toast:find("not allowed", 1, true), "commands other than stop/home/gps/ping are refused")
TT.send = send0
-- a work-area corner from the pocket's GPS
penv.act("corner", { 1 }, true)
pump()
local a = CONFIG.map.areaA
CHECK(a and a.x == 120 and a.z == -40, "corner 1 where the pocket is (GPS)")
state.playerDim = "jamd:mining"
GPSPOS = { 999, 10, 999 }
penv.act("corner", { 2 }, true)
pump()
CHECK(not CONFIG.map.areaB and P.toast:find("overworld", 1, true), "in another dimension: no corner from the GPS (" .. tostring(P.toast) .. ")")
state.playerDim = nil
-- a ride: the base starts a drone ride for the owner to the base
local rode
local start0, problem0 = startRide, rideProblem
startRide = function(who, dest) rode = who .. "->" .. dest.name end
rideProblem = function() return nil end
state.owner = "Alaory"
penv.act("ride", { "base" })
pump()
startRide, rideProblem = start0, problem0
CHECK(rode == "Alaory->Base", "RIDE: a drone for the owner to the base (" .. tostring(rode) .. ")")
-- mining START goes to the loader
MINE.units[10] = { id = 10, role = "loader", dim = "overworld", log = {}, queue = {}, lastSeen = os.clock() }
penv.act("mine", { 10, "start" })
pump()
CHECK(MINE.units[10].queue[1] and MINE.units[10].queue[1].cmd == "start", "MINE: START to the loader")

-- FORGET from the pocket: refused while the turtle is online, works when it is gone
state.turtles[7].lastSeen = os.clock()
penv.act("forget", { 7 })
pump()
CHECK(state.turtles[7] and P.toast:find("online", 1, true), "FORGET refused for an online turtle")
state.turtles[9].lastSeen = os.clock() - 9999
penv.act("forget", { 9 })
pump()
CHECK(state.turtles[9] == nil, "FORGET removes an offline turtle: " .. tostring(P.toast))
-- DROP a gone miner from the pocket; the MINE tab shows it as gone first
MINE.units[11] = { id = 11, role = "miner", dim = "overworld", label = "Digger", leader = 10, log = {}, queue = {},
                   lastSeen = os.clock() - 9999, seenEpoch = os.epoch("utc") - 3600000 }
penv.refresh()
pump()
local gone = P.data.mining[1] and P.data.mining[1].gone
CHECK(gone and gone[1] and gone[1].id == 11, "status: the gone miner is listed")
P.tab = "mine"
CHECK(pcall(penv.draw), "MINE tab with a gone miner draws")
penv.act("minedrop", { 11 })
pump()
CHECK(MINE.units[11] == nil, "DROP from the pocket: " .. tostring(P.toast))
-- the WELCOME BACK report reaches the pocket
POCKET.out = {}
AWAY.on, AWAY.since, AWAY.snap = true, os.epoch("utc") - 3600000, {}
pcall(AWAY.back)
pump()
local wb = false
for _, n in ipairs(P.notes) do if n.title == "WELCOME BACK" then wb = true end end
CHECK(wb, "the WELCOME BACK report reaches the pocket")

-- security: a forged message, a replay, and an unpaired pocket do nothing
local before = POCKET.pockets[PID].lastN
POCKET.receive(PID, { t = "act", n = os.epoch("utc") * 100 + 99, a = "allstop", sig = "0000000000000000" })
CHECK(POCKET.pockets[PID].lastN == before, "a forged message (wrong signature) is ignored")
local old = { t = "act", n = before, a = "allhome", args = {} }
old.sig = penv.sign(P.key, old.t, old.n, old.a, old.args)
local n0 = #POCKET.out
POCKET.receive(PID, old)
CHECK(#POCKET.out == n0, "a replayed (old number) message is ignored")
-- after a base restart (lastN from the file is older): a message recorded 5 minutes ago is still refused
POCKET.pockets[PID].lastN = 0
local recorded = { t = "act", n = (os.epoch("utc") - 300000) * 100, a = "allhome", args = {} }
recorded.sig = penv.sign(P.key, recorded.t, recorded.n, recorded.a, recorded.args)
n0 = #POCKET.out
POCKET.receive(PID, recorded)
CHECK(#POCKET.out == n0, "a recorded old message is refused even after a restart")
POCKET.receive(77, { t = "act", n = os.epoch("utc") * 100, a = "allstop", sig = "x" })
local last = POCKET.out[#POCKET.out]
CHECK(last and last.id == 77 and last.msg.t == "unpaired", "an unknown pocket is told it is not paired")

-- the monitor's warnings reach the pocket
POCKET.out = {}
pushNote("WARNING", "Scout1 is STUCK", C.warn)
pump()
CHECK(P.notes[1] and P.notes[1].msg == "Scout1 is STUCK", "a warning arrives on the pocket")
P.tab = "msg" penv.draw()
CHECK(screenText():find("STUCK", 1, true), "MSG shows it")
-- console
local out = handleCommand("pocket") or {}
CHECK(table.concat(out, "\n"):find("MyPocket", 1, true), "console: pocket lists it")
handleCommand("pocket unpair " .. PID)
CHECK(POCKET.pockets[PID] == nil, "console: unpair")
