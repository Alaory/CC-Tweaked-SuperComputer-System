








TT = {}



function TT.sign(key, t, n, cmd, args)
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


function TT.findModem()
for _, name in ipairs(peripheral.getNames()) do
if SIDES[name] then
local okT, isM = pcall(peripheral.hasType, name, "modem")
if okT and isM then
local okW, w = pcall(peripheral.call, name, "isWireless")
if okW and w then return name end
end
end
end
end




function TT.markMissing(t, by)
if t.missing then return end
t.missing = os.epoch("utc")
TT.listDirty = true
pcall(MAP.reclaim, t.id)
local gear = {}
if type(t.gear) == "string" and t.gear ~= "" then gear[1] = t.gear end
local where = t.pos and t.pos.x and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "?"
local msg = (t.label or ("Turtle " .. t.id)) .. " is not at its last spot (" .. where .. ")" ..
(by and (" - " .. by .. " looked") or "") .. ". Probably deleted by a server crash" ..
(#gear > 0 and (". It carried: " .. table.concat(gear, ", ")) or "") ..
". FORGET it on the TURTLES tab when you are sure."
TT.log(t, "MISSING: " .. msg)
setPopup("TURTLE MISSING", msg, C.bad)
if sysLog then sysLog(msg, "WARNING") end
end


function TT.forget(id)
local t = state.turtles[id]
if not t then return false end
pcall(MAP.reclaim, id)
local q = MAP.queue
if q and q.ids then
for i = #q.ids, 1, -1 do if q.ids[i] == id then table.remove(q.ids, i) end end
end
state.turtles[id] = nil
if state.tSel == id then state.tSel = nil end
TT.listDirty = true
pcall(TT.saveList)
if sysLog then sysLog((t.label or ("Turtle " .. id)) .. " forgotten (removed from the list)", "INFO") end
return true
end




TT.COPYSTEP = 100000
function TT.realId(v)
v = tonumber(v) or 0
return v % TT.COPYSTEP, math.floor(v / TT.COPYSTEP)
end

TT.copyRes = {}
function TT.freeCopyNo(id)
local real = TT.realId(id)
for k = 1, 99 do
local v = k * TT.COPYSTEP + real
if not state.turtles[v] and not (MINE and MINE.units and MINE.units[v]) and not TT.copyRes[v] then
TT.copyRes[v] = true
return k
end
end
end

function TT.get(id)
local t = state.turtles[id]
if not t then
t = { id = id, label = "Turtle " .. id, log = {}, lastN = 0 }
state.turtles[id] = t
end
return t
end


function TT.log(t, msg)

local okD, now = pcall(os.date, "%H:%M")
table.insert(t.log, 1, { t = (okD and now) or textutils.formatTime(os.time(), true), msg = msg })
while #t.log > 40 do table.remove(t.log) end
end


function TT.online(t)
return t.lastSeen ~= nil and (os.clock() - t.lastSeen) < CONFIG.turtles.offlineAfter
end







function TT.factoryRole(t)
if not (t and FACTORY) then return nil end
local ok, b = pcall(function() return FACTORY.builderTurtle and FACTORY.builderTurtle() end)
if ok and b == t then return "builder" end
local ok2, c = pcall(function() return FACTORY.crafterTurtle and FACTORY.crafterTurtle() end)
if ok2 and c == t then return "crafter" end
return nil
end
local QUIET_TASK = { "waiting", "refuel", "gps", "install" }
local TROUBLE_TASK = { "backing up", "retracing", "planning a route", "following a planned route" }
function TT.stillFor(t)
return os.clock() - math.max(t.movedAt or os.clock(), t.taskAt or 0)
end
function TT.idleWhy(t)
local fuel = tonumber(t.fuel)
local minFuel = tonumber(CONFIG.map.surveyMinFuel) or 500
local q = MAP and MAP.queue
if not (t.pos and t.pos.x) then return "position unknown - press GPS LOCATE", C.warn end
if t.anchor then return "anchor - keeps the base loaded", C.purple end
if t.rescuerRole then return "rescuer - waits for a turtle in trouble", C.warn end
if t.party then return "in the SEARCH PARTY - waits for the others", C.label end
local fr = TT.factoryRole(t)
if fr then return "factory " .. fr .. " - stays at the factory (no surveys)", C.label end
if fuel and fuel < minFuel then
return "fuel " .. fuel .. " is below " .. minFuel .. " - " ..
((CONFIG.turtles.fuelChest and CONFIG.turtles.fuelChest.x) and "waiting for the fuel chest"
or "needs fuel at home (fuel chest under / next to its home)"), C.warn
end
if q then
if q.ids then
local mine = false
for _, i in ipairs(q.ids) do if i == t.id then mine = true end end
if not mine then return "not chosen for the running survey", C.warn end
end
if q.excluded and q.excluded[t.id] then return "taken off the survey by STOP - any button gives it back", C.warn end
if q.auto and MAP.full then return "auto-map paused - the map floppies are full", C.warn end
if t.queueAt and os.clock() - t.queueAt < 30 then return "just got survey spots - starting", C.good end
if t.packWait and q.wave then
return "waiting for the rest of the pack (they survey together, so one visit wakes them all)", C.label
end
local idle = t.idleSince and os.clock() - t.idleSince or 0

local w = q.lastWhy
if idle > 20 and w then
if w.near > 0 and w.near >= w.redo then
return "survey: " .. w.near .. " spots wait - " .. (w.who or "a player") .. " is near them", C.warn
end
if w.done > 0 then return "survey: skipping already mapped spots (" .. commas(w.done) .. " so far)", C.label end
end
if idle > 60 then return "a survey runs but it got nothing for " .. math.floor(idle) .. " s", C.warn end
return "waiting for the next survey spots", C.good
end
local a = MAP and MAP.auto
local home = t.home and t.pos and (math.abs(t.pos.x - t.home.x) + math.abs(t.pos.y - t.home.y)
+ math.abs(t.pos.z - t.home.z) <= 2)
local where = home and "at home" or (t.home and "away from home" or "no home yet")
if a and a.done then return "nothing to do (" .. where .. ") - the whole map is done", C.dim end
if a and not a.on then return "nothing to do (" .. where .. ") - auto-map is OFF (MAP tab)", C.warn end
return "nothing to do (" .. where .. ")", C.dim
end
function TT.status(t)
local now = os.clock()
if t.missing and not TT.online(t) then
return "missing", "MISSING", C.bad,
"not at its last spot" .. (t.pos and t.pos.x and (" " .. fmtPos(t.pos.x, t.pos.y, t.pos.z)) or "") ..
" - probably deleted (server crash). FORGET removes it"
end
if not TT.online(t) then
return "offline", "OFFLINE", C.bad,
((t.seenEpoch and ("last seen " .. TT.ago(t.seenEpoch)) or "never seen") ..
(t.rescuer and " - rescue on its way" or ""))
end
local task = tostring(t.task or "idle")
local busy = task ~= "idle"
local low = task:lower()
local fuel = tonumber(t.fuel)
if fuel and fuel < 20 then return "nofuel", "NO FUEL", C.bad, "fuel " .. fuel .. " - it cannot move" end

if t.stuck and not busy then
local sp, p = t.stuckPos, t.pos
local moved = sp and p and p.x and (math.abs(p.x - sp.x) + math.abs(p.z - sp.z) > 3)
if not moved then return "stuck", "STUCK", C.bad, tostring(t.stuck) end
end
if t.held then return "held", "STOPPED", C.warn, "stopped by you - any button (e.g. PING) releases it" end
if busy then
for _, w in ipairs(TROUBLE_TASK) do
if low:find(w, 1, true) then return "trouble", "FINDING A WAY", C.warn, "blocked - " .. task end
end
local quiet = false
for _, w in ipairs(QUIET_TASK) do if low:find(w, 1, true) then quiet = true end end
local still = TT.stillFor(t)
if not quiet and still > 90 then
return "still", "NOT MOVING", C.bad, "has not moved for " .. math.floor(still) .. " s - " .. task
end
local lab = t.anchor and "ANCHOR" or t.rescuerRole and "RESCUER" or "WORKING"
return "busy", lab, t.anchor and C.purple or C.good, task
end
local why, col = TT.idleWhy(t)
local lab = t.anchor and "ANCHOR" or t.rescuerRole and "RESCUER" or "IDLE"
return "idle", lab, (t.anchor and C.purple) or (t.rescuerRole and C.good) or (col == C.warn and C.warn or C.label), why
end




function TT.stallTick()
local now = os.clock()
for id, t in pairs(state.turtles) do
local key = TT.online(t) and not t.held and not t.anchor and TT.status(t)
if key == "still" and TT.stillFor(t) > 180 and (not t.stallAt or now - t.stallAt > 600) then
t.stallAt = now
TT.send(id, "stop", {}, true, true)
TT.log(t, "Not moving for " .. math.floor(TT.stillFor(t)) .. " s in '" .. tostring(t.task) ..
"' - stopped it so it can start again")
if sysLog then sysLog((t.label or ("Turtle " .. id)) .. " hung in its job (not moving 3 min) - stopped it", "WARNING") end
end
end
end


function TT.list()
local out = {}
for _, t in pairs(state.turtles) do out[#out + 1] = t end
table.sort(out, function(a, b) return a.id < b.id end)
return out
end


function TT.find(word)
local n = tonumber(word)
if n and state.turtles[n] then return state.turtles[n] end
for _, t in pairs(state.turtles) do
if t.label:lower() == tostring(word):lower() then return t end
end
end












TT.sess = {}
function TT.dupSeen(t, id, m, opt)
opt = opt or {}
local now = os.clock()
local S = TT.sess[id] or {}
TT.sess[id] = S
local s = S[m.ses]
if not s then


for _, v in pairs(S) do
if now - v.seen < 120 and type(t.pos) == "table" and t.pos.x then
t.dupAnchor = { x = t.pos.x, y = t.pos.y, z = t.pos.z }
end
end
s = { first = now }
S[m.ses] = s
end
local anchor = opt.anchor or t.home
if opt.where then anchor = t.dupAnchor or t.pos end
s.seen, s.dup = now, m.dup and true or nil
if type(m.pos) == "table" and m.pos.x then s.pos = m.pos end
for k, v in pairs(S) do if now - v.seen > 600 then S[k] = nil end end
if m.t == "result" and m.cmd == "becomecopy" and m.ok then s.promoted = true end
if s.promoted then return true end
local alive, n = {}, 0
for k, v in pairs(S) do
for k2, v2 in pairs(S) do
if k ~= k2 and not v.promoted and not v2.promoted and now - v.seen < 120 and now - v2.seen < 120
and v.seen > v2.first + 2 and v2.seen > v.first + 2 then
if not alive[k] then alive[k] = true n = n + 1 end
end
end
end
if n == 0 then

t.mainSes = m.ses
if t.dups then
t.dups = nil
TT.listDirty = true
if opt.log then opt.log("No extra copies any more") else TT.log(t, "No extra copies any more") end
end
return false
end


local known = t.dups and #t.dups > 0
if not (known and t.mainSes and alive[t.mainSes] and not (S[t.mainSes] or {}).dup) then
local best, bd
for k in pairs(alive) do
local v = S[k]
local d = (v.dup and 1e9 or 0)
if anchor and anchor.x and v.pos then
d = d + math.abs(v.pos.x - anchor.x) + math.abs((v.pos.y or 0) - (anchor.y or 0)) + math.abs(v.pos.z - anchor.z)
end
if not bd or d < bd then best, bd = k, d end
end
t.mainSes = best
end
local dups = {}
for k in pairs(alive) do
if k ~= t.mainSes then dups[#dups + 1] = { ses = k, pos = S[k].pos, dup = S[k].dup } end
end
local was = t.dups and #t.dups or 0
t.dups = dups
if #dups > was then
TT.listDirty = true
local where = {}
for _, d in ipairs(dups) do
where[#where + 1] = d.pos and fmtPos(d.pos.x, d.pos.y, d.pos.z) or "?"
end
local msg = (t.label or ("Turtle " .. id)) .. " exists " .. (#dups + 1) .. " TIMES (server crash copy) at " ..
table.concat(where, ", ") ..
((CONFIG.turtles.copies ~= "stop" and not (opt.canUse and not opt.canUse(m)))
and " - each copy becomes a turtle of its own" or " - the copies are stopped: break them")
pushNote("WARNING", msg, C.warn)
if sysLog then sysLog(msg, "WARNING") end
if opt.log then opt.log(msg) else TT.log(t, msg) end
end
if m.ses ~= t.mainSes then

local use = CONFIG.turtles.copies ~= "stop" and not (opt.canUse and not opt.canUse(m))
if (not s.stopAt or now - s.stopAt > 15) and (use or not m.dup) then
s.stopAt = now
if use then
s.k = s.k or TT.freeCopyNo(id)
end
if use and s.k then
local v = s.k * TT.COPYSTEP + TT.realId(id)
local msg = (t.label or ("Turtle " .. id)) .. ": its copy becomes a turtle of its own - '" ..
tostring(t.label or ("Turtle " .. TT.realId(id))):gsub("%s*%[c%d+%]%s*$", "") .. " [c" .. s.k ..
"]' (#" .. v .. ")"
if not s.told then
s.told = true
if sysLog then sysLog(msg, "INFO") end
if opt.log then opt.log(msg) else TT.log(t, msg) end
end
if opt.stop then opt.stop(m.ses, "becomecopy", { s.k })
else TT.send(id, "becomecopy", { s.k }, true, true, m.ses) end
elseif opt.stop then opt.stop(m.ses)
else TT.send(id, "dupstop", {}, true, true, m.ses) end
end
return true
end
return false
end


function TT.dupText(t)
if not (t.dups and #t.dups > 0) then return nil end
local where = {}
for _, d in ipairs(t.dups) do where[#where + 1] = d.pos and fmtPos(d.pos.x, d.pos.y, d.pos.z) or "?" end
if CONFIG.turtles.copies ~= "stop" then
return (#t.dups == 1 and "1 COPY" or (#t.dups .. " COPIES")) .. " of it (server crash) at " ..
table.concat(where, ", ") .. " - becoming turtle(s) of their own"
end
return (#t.dups == 1 and "1 COPY" or (#t.dups .. " COPIES")) .. " of it (server crash), stopped at " ..
table.concat(where, ", ") .. " - break them"
end

function TT.receive(id, m)
if type(m) ~= "table" or type(m.n) ~= "number" or type(m.t) ~= "string" then return end
if m.sig ~= TT.sign(CONFIG.turtles.key, m.t, m.n) then

TT.badKey = TT.badKey or {}
if not TT.badKey[id] or os.clock() - TT.badKey[id] > 600 then
TT.badKey[id] = os.clock()
pushNote("WARNING", "Turtle #" .. id .. (type(m.label) == "string" and (" (" .. m.label .. ")") or "") ..
" uses a DIFFERENT KEY - its messages are ignored. Give it the key from base_config.lua" ..
(m.mine and " (miner setup)" or ""), C.warn)
end
return
end

local cn = tonumber(m.copy)
if cn and cn >= 1 and cn < 100 then id = cn * TT.COPYSTEP + TT.realId(id) end
if m.mine then return MINE.receive(id, m) end
local t = TT.get(id)
if type(m.ses) == "string" and TT.dupSeen(t, id, m) then return end
if m.n <= (t.lastN or 0) then return end
t.lastN = m.n
local prevSeen = t.lastSeen
t.lastSeen = os.clock()
if t.missing then
t.missing = nil
TT.listDirty = true
TT.log(t, "It is back - it was not deleted after all")
if sysLog then sysLog((m.label or t.label or ("Turtle " .. id)) .. " reports again (was MISSING)", "DONE") end
end
if type(m.label) == "string" then t.label = m.label end
t.fuel, t.fuelMax, t.items = m.fuel, m.fuelMax, m.items

local op, np = t.pos, m.pos

if not t.movedAt or not prevSeen or os.clock() - prevSeen > CONFIG.turtles.offlineAfter then
t.movedAt = os.clock()
end
if type(np) == "table" and np.x and (not (op and op.x) or math.abs(np.x - op.x) + math.abs((np.y or 0) - (op.y or 0))
+ math.abs(np.z - op.z) >= 1) then
t.movedAt = os.clock()
end
if m.task ~= t.task then t.taskAt = os.clock() end
t.pos, t.task, t.home = m.pos, m.task, m.home

if m.stuck and not t.stuck and type(np) == "table" and np.x then t.stuckPos = { x = np.x, y = np.y, z = np.z } end
if not m.stuck then t.stuckPos = nil end
t.stuck, t.trail = m.stuck, m.trail
t.anchor, t.waiting = m.anchor, m.waiting
t.rec = m.rec

if t.stopAsk and ((m.t == "result" and m.cmd == "stop") or m.task == "idle") then t.stopAsk = nil end


if t.held and (m.t == "status" or m.t == "hello") and m.task and m.task ~= "idle" and not t.stopAsk then
TT.log(t, "Busy again after STOP (" .. tostring(m.task) .. ") - sending STOP again")
t.stopAsk = { tries = 1, last = os.clock() }
TT.send(id, "stop", {}, true, true)
end


if t.recall and (m.t == "status" or m.t == "hello") and m.task then
local task = tostring(m.task)
if task:find("^survey") or task:find("^scanning") then
if not t.recallAt or os.clock() - t.recallAt > 20 then
t.recallAt = os.clock()
TT.send(id, "stop", {}, true, true)
end
elseif task == "idle" then
t.recall, t.recallAt = nil, nil
TT.listDirty = true
if t.home then TT.send(id, "home", {}, true) end
TT.log(t, "Called back: going home")
end
end
local oldVer = t.ver
if m.ver then t.ver = m.ver end
t.updReady = m.updReady
if oldVer and oldVer ~= "?" and m.ver and m.ver ~= oldVer and CODE and m.ver == CODE.ver then
pcall(TT.updated, t, oldVer)
end
if m.gear then
t.gear = m.gear

local bad = (m.gear:find("NO CHUNKY", 1, true) and "has NO Chunky upgrade equipped (its chunk unloads when you leave)")
or (m.gear:find("WIRELESS modem", 1, true) and "has a normal Wireless Modem (~64 blocks) - it loses contact further away; use an Ender Modem")
if bad and t.gearWarned ~= bad then
t.gearWarned = bad
TT.log(t, "Equipment: " .. m.gear)
setPopup("TURTLE EQUIPMENT", (t.label or ("Turtle " .. id)) .. " " .. bad, C.warn)
elseif not bad then t.gearWarned = nil end
end
t.seenEpoch = os.epoch("utc")
TT.listDirty = true
if m.t == "updmiss" and CODE and m.want == CODE.ver and type(m.missing) == "table" then

for _, k in ipairs(m.missing) do
local p = CODE.pieces[tonumber(k) or 0]
if p then TT.send(id, "upd", { CODE.ver, tonumber(k), #CODE.pieces, p }, true) end
end
if TT.sending[id] then TT.sending[id] = os.clock() end
elseif m.t == "homebad" and tonumber(m.x) then

t.homeBad = t.homeBad or {}
t.homeBad[m.x .. "," .. m.y .. "," .. m.z] = true
t.homeOfferAt = nil
TT.log(t, "Offered home " .. m.x .. " " .. m.y .. " " .. m.z .. " is not free - offering another")
elseif m.t == "hello" then
TT.log(t, "Connected")

if CONFIG.turtles.dig ~= nil then TT.send(id, "setting", { "dig", tostring(CONFIG.turtles.dig == true) }, true) end
elseif m.t == "scan" then
local ok = pcall(MAP.addScan, m)
TT.log(t, ok and ("Scan received at " .. tostring(m.x) .. " " .. tostring(m.z))
or "Scan could not be stored")

if ok and m.sid then TT.send(id, "ack", { m.sid }, true) end
elseif m.t == "rescued" then
local target = tonumber(m.target) and TT.get(tonumber(m.target)) or nil
if target and not target.label then target.label = "Turtle " .. target.id end
local where = type(m.at) == "table" and (" at " .. tostring(m.at.x) .. " " .. tostring(m.at.y) .. " " .. tostring(m.at.z)) or ""
TT.log(t, (m.ok and "Rescue done: " or "Rescue failed: ") .. tostring(m.msg))
if target then
if type(m.at) == "table" and tonumber(m.at.x) then
target.pos = { x = tonumber(m.at.x), y = tonumber(m.at.y), z = tonumber(m.at.z), f = target.pos and target.pos.f }
end
TT.log(target, (m.ok and "Rescued by " or "Rescue by ") .. t.label .. (m.ok and "" or " failed") .. where)
target.rescuer, target.rescueKind = nil, nil

if not m.ok and tostring(m.msg):find("not found within", 1, true) and not TT.online(target) then
TT.markMissing(target, t.label)
end
if m.ok then target.rescueTries = nil end

if m.ok and m.mode == "supply" then
TT.send(target.id, "refuel", {})
if tostring(m.gave or ""):find("pick", 1, true) then TT.send(target.id, "setting", { "dig", "true" }) end
TT.send(target.id, "home", {})
end
end
setToast((m.ok and "Rescue done: " or "Rescue failed: ") .. tostring(m.msg), m.ok and C.good or C.warn, 8)
if t.rescuerRole and not t.held then TT.send(id, "home", {}) end
elseif m.t == "learn" then
pcall(KNOW.learn, m)
elseif m.t == "need" then

local x1, z1 = tonumber(m.x1), tonumber(m.z1)
local x2, z2 = tonumber(m.x2), tonumber(m.z2)
if x1 and z1 and x2 and z2 then
local okA, walls, dead = pcall(KNOW.around, x1, z1, x2, z2)
if okA then

local okC, cruise = pcall(TT.cruiseHeight, tonumber(m.fx), tonumber(m.fz), tonumber(m.tx), tonumber(m.tz))
TT.send(id, "know", { walls, dead, EXITROUTE and EXITROUTE.route or "none",
EXITROUTE and EXITROUTE.t or 0, (okC and cruise) or "none" }, true)
end
end
elseif m.t == "exitroute" and type(m.route) == "string" then
local n = 0
for _ in m.route:gmatch(";") do n = n + 1 end
EXITROUTE = { route = m.route, t = os.epoch("utc"), n = n + 1, by = t.label }
KNOW.dirty = true
TT.log(t, "Exit route saved (" .. (n + 1) .. " corners) - shared with all turtles")
elseif m.t == "result" and m.cmd == "upd" then
TT.log(t, "Update: " .. tostring(m.msg))
if not m.ok then
setToast(t.label .. ": update failed - " .. tostring(m.msg), C.warn)
TT.sending[id] = nil
t.updRetry, t.updState, t.updNote = os.clock() + 120, "retry", tostring(m.msg)
elseif tostring(m.msg):find("ready", 1, true) then
setToast(t.label .. " got " .. (CODE and TT.verName(CODE.ver) or "the update") ..
" - installs when its job is done", C.label)
end
elseif m.t == "look" then
TT.lookIn(t, m)
elseif m.t == "turtlesseen" then
pcall(TT.partySeen, id, m.seen)
elseif m.t == "recipe" then
if FACTORY and type(m.recipe) == "table" then pcall(FACTORY.learned, id, m.recipe) end
elseif m.t == "result" then
if m.cmd == "drive" then
t.driveMsg = { ok = m.ok, msg = tostring(m.msg), at = os.clock() }

t.driveAnyway = (not m.ok and tostring(m.msg):find("DIG ANYWAY", 1, true)) and t.driveLast or nil
end
if m.cmd == "fuelup" and TT.fuelTrip and TT.fuelTrip.id == id then TT.fuelTrip = nil end
if m.cmd == "surveypts" and MAP.batchResult then pcall(MAP.batchResult, id, m.ok) end
if m.cmd == "build" and FACTORY then pcall(FACTORY.result, id, m.ok, m.msg) end
if m.cmd == "craft" and FACTORY then pcall(FACTORY.craftResult, id, m.ok, m.msg) end
if m.cmd == "restart" and not m.ok and sysLog then sysLog(t.label .. ": " .. tostring(m.msg), "ERROR") end
TT.log(t, (m.ok and "Done: " or "Failed: ") .. tostring(m.msg))
if not m.ok then setToast(t.label .. ": " .. tostring(m.msg), C.warn, 6) end
end
if not state.tSel then state.tSel = id end
os.queueEvent("inv_update")
end








local KNOW_LIFE = { hard = 6 * 3600000 + 600000, short = 32 * 60000, door = 11 * 60000 }
local DEAD_LIFE = 3 * 3600000
KNOW = { walls = {}, dead = {}, n = 0, dirty = false, saved = 0 }
EXITROUTE = nil

local function epoch() return os.epoch("utc") end


function KNOW.prune()
local t = epoch()
for k, w in pairs(KNOW.walls) do
if t - w.t > (KNOW_LIFE[w.k] or KNOW_LIFE.hard) then KNOW.walls[k] = nil KNOW.n = KNOW.n - 1 end
end
for k, d in pairs(KNOW.dead) do
if t - d.t > DEAD_LIFE then KNOW.dead[k] = nil end
end
if KNOW.n > (CONFIG.turtles.knowMax or 20000) then
local list = {}
for k, w in pairs(KNOW.walls) do list[#list + 1] = { k = k, t = w.t } end
table.sort(list, function(a, b) return a.t < b.t end)
for i = 1, KNOW.n - CONFIG.turtles.knowMax do KNOW.walls[list[i].k] = nil end
KNOW.n = CONFIG.turtles.knowMax
end
end


function KNOW.save()
KNOW.prune()
local path = dataFile(CONFIG.turtles.knowFile, true)
local function text()
local lines = {}
for k, w in pairs(KNOW.walls) do lines[#lines + 1] = "W " .. k .. "," .. w.k .. "," .. w.t end
for k, d in pairs(KNOW.dead) do lines[#lines + 1] = "D " .. k .. "," .. d.t end
return table.concat(lines, "\n") .. "\n"
end
local ok = saveFileSafe(path, text())
local tries = 0
while not ok and KNOW.n > 200 and tries < 4 do

tries = tries + 1
local was = CONFIG.turtles.knowMax
CONFIG.turtles.knowMax = math.floor(KNOW.n / 2)
KNOW.prune()
CONFIG.turtles.knowMax = was
ok = saveFileSafe(path, text())
end
if ok then dropOldCopy(CONFIG.turtles.knowFile, path, KNOW.n == 0) end
if EXITROUTE then
local f = fs.open(CONFIG.turtles.exitFile, "w")
if f then f.write(textutils.serialize(EXITROUTE)) f.close() end
elseif fs.exists(CONFIG.turtles.exitFile) then
fs.delete(CONFIG.turtles.exitFile)
end
KNOW.dirty, KNOW.saved = false, os.clock()
end


function KNOW.load()
TT.loadList()
if fs.exists(dataFile(CONFIG.turtles.knowFile)) then
local h = fs.open(dataFile(CONFIG.turtles.knowFile), "r")
while h do
local line = h.readLine()
if not line then break end
local x, y, z, k, t = line:match("^W (-?%d+),(-?%d+),(-?%d+),(%a+),(%d+)$")
if x then
KNOW.walls[x .. "," .. y .. "," .. z] = { k = k, t = tonumber(t) }
KNOW.n = KNOW.n + 1
else
local dx, dy, dz, dt = line:match("^D (-?%d+),(-?%d+),(-?%d+),(%d+)$")
if dx then KNOW.dead[dx .. "," .. dy .. "," .. dz] = { t = tonumber(dt) } end
end
end
if h then h.close() end
end
if fs.exists(CONFIG.turtles.exitFile) then
local f = fs.open(CONFIG.turtles.exitFile, "r")
if f then
local t = textutils.unserialize(f.readAll() or "")
f.close()
if type(t) == "table" and t.route then EXITROUTE = t end
end
end
KNOW.prune()
end


function KNOW.learn(m)
local t = epoch()
for x, y, z, k in tostring(m.walls or ""):gmatch("(-?%d+),(-?%d+),(-?%d+),(%a+)") do
local key = x .. "," .. y .. "," .. z
if not KNOW.walls[key] then KNOW.n = KNOW.n + 1 end
KNOW.walls[key] = { k = k, t = t }
end
for x, y, z in tostring(m.clears or ""):gmatch("(-?%d+),(-?%d+),(-?%d+)") do
local key = x .. "," .. y .. "," .. z
if KNOW.walls[key] and KNOW.walls[key].t <= t then KNOW.walls[key] = nil KNOW.n = KNOW.n - 1 end
end
for x, y, z in tostring(m.dead or ""):gmatch("(-?%d+),(-?%d+),(-?%d+)") do
KNOW.dead[x .. "," .. y .. "," .. z] = { t = t }
end
KNOW.dirty = true
end


function KNOW.around(x1, z1, x2, z2)
local m = 48
x1, z1, x2, z2 = x1 - m, z1 - m, x2 + m, z2 + m
local list = {}
for k, w in pairs(KNOW.walls) do
local x, z = k:match("^(-?%d+),%-?%d+,(-?%d+)$")
x, z = tonumber(x), tonumber(z)
if x and x >= x1 and x <= x2 and z >= z1 and z <= z2 then list[#list + 1] = { k = k, w = w } end
end
table.sort(list, function(a, b) return a.w.t > b.w.t end)
local walls = {}
for i = 1, math.min(#list, 2500) do walls[i] = list[i].k .. "," .. list[i].w.k .. "," .. list[i].w.t end
local dead = {}
for k, d in pairs(KNOW.dead) do
local x, z = k:match("^(-?%d+),%-?%d+,(-?%d+)$")
x, z = tonumber(x), tonumber(z)
if x and x >= x1 and x <= x2 and z >= z1 and z <= z2 then dead[#dead + 1] = k .. "," .. d.t end
end
return table.concat(walls, ";"), table.concat(dead, ";")
end






CODE = nil
local CHUNK = 8000



local VER_FILE = "turtle_versions.dat"
TT.versions = { next = 1, byHash = {} }
do
if fs.exists(VER_FILE) then
local h = fs.open(VER_FILE, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if type(t) == "table" and type(t.byHash) == "table" then TT.versions = t end
end
end

function TT.verName(hash)
if not hash or hash == "?" then return "?" end
local n = TT.versions.byHash[hash]
return n and ("v" .. n) or "old"
end




function TT.workYield()
if TT.yieldCo and coroutine.running() == TT.yieldCo then
os.queueEvent("base_working")
os.pullEvent("base_working")
end
end
local function codeHash(str)
local h1, h2 = 5381, 52711
for i = 1, #str do
if i % 16384 == 0 then TT.workYield() end
local c = str:byte(i)
h1 = (h1 * 33 + c) % 4294967296
h2 = (h2 * 131 + c * 7 + i) % 4294967296
end
return string.format("%08x%08x", h1, h2)
end


local function setStr(code, name, val)
val = tostring(val):gsub("%%", "%%%%")
return (code:gsub('(\n%s*' .. name .. '%s*=%s*)"[^"\n]*"', '%1"' .. val .. '"', 1))
end



local function modTime(p)
local ok, a = pcall(function() return fs.attributes and fs.attributes(p) end)
return (ok and type(a) == "table" and tonumber(a.modified)) or 0
end

function TT.codePath()
local name = CONFIG.turtles.codeFile or "node.lua"
local here = fs.combine(BASE_DIR or "", name)


local top = name
if top ~= here and fs.exists(top) and (not fs.exists(here) or modTime(top) > modTime(here)) then
return top
end
if fs.exists(here) then return here end
for _, d in ipairs(mountedDisks()) do
local p = fs.combine(d.mount, name)
if fs.exists(p) then return p end
end
return here
end





function TT.shrinkCode(text)
local out, inBlock = {}, false
for line in (text .. "\n"):gmatch("(.-)\n") do
local t = line:match("^%s*(.-)$")
if inBlock then
if line:find("]]", 1, true) then inBlock = false end
t = ""
elseif t:sub(1, 4) == "--[[" then
if not t:find("]]", 5, true) then inBlock = true end
t = ""
elseif t:sub(1, 2) == "--" then
t = ""
end
out[#out + 1] = t
if #out % 500 == 0 then TT.workYield() end
end
if out[#out] == "" then out[#out] = nil end
return table.concat(out, "\n") .. "\n"
end


function TT.codeLoad(force)
local path = TT.codePath()
if not fs.exists(path) then CODE = nil return end

local mod = path .. ":" .. modTime(path) .. ":" .. fs.getSize(path)
if CODE and CODE.mod == mod and not force then return end
local h = fs.open(path, "r")
local text = h.readAll() or ""
h.close()
text = setStr(text, "protocol", CONFIG.turtles.protocol)
text = setStr(text, "baseName", CONFIG.turtles.hostname)
text = setStr(text, "key", CONFIG.turtles.key)


TT.workYield()
local okC, errC = load(text, "node", "t", {})
TT.codeError = (not okC) and (path .. ": " .. tostring(errC)) or nil
TT.workYield()
if okC then

local okS, small = pcall(TT.shrinkCode, text)
if okS and load(small, "node", "t", {}) then text = small end
end
if not okC then
if not (CODE and CODE.badMod == mod) then
setPopup("TURTLE PROGRAM", "The new node.lua does not compile - not sent to the turtles: " ..
tostring(errC), C.bad)
end
if CODE then CODE.badMod = mod end
return
end
local pieces = {}
for i = 1, #text, CHUNK do pieces[#pieces + 1] = text:sub(i, i + CHUNK - 1) end
local ver = codeHash(text)
if CODE and CODE.ver == ver then CODE.mod, CODE.path = mod, path return end
CODE = { text = text, ver = ver, mod = mod, pieces = pieces, path = path }
if not TT.versions.byHash[CODE.ver] then
TT.versions.byHash[CODE.ver] = TT.versions.next
TT.versions.next = TT.versions.next + 1
saveFileSafe(VER_FILE, serialSmall(TT.versions))
if next(state.turtles) then
setToast("New turtle program " .. TT.verName(CODE.ver) .. " - updating the turtles one by one", C.label)
end
if sysLog then sysLog("New turtle program " .. TT.verName(CODE.ver) .. " (" .. #text .. " bytes)", "INFO") end
end
for _, t in pairs(state.turtles) do t.updSent, t.updRetry, t.updState = nil, nil, nil end
TT.updating, TT.sending = nil, {}
TT.writeInstallDisk()
end


function TT.pushCode(id)
if not CODE then return false end
local t = state.turtles[id]
for i, p in ipairs(CODE.pieces) do
TT.send(id, "upd", { CODE.ver, i, #CODE.pieces, p }, true)
end
if t then
t.updSent = os.clock()
TT.log(t, "Sending the turtle program update " .. TT.verName(CODE.ver))
end
return true
end







TT.sending = {}
function TT.updateTick()
if not CODE then return end
local forced = TT.updateForce and os.clock() < TT.updateForce
if not CONFIG.turtles.autoUpdate and not forced then return end

if TT.codeSeenVer ~= CODE.ver then TT.codeSeenVer, TT.codeSeenAt = CODE.ver, os.clock() end
TT.updWaiting = false
if not forced and CONFIG.turtles.updateWhenAway ~= false and AWAY and not AWAY.on
and AWAY.ownerOnline() == true and os.clock() - TT.codeSeenAt < 7200 then
TT.updWaiting = true
return
end
local now = os.clock()


if forced then
local left = false
for _, t in pairs(state.turtles) do if TT.online(t) and TT.outdated(t) then left = true break end end
if not left then TT.updateForce = nil end
end
local busy = 0
for id, t0 in pairs(TT.sending) do
local t = state.turtles[id]
if not t or t.ver == CODE.ver or t.updReady == CODE.ver then
TT.sending[id] = nil
if t then t.updState = (t.updReady == CODE.ver and t.ver ~= CODE.ver) and "ready" or nil end
elseif now - t0 > 45 then
TT.sending[id] = nil
t.updRetry, t.updState = now + 120, "retry"
t.updNote = "no answer in 45 s (scanning? out of range?)"
TT.log(t, "No answer to the update - trying again in 2 min")
else
busy = busy + 1
end
end
for _, t in ipairs(TT.list()) do
if busy >= 3 then break end
if TT.online(t) and TT.outdated(t) and t.updReady ~= CODE.ver and not TT.sending[t.id]
and (not t.updRetry or now > t.updRetry) then
TT.pushCode(t.id)
TT.sending[t.id], t.updState = now, "sending"
busy = busy + 1
end
end
TT.updating = next(TT.sending) and { id = next(TT.sending), t0 = now } or nil
end






function TT.forceUpdate()
pcall(TT.codeLoad, true)
if not CODE then return nil end
TT.updateForce = os.clock() + 3600
local n = 0
for _, t in pairs(state.turtles) do
if TT.online(t) and TT.outdated(t) then
n = n + 1
t.updRetry = nil
if t.updState == "retry" then t.updState = nil end
if t.updReady == CODE.ver and t.task and t.task ~= "idle" then
TT.send(t.id, "stop", {}, true, true)
TT.log(t, "UPDATE TURTLES: stopping its job so it installs " .. TT.verName(CODE.ver) .. " now")
end
end
end
return n
end


function TT.updated(t, oldVer)
TT.log(t, "Updated: " .. TT.verName(oldVer) .. " -> " .. TT.verName(t.ver))
setToast(t.label .. " updated to " .. TT.verName(t.ver), C.good)
if not CODE then return end
local n, all = 0, true
for _, o in pairs(state.turtles) do
if TT.online(o) then
n = n + 1
if o.ver ~= CODE.ver then all = false end
end
end
if all and n > 1 then setToast("All " .. n .. " turtles run " .. TT.verName(CODE.ver), C.good) end
end




function TT.outdated(t)
return CODE ~= nil and t.ver ~= nil and t.ver ~= CODE.ver
end



local INSTALLER = [[
-- TURTLE INSTALLER (kept up to date by the base computer).
-- Put a NEW turtle next to the disk drive with this disk and turn it on.
if not turtle then
  -- on the base computer (it booted from this floppy): start the base program instead
  for _, pattern in ipairs({ "inventory.lua", "*/inventory.lua", "*/*/inventory.lua" }) do
    for _, p in ipairs(fs.find(pattern)) do
      if fs.getDrive(p) == "hdd" then
        if fs.exists("startup.lua") then shell.run("/startup.lua") else shell.run("/" .. p) end
        return
      end
    end
  end
  print("This disk installs the turtle program - use it with a turtle.")
  return
end
local here = fs.getDir(shell.getRunningProgram())
local src = fs.combine(here, "node.lua")
if not fs.exists(src) then printError("node.lua is missing on this disk") return end
if not os.getComputerLabel() then os.setComputerLabel("Turtle " .. os.getComputerID()) end
if fs.exists("startup.lua") then
  if fs.exists("startup.old") then fs.delete("startup.old") end
  fs.move("startup.lua", "startup.old")
end
fs.copy(src, "startup.lua")
print("Turtle program installed on " .. os.getComputerLabel() .. ".")
print("Needs: an Ender (or Wireless) Modem and the Chunky upgrade equipped, fuel inside.")
print("Move it away from the drive or take the disk out. Starting now...")
sleep(2)
shell.run("/startup.lua")
]]




function TT.installDrive()
local n = CONFIG.turtles.installDrive or "bottom"
if peripheral.isPresent(n) and peripheral.getType(n) == "drive" then return n end
end


local function writeInstaller(d)
local function put(file, text)
local p = fs.combine(d.mount, file)
if fs.exists(p) then
local h0 = fs.open(p, "r")
local old = h0 and h0.readAll()
if h0 then h0.close() end
if old == text then return true end
end
local h = fs.open(p, "w")
if not h then return false end
local ok = pcall(h.write, text)
pcall(h.close)
return ok
end
local ok = put("startup.lua", INSTALLER) and put("node.lua", CODE.text) and put("turtle_installer", CODE.ver)
pcall(disk.setLabel, d.name, "Turtle installer " .. TT.verName(CODE.ver))
state.installDisk = d.name
return ok
end



function TT.prepareInstallFloppy(quiet)
local drive = TT.installDrive()
if not drive or not disk or not disk.hasData(drive) then return end
if not CODE then
setToast("No node.lua on this computer - cannot make an install floppy", C.warn)
return
end
local d
for _, m in ipairs(mountedDisks()) do if m.name == drive then d = m end end
if not d then return end
if d.data then
setPopup("INSTALL DRIVE", "That is a data floppy (map) - it is not changed. Put an EMPTY floppy in.", C.warn)
return
end
if not d.empty and not d.installer then
setPopup("INSTALL DRIVE", "That floppy has other files on it - it is not changed. Put an EMPTY floppy in.", C.warn)
return
end
local fresh = d.installer and fs.exists(fs.combine(d.mount, "turtle_installer"))
if fresh then
local h = fs.open(fs.combine(d.mount, "turtle_installer"), "r")
fresh = h and h.readAll() == CODE.ver
if h then h.close() end
end
if writeInstaller(d) then
if not (quiet and fresh) then
setToast("Install floppy ready (" .. TT.verName(CODE.ver) .. ") - take it out of the drive for a rescue turtle",
C.good)
end
else
setToast("Could not write the install floppy (full?)", C.bad)
end
end




function TT.writeInstallDisk()
if not CODE or not disk then return end
local disks, target = mountedDisks(), {}
local drive = TT.installDrive()
for _, d in ipairs(disks) do
if d.installer or (drive and d.name == drive and d.empty) then target[#target + 1] = d end
end
if #target == 0 and not drive then
for _, d in ipairs(disks) do if d.empty and not d.data then target[1] = d break end end
end
for _, d in ipairs(target) do writeInstaller(d) end
end




TT.listDirty = false

function TT.saveList()
local out = {}
for id, t in pairs(state.turtles) do
out[#out + 1] = { id = id, label = t.label, pos = t.pos, home = t.home, seen = t.seenEpoch,
task = t.task, ver = t.ver, gear = t.gear, anchor = t.anchor, rescuerRole = t.rescuerRole,
held = t.held, recall = t.recall, missing = t.missing }
end
saveFileSafe(dataPath(CONFIG.turtles.listFile), serialSmall(out))
TT.listDirty = false
end

function TT.loadList()
local lp = dataPath(CONFIG.turtles.listFile)
if not fs.exists(lp) then return end
local h = fs.open(lp, "r")
local list = textutils.unserialize(h.readAll() or "")
h.close()
if type(list) ~= "table" then return end
for _, e in ipairs(list) do
if type(e) == "table" and tonumber(e.id) then
local t = TT.get(tonumber(e.id))
if e.label then t.label = e.label end
t.pos, t.home, t.seenEpoch, t.task = e.pos, e.home, e.seen, e.task
t.ver, t.gear, t.anchor = e.ver, e.gear, e.anchor
t.rescuerRole = e.rescuerRole
t.held = e.held
t.recall = e.recall
t.missing = e.missing
end
end
end

function TT.ago(epochMs)
if not epochMs then return "never" end
local s = math.floor((os.epoch("utc") - epochMs) / 1000)
if s < 90 then return s .. " s ago" end
if s < 5400 then return math.floor(s / 60) .. " min ago" end
if s < 172800 then return math.floor(s / 3600) .. " h ago" end
return math.floor(s / 86400) .. " days ago"
end


local function hasGear(t, what)
return type(t.gear) == "string" and ("," .. t.gear .. ","):find("," .. what .. ",", 1, true) ~= nil
end


function TT.rescueMode(t)
if TT.online(t) then return "supply" end
return "install"
end

function TT.pickRescuer(target, mode, x, z)
local best, bestD
for id, t in pairs(state.turtles) do
if id ~= target.id and TT.online(t) and not t.anchor and not t.held and (t.task == nil or t.task == "idle")
and t.pos and t.pos.x then
local ok
if mode == "install" then ok = hasGear(t, "drive") and hasGear(t, "floppy")
else ok = hasGear(t, "fuel") or hasGear(t, "pick") end
if ok then
local d = math.abs(t.pos.x - x) + math.abs(t.pos.z - z)
if not bestD or d < bestD then best, bestD = t, d end
end
end
end
return best
end

function TT.rescueReady(t)
local miss = {}
if not hasGear(t, "drive") then miss[#miss + 1] = "a Disk Drive" end
if not hasGear(t, "floppy") then miss[#miss + 1] = "the install floppy" end
if not hasGear(t, "scanner") then miss[#miss + 1] = "a Geo Scanner" end
if #miss == 0 then
return true, hasGear(t, "pick") and "can rescue lost turtles"
or "can rescue (no pickaxe: Disk Drives are left behind)", 0
end
if hasGear(t, "scanner") then

return false, "wakes up lost turtles; reinstalling also needs " .. table.concat(miss, " + "), #miss
end
return false, "needs " .. table.concat(miss, " + "), #miss
end



function TT.findLost(radius, cx, cy, cz)
if not cx then
local b = state.basePos or CONFIG.drone.home
if not b then return false, "base position unknown - use: findlost <radius> <x> <y> <z>" end
cx, cy, cz = b.x, b.y, b.z
end
local best, bestD
local why, whyMiss = "no turtle is online and idle", math.huge
for id, t in pairs(state.turtles) do
if TT.online(t) and not t.anchor and not t.held and (t.task == nil or t.task == "idle") and t.pos and t.pos.x then
local ok, msg, nmiss = TT.rescueReady(t)
if ok then
local d = math.abs(t.pos.x - cx) + math.abs(t.pos.z - cz)
if not bestD or d < bestD then best, bestD = t, d end
elseif nmiss < whyMiss then
why, whyMiss = t.label .. " " .. msg, nmiss
end
end
end
if not best then return false, why end
local skip = {}
for id, t in pairs(state.turtles) do if TT.online(t) then skip[#skip + 1] = id end end
radius = radius or 96
TT.send(best.id, "sweep", { cx, cy, cz, radius, table.concat(skip, ",") })
TT.log(best, "Searching for lost turtles within " .. radius .. " blocks of " .. cx .. " " .. cy .. " " .. cz)
return true, best.label .. " is searching for lost turtles (" .. radius .. " blocks around the base)"
end




function TT.rescue(targetId, x, y, z, radius, forced, visit)
local target = state.turtles[targetId]
if not target then
target = TT.get(targetId)
target.label = target.label or ("Turtle " .. targetId)
end
if not x then
if not (target.pos and target.pos.x) then return false, "its last position is unknown - give x y z" end
x, y, z = target.pos.x, target.pos.y, target.pos.z
end
local mode = TT.rescueMode(target)
local r = forced or TT.pickRescuer(target, mode, x, z)
if forced then

if mode == "install" and not visit and not (hasGear(forced, "drive") and hasGear(forced, "floppy")) then
return false, forced.label .. " needs a Disk Drive and the install floppy to reinstall a turtle"
elseif mode == "supply" and not (hasGear(forced, "fuel") or hasGear(forced, "pick")) then
return false, forced.label .. " needs fuel (coal ...) or a spare pickaxe to bring"
end
end
if not r then
return false, mode == "install"
and "no free turtle with a Disk Drive + the install floppy (and a Geo Scanner to search)"
or "no free turtle with fuel or a spare pickaxe"
end
TT.send(r.id, "rescue", { target.id, x, y, z, mode, radius or 24 })
TT.log(target, "Rescue on its way: " .. r.label .. " (" .. mode .. ")")
target.rescuer = r.id
return true, r.label .. " is on its way (" .. (mode == "install" and "reinstall" or "supplies") .. ")"
end







function TT.cruiseHeight(fx, fz, tx, tz)
if not (fx and fz and tx and tz) then return nil end
local top, known, total = -64, 0, 0
local function look(x, z)
total = total + 1
local h = MAP.get(x, z)
if h then
known = known + 1
if h + 3 > top then top = h + 3 end
return
end
h = MAP.getOverview(x, z)
if h then
known = known + 1
if h + 10 > top then top = h + 10 end
end
end
local function line(ax, az, bx, bz)
local n = math.max(math.abs(bx - ax), math.abs(bz - az))
local steps = math.max(1, math.floor(n / 4))
for i = 0, steps do
local x = ax + math.floor((bx - ax) * i / steps + 0.5)
local z = az + math.floor((bz - az) * i / steps + 0.5)
for d = -2, 2, 2 do
if ax == bx then look(x + d, z) else look(x, z + d) end
end
end
end
line(fx, fz, tx, fz)
line(tx, fz, tx, tz)
if total == 0 or known / total < 0.7 then return nil end
return math.floor(top)
end











TT.startedAt = os.clock()
local RETRY_AFTER, MAX_TRIES = 1800, 3


function TT.rescuers()
local list = {}
for _, t in pairs(state.turtles) do if t.rescuerRole then list[#list + 1] = t end end
table.sort(list, function(a, b) return a.id < b.id end)
return list
end


local function problemOf(t)
local now = os.clock()
if t.missing and not TT.online(t) then return nil end
if TT.online(t) then
t.offlineNoted = nil
local idle = (t.task == nil or t.task == "idle")
local fuel = tonumber(t.fuel)
if fuel and fuel < 20 then t.lowFuelSince = t.lowFuelSince or now else t.lowFuelSince = nil end
if t.stuck and idle then t.stuckSince = t.stuckSince or now else t.stuckSince = nil end
if t.lowFuelSince and now - t.lowFuelSince > 60 then return "fuel" end
if t.stuckSince and now - t.stuckSince > 60 then return "stuck" end
return nil
end

if not (t.pos and t.pos.x and t.seenEpoch) then return nil end
local after = tonumber(CONFIG.turtles.rescueAfter) or 180
if (os.epoch("utc") - t.seenEpoch) / 1000 < after then return nil end
return "lost"
end


function TT.patrolTick()
local rescuers = TT.rescuers()
if #rescuers == 0 then return end
local now = os.clock()
local total, offline = 0, 0
for _, t in pairs(state.turtles) do
if not t.rescuerRole and not t.missing then
total = total + 1
if not TT.online(t) then offline = offline + 1 end
end
end
local massOffline = total >= 2 and offline * 2 >= total
local warmingUp = now - TT.startedAt < 300


local problems = {}
for id, t in pairs(state.turtles) do
if not t.rescuerRole then problems[id] = problemOf(t) end

if TT.online(t) and not problems[id] and not t.rescuer then
t.fineSince = t.fineSince or now
if now - t.fineSince > 300 then t.rescueTries, t.rescueAt = nil, nil end
else
t.fineSince = nil
end
end
for _, t in pairs(state.turtles) do

if t.rescuer and t.rescueKind then
local r = state.turtles[t.rescuer]
local fine = (t.rescueKind == "lost" and TT.online(t))
or (t.rescueKind ~= "lost" and TT.online(t) and not problems[t.id])
if fine then
if r then
TT.send(r.id, "stop", {})
TT.send(r.id, "home", {})
TT.log(r, "Rescue of " .. t.label .. " called off - it is fine again")
end
TT.log(t, "Fine again - rescue called off")
t.rescuer, t.rescueKind = nil, nil
t.rescueTries, t.rescueAt = nil, nil
end
end
end
for _, r in ipairs(rescuers) do
local free = TT.online(r) and (r.task == nil or r.task == "idle") and not r.stopAsk and not r.held
if free then

local pick, pickKind, pickScore
for _, t in pairs(state.turtles) do
if not t.rescuerRole and not t.rescuer and (t.rescueTries or 0) < MAX_TRIES
and (not t.rescueAt or now - t.rescueAt > RETRY_AFTER) then
local kind = problems[t.id]


local silent = t.seenEpoch and (os.epoch("utc") - t.seenEpoch) / 1000 or 0
if kind == "lost" and (warmingUp or (massOffline and silent < (tonumber(CONFIG.turtles.rescueAfterCrash) or 600))) then
kind = nil
end

if kind == "lost" then
for _, o in pairs(state.turtles) do
if o.rescuer and o.rescueKind == "lost" and o.pos and o.pos.x and t.pos and t.pos.x
and math.abs(o.pos.x - t.pos.x) <= 48 and math.abs(o.pos.z - t.pos.z) <= 48 then kind = nil end
end
end
if kind then

local score = 0
if kind == "lost" then
for oid, o in pairs(state.turtles) do
if problems[oid] == "lost" and o.pos and o.pos.x and t.pos and t.pos.x
and math.abs(o.pos.x - t.pos.x) <= 48 and math.abs(o.pos.z - t.pos.z) <= 48 then score = score + 1 end
end
else
score = 1000
end
if not pick or score > pickScore then pick, pickKind, pickScore = t, kind, score end
end
end
end
if pick then
local ok, msg = TT.rescue(pick.id, nil, nil, nil, nil, r, pickKind == "lost")
pick.rescueAt, pick.rescueTries = now, (pick.rescueTries or 0) + 1
if ok then
pick.rescueKind = pickKind
if pickKind == "lost" and (pickScore or 0) > 1 then
TT.log(r, "Going to " .. pick.label .. " - " .. pickScore .. " offline turtles are there together")
end
setToast("Rescuer " .. r.label .. " sent to " .. pick.label .. " (" ..
(pickKind == "lost" and "offline - going there wakes it up" or pickKind == "fuel" and "no fuel" or "stuck") .. ")",
C.label)
else
TT.log(r, "Cannot rescue " .. pick.label .. ": " .. tostring(msg))
end
if pick.rescueTries >= MAX_TRIES and not ok then
setPopup("TURTLE NEEDS YOU", pick.label .. " could not be rescued " .. MAX_TRIES .. " times - please look at it (" ..
(pick.pos and fmtPos(pick.pos.x, pick.pos.y, pick.pos.z) or "position unknown") .. ")", C.warn)
end
end
end
end
end


function TT.setDig(on)
setSetting("turtles.dig", on and true or false)
local n = 0
for id, t in pairs(state.turtles) do
if TT.online(t) then TT.send(id, "setting", { "dig", tostring(on and true or false) }, true) n = n + 1 end
end
return n
end







function TT.threats()
local range = tonumber(CONFIG.turtles.avoidRange or 100) or 0
if range <= 0 then return {}, 0 end


if not state.owner then return {}, 0 end
local me = tostring(state.owner):lower()
local who = CONFIG.turtles.avoidWho or "strangers"
local list = {}
for _, e in ipairs(state.players or {}) do
local friend = e.isOwner or tostring(e.name):lower() == me or (who ~= "everyone" and state.access and state.access.allowed
and state.access.allowed[tostring(e.name):lower()])


local here = e.p and e.p.x and not e.dimOther and e.dim == (DRONE_DIM or "minecraft:overworld")
if not friend and here then list[#list + 1] = { name = e.name, x = e.p.x, z = e.p.z } end
end
return list, range
end

function TT.nearThreat(x, z, list, range)
local best, bd
for _, p in ipairs(list) do
local d = math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2)
if d <= range and (not bd or d < bd) then best, bd = p.name, d end
end
return best, bd
end

function TT.avoidTick()
local list, range = TT.threats()
if #list == 0 then

for _, t in pairs(state.turtles) do t.avoidHome = nil end
return
end
local now = os.clock()
for id, t in pairs(state.turtles) do
if TT.online(t) and t.pos and t.pos.x and not t.anchor and not t.held then



local away = list
if t.home and t.home.x then
away = {}
for _, p in ipairs(list) do
if math.sqrt((p.x - t.home.x) ^ 2 + (p.z - t.home.z) ^ 2) > range then away[#away + 1] = p end
end
end
local name, d = TT.nearThreat(t.pos.x, t.pos.z, away, range)

local task = tostring(t.task or "")
local work = task:find("^survey") or task:find("^scanning")
local recently = t.avoidAt and now - t.avoidAt < 60
if name and work and not recently then
t.avoidAt, t.avoidHome = now, true
TT.send(id, "stop", {}, true, true)
TT.log(t, "Player " .. name .. " " .. math.floor(d) .. " blocks away - stopping, going home")
if not t.avoidSaid or now - t.avoidSaid > 600 then
t.avoidSaid = now
setPopup("PLAYER NEAR A TURTLE", (t.label or ("Turtle " .. id)) .. ": " .. name .. " is " .. math.floor(d) ..
" blocks away (" .. math.floor(t.pos.x) .. " " .. math.floor(t.pos.z) .. ") - it went home", C.warn)
end
end
end

if t.avoidHome and TT.online(t) and (t.task == nil or t.task == "idle") then
t.avoidHome = nil
if t.home then TT.send(id, "home", {}, true) end
end
end
end





function TT.homeSpot(t)
local taken, homes = {}, {}
for _, o in pairs(state.turtles) do
if o.home and o.home.x then
taken[o.home.x .. "," .. o.home.y .. "," .. o.home.z] = true
if o.id ~= t.id then homes[#homes + 1] = o end
end
if o.homeOffer and o.id ~= t.id then taken[o.homeOffer] = true end
end
table.sort(homes, function(a, b) return a.id < b.id end)



if FACTORY and FACTORY.chest then
for _, f in ipairs({ FACTORY.builderTurtle and FACTORY.builderTurtle(), FACTORY.crafterTurtle and FACTORY.crafterTurtle() }) do
if f and f.home and f.home.x then
for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 0, -1, 0 } }) do
taken[(f.home.x + d[1]) .. "," .. (f.home.y + d[2]) .. "," .. (f.home.z + d[3])] = true
end
end
end
end
local bad = t.homeBad or {}


for _, step in ipairs({ 1, 2 }) do
for _, o in ipairs(homes) do
local h = o.home
for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
local x, y, z = h.x + d[1] * step, h.y, h.z + d[2] * step
local k = x .. "," .. y .. "," .. z
if not taken[k] and not bad[k] then return x, y, z end
end
end
end
end


function TT.homeTick()
local now = os.clock()
local idleHome = tonumber(CONFIG.turtles.idleHome or 120) or 0
local queueIds
for id, t in pairs(state.turtles) do
local on = TT.online(t)

if on and not t.home then
if not t.homeOfferAt or now - t.homeOfferAt > 60 then
t.homeOfferAt = now
local x, y, z = TT.homeSpot(t)
if x then
t.homeOffer = x .. "," .. y .. "," .. z
TT.send(id, "homeoffer", { x, y, z }, true)
TT.log(t, "No home yet - offered " .. x .. " " .. y .. " " .. z .. " (next to another turtle's home)")
elseif not t.homeNoSpotSaid then
t.homeNoSpotSaid = true
TT.log(t, "No home yet, and no other turtle has one to sit next to - press SET HOME on one turtle")
end
end
elseif t.home then
t.homeOffer = nil
end



local idle = on and (t.task == nil or t.task == "idle")
if idle then t.idleSince = t.idleSince or now else t.idleSince = nil end

local fuel = tonumber(t.fuel)

local low = fuel and fuel < (tonumber(CONFIG.turtles.lowFuel) or 2000) * ((AWAY and AWAY.on) and 3 or 1)


local fc = CONFIG.turtles.fuelChest
if TT.fuelTrip and (not state.turtles[TT.fuelTrip.id] or now - TT.fuelTrip.t0 > 600) then TT.fuelTrip = nil end
if low and fc and fc.x and idle and on and t.pos and t.pos.x and not t.held and not t.anchor and not t.stuck
and not t.rescuer and not TT.fuelTrip and now - t.idleSince > 10
and (not t.fuelTripAt or now - t.fuelTripAt > 600) then
t.fuelTripAt = now
TT.fuelTrip = { id = id, t0 = now }
TT.send(id, "fuelup", { fc.x, fc.y, fc.z }, true)
TT.log(t, "Low on fuel (" .. fuel .. ") - going to the fuel chest at " .. fc.x .. " " .. fc.y .. " " .. fc.z)
low = false
t.idleHomeAt = now
elseif low and fc and fc.x and (not t.fuelTripAt or now - t.fuelTripAt > 600) then
low = "wait"
end
local wait = low and 10 or idleHome
if low ~= "wait" and idleHome > 0 and idle and t.home and t.pos and t.pos.x and not t.held and not t.anchor and not t.party
and not t.stuck and not t.rescuer and now - t.idleSince > wait
and (not t.idleHomeAt or now - t.idleHomeAt > 600) then
local away = math.abs(t.pos.x - t.home.x) + math.abs(t.pos.y - t.home.y) + math.abs(t.pos.z - t.home.z)
local needed = false
if MAP.queue and not t.rescuerRole and not low and not TT.factoryRole(t) then
queueIds = queueIds or MAP.queue.ids or TT.available()
for _, qid in ipairs(queueIds) do
if qid == id and not (MAP.queue.excluded and MAP.queue.excluded[id]) then needed = true end
end
end
if away > 2 and not needed then
t.idleHomeAt = now
TT.send(id, "home", {}, true)
TT.log(t, low and ("Low on fuel (" .. fuel .. ") - going home to the fuel chest")
or ("Idle for " .. math.floor(now - t.idleSince) .. " s away from home - going home"))
end
end



if not t.stuck then t.digOutTries = nil end
if on and idle and t.stuck and t.home and not t.held and not t.anchor and not t.missing
and tostring(t.gear or ""):find("pick", 1, true)
and now - (t.idleSince or now) > 30 and (t.digOutTries or 0) < 3
and (not t.digOutAt or now - t.digOutAt > 600) then
t.digOutAt, t.digOutTries = now, (t.digOutTries or 0) + 1
TT.send(id, "home", { "dig" }, true)
TT.log(t, "Stuck (" .. tostring(t.stuck) .. ") - digging its way home through natural blocks (try " ..
t.digOutTries .. "/3)")
end
end
end



function TT.drive(id, act, force)
local t = state.turtles[id]
if not t then return end
t.held = nil
t.driveLast, t.driveSent, t.driveMsg = act, os.clock(), nil
if not force then t.driveAnyway = nil end
TT.send(id, "drive", { act, force and "force" or nil }, true)
TT.listDirty = true
end
local LOOKDIR = { north = { 0, -1 }, east = { 1, 0 }, south = { 0, 1 }, west = { -1, 0 } }


function TT.lookIn(t, m)
local p = m.pos or t.pos
local v = t.view or {}
if type(v.cells) ~= "table" then v.cells = {} end
if p and p.x and type(m.scan) == "string" then
v.scanAt = os.clock()


local f = math.floor
local sr = math.max(1, math.min(8, math.floor(tonumber(m.scanR) or 3)))
for ax = -sr, sr do for ay = -sr, sr do for az = -sr, sr do
v.cells[f(p.x + ax) .. "," .. f(p.y + ay) .. "," .. f(p.z + az)] = false
end end end
for dx, dy, dz, name in m.scan:gmatch("(-?%d+),(-?%d+),(-?%d+),([^;]+)") do
local f = math.floor
v.cells[f(p.x + tonumber(dx)) .. "," .. f(p.y + tonumber(dy)) .. "," .. f(p.z + tonumber(dz))] = name
end
end
local function set(x, y, z, name)
local k = math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
if not name or name == "air" or name:find(":air$") then v.cells[k] = false
else v.cells[k] = tostring(name):gsub("^minecraft:", "") end
end
if p and p.x then
set(p.x, p.y, p.z, nil)
set(p.x, p.y + 1, p.z, m.up)
set(p.x, p.y - 1, p.z, m.down)
local d = LOOKDIR[tostring(p.f)]
if d then set(p.x + d[1], p.y, p.z + d[2], m.front) end
end
v.front, v.up, v.down, v.at, v.scanErr = m.front, m.up, m.down, os.clock(), m.scanErr
t.view = v
end


function TT.anchorInfo()
for _, t in pairs(state.turtles) do
if t.anchor then
local inChunk
local b = state.basePos
if b and t.pos and t.pos.x then
inChunk = math.floor(t.pos.x / 16) == math.floor(b.x / 16)
and math.floor(t.pos.z / 16) == math.floor(b.z / 16)
end
return t, inChunk
end
end
end



function TT.available()
local list = {}
for id, t in pairs(state.turtles) do
if TT.online(t) and t.pos and t.pos.x and (t.task == nil or t.task == "idle") and not t.anchor
and not t.rescuerRole and not t.party and not TT.factoryRole(t) then
list[#list + 1] = id
end
end
table.sort(list)
return list
end



function TT.splitSurvey(spots, ids)
local out = {}

local known = {}
for _, id in ipairs(ids) do
local t = state.turtles[id]
if t and t.pos and t.pos.x then known[#known + 1] = id end
end
ids = known
if #ids == 0 or #spots == 0 then return out end
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, p in ipairs(spots) do
minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
end


local alongX = (maxX - minX) >= (maxZ - minZ)
if #ids >= 2 then
local tminX, tmaxX, tminZ, tmaxZ = math.huge, -math.huge, math.huge, -math.huge
for _, id in ipairs(ids) do
local p = state.turtles[id].pos
tminX, tmaxX = math.min(tminX, p.x), math.max(tmaxX, p.x)
tminZ, tmaxZ = math.min(tminZ, p.z), math.max(tmaxZ, p.z)
end
local sx, sz = tmaxX - tminX, tmaxZ - tminZ
if math.max(sx, sz) >= 17 then alongX = sx >= sz end
end
local sorted = {}
for i, p in ipairs(spots) do sorted[i] = p end
table.sort(sorted, function(a, b)
if alongX then return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end
return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1])
end)
local n = math.min(#ids, #sorted)
local groups = {}
for i = 1, n do groups[i] = {} end
for i, p in ipairs(sorted) do
local gi = math.floor((i - 1) * n / #sorted) + 1
groups[gi][#groups[gi] + 1] = p
end

local pairsList = {}
for _, id in ipairs(ids) do
local t = state.turtles[id]
for gi, g in ipairs(groups) do
local sx, sz = 0, 0
for _, p in ipairs(g) do sx, sz = sx + p[1], sz + p[2] end
sx, sz = sx / #g, sz / #g
pairsList[#pairsList + 1] = { id = id, gi = gi, d = math.abs(t.pos.x - sx) + math.abs(t.pos.z - sz) }
end
end
table.sort(pairsList, function(a, b) return a.d < b.d end)
local usedT, usedG = {}, {}
for _, pr in ipairs(pairsList) do
if not usedT[pr.id] and not usedG[pr.gi] then
usedT[pr.id], usedG[pr.gi] = true, true
out[pr.id] = groups[pr.gi]
end
end
return out
end


function TT.sendSpots(id, spots, r)
local args = { r }
for _, p in ipairs(spots) do
args[#args + 1] = p[1]
args[#args + 1] = p[2]
end
TT.send(id, "surveypts", args)
end






function TT.stopTick()
for _, t in pairs(state.turtles) do
local s = t.stopAsk
if s and os.clock() - s.last >= 3 then
if s.tries >= 20 then
t.stopAsk = nil
TT.log(t, "STOP: no answer for a minute - sent again when it is back")
setToast(t.label .. " does not answer STOP - it gets STOP again as soon as it is back", C.warn)
else
s.tries, s.last = s.tries + 1, os.clock()
TT.send(t.id, "stop", {}, true, true)
end
end
end
end



function TT.send(id, cmd, args, quiet, again, ses)
local n = os.epoch("utc")
if n <= state.tLastN then n = state.tLastN + 1 end
state.tLastN = n
local a = {}
for i, v in ipairs(args or {}) do a[i] = v end
local t = state.turtles[id]
if not ses and t and t.dups and #t.dups > 0 then ses = t.mainSes end
state.tOut[#state.tOut + 1] = { id = id, msg = { t = "cmd", n = n, cmd = cmd, args = a, ses = ses,
sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) } }

if t and t.held and cmd ~= "stop" and not quiet then t.held = nil TT.listDirty = true end
if cmd == "stop" and t and not again then
t.stopAsk = { tries = 1, last = os.clock() }
t.held = true
TT.listDirty = true
if MAP.queue then
MAP.queue.excluded = MAP.queue.excluded or {}
MAP.queue.excluded[id] = true
end
end
if t and not quiet then
local shown = {}
for i, v in ipairs(a) do shown[i] = tostring(v) end
if cmd == "surveypts" then
TT.log(t, "> survey: " .. math.floor((#a - 1) / 2) .. " spots")
else
TT.log(t, "> " .. cmd .. (#shown > 0 and (" " .. table.concat(shown, " ")) or ""))
end
end
os.queueEvent("turtle_send")
end


KNOW.load()












TT.party = nil
local PARTY_GAP, PARTY_HOP = 24, 128

local function flat(a, b) return math.abs(a.x - b.x) + math.abs(a.z - b.z) end


function TT.lostList()
local out = {}
for _, t in pairs(state.turtles) do
if not TT.online(t) and not t.missing and t.pos and t.pos.x then out[#out + 1] = t end
end
return out
end

function TT.partyStart()
if TT.party then return false, "a search party is already out (type  search stop  to call it back)" end
local lost = TT.lostList()
if #lost == 0 then return false, "no lost turtle (offline, last spot known) to look for" end
local meet = CONFIG.drone and CONFIG.drone.home or state.basePos
if not (meet and meet.x) then return false, "base position unknown (CONFIG.drone.home)" end
local members = {}
for id, t in pairs(state.turtles) do
local fuel = tonumber(t.fuel) or 0
if TT.online(t) and t.pos and t.pos.x and not t.anchor and not t.rescuerRole and not t.held and fuel > 2000
and not TT.factoryRole(t) then
members[#members + 1] = id
end
end
if #members == 0 then return false, "no free turtle (online, fuel > 2000, not the anchor / rescuer / factory turtles)" end
table.sort(members)

local order, from = {}, { x = meet.x, z = meet.z }
while #lost > 0 do
local bi, bd
for i, t in ipairs(lost) do
local d = flat(t.pos, from)
if not bd or d < bd then bi, bd = i, d end
end
local t = table.remove(lost, bi)
order[#order + 1] = t.id
from = t.pos
end
TT.party = { members = members, targets = order, ti = 1, found = {}, missing = {}, located = {},
seenAt = {}, locatedSet = {}, foundSet = {}, phase = "move", stage = "meet", goals = {}, t0 = os.clock(), started = os.clock() }
for k, id in ipairs(members) do
local t = state.turtles[id]
t.party = true
if t.task and t.task ~= "idle" then TT.send(id, "stop", {}, true, true) end
TT.party.goals[id] = { x = meet.x + (k - 1) * 2 - #members, y = meet.y, z = meet.z + 3 }
end
TT.partySendGoals()
if sysLog then sysLog("Search party: " .. #members .. " turtle(s) look for " .. #order .. " lost one(s)", "INFO") end
return true, #members .. " turtle(s) meet at the base, then look for " .. #order .. " lost turtle(s)"
end


function TT.partySendGoals()
local P = TT.party
P.sentAt, P.done = os.clock(), {}
for id, g in pairs(P.goals) do
TT.send(id, "goto", { math.floor(g.x), math.floor(g.y), math.floor(g.z) }, true)
end
end

function TT.partyStop(why)
local P = TT.party
if not P then return false end
for _, id in ipairs(P.members) do
local t = state.turtles[id]
if t then
t.party = nil
TT.send(id, "stop", {}, true, true)
TT.send(id, "home", {}, true)
end
end
TT.party = nil
local msg = "Search party " .. (why or "called back") .. ": found " .. #P.found .. ", sent the rescuer to " ..
#P.located .. ", MISSING (deleted) " .. #P.missing
pushNote("DONE", msg, C.good)
if sysLog then sysLog(msg, "INFO") end
return true, msg
end


local function partyTarget(P)
while P.targets[P.ti] do
local t = state.turtles[P.targets[P.ti]]
if t and not t.missing and not TT.online(t) and not P.locatedSet[t.id] then return t end
P.ti, P.stage = P.ti + 1, "travel"
end
end


function TT.partySeen(id, seen)
local P = TT.party
if not (P and type(seen) == "table") then return end
P.scanned = P.scanned or {}
P.scanned[id] = true
P.locatedSet = P.locatedSet or {}
for _, b in ipairs(seen) do
local x, y, z = tonumber(b.x), tonumber(b.y), tonumber(b.z)
local busy = false
for _, o in pairs(state.turtles) do
if TT.online(o) and o.pos and o.pos.x and math.abs(o.pos.x - x) + math.abs(o.pos.y - y) + math.abs(o.pos.z - z) <= 1 then busy = true end
end
local k = x and (x .. "," .. y .. "," .. z)
if x and not busy and not P.seenAt[k] then
P.seenAt[k] = true

local best, bd
for _, tid in ipairs(P.targets) do
local t = state.turtles[tid]
if t and not TT.online(t) and not t.missing and not P.locatedSet[tid] and t.pos and t.pos.x then
local d = math.abs(t.pos.x - x) + math.abs(t.pos.z - z)
if d <= 96 and (not bd or d < bd) then best, bd = t, d end
end
end
if best then
P.locatedSet[best.id] = true
P.located[#P.located + 1] = best.id
local rescuer
for _, o in pairs(state.turtles) do if o.rescuerRole and TT.online(o) then rescuer = o end end
local ok, msg = TT.rescue(best.id, x, y, z, 6, rescuer)
local text = "Search party: " .. (best.label or ("#" .. best.id)) .. " found at " .. x .. " " .. y .. " " .. z ..
(ok and (" - " .. msg) or (" - no rescuer could go (" .. tostring(msg) .. ") - get it yourself"))
TT.log(best, text)
pushNote(ok and "DONE" or "WARNING", text, ok and C.good or C.warn)
if sysLog then sysLog(text, ok and "DONE" or "WARNING") end
end
end
end
end


function TT.partyTick()
local P = TT.party
if not P then return end
local now = os.clock()
P.locatedSet = P.locatedSet or {}

local live = {}
for _, id in ipairs(P.members) do
local t = state.turtles[id]
if t and TT.online(t) then live[#live + 1] = id else if t then t.party = nil end P.goals[id] = nil end
end
P.members = live
if #live == 0 then return TT.partyStop("ended - no turtle left in it") end

for _, tid in ipairs(P.targets) do
local t = state.turtles[tid]
if t and TT.online(t) and not P.foundSet[tid] then
P.foundSet[tid] = true
P.found[#P.found + 1] = tid
local text = "Search party: " .. (t.label or ("#" .. tid)) .. " is back (the party loaded its area)"
TT.log(t, text)
pushNote("DONE", text, C.good)
end
end
if P.phase == "move" then

local all = true
for id, g in pairs(P.goals) do
local t = state.turtles[id]
if not P.done[id] then
local near = t.pos and t.pos.x and flat(t.pos, g) <= 6
local idle = (t.task == nil or t.task == "idle") and now - P.sentAt > 20
if near or idle then P.done[id] = true else all = false end
end
end
if not all and now - P.sentAt < 300 then return end
if P.stage == "meet" then P.stage = "travel" end
if P.scanNext then
P.scanNext, P.scanned, P.phase, P.scanT = false, {}, "scan", now
for _, id in ipairs(P.members) do TT.send(id, "findturtles", {}, true) end
return
end
P.phase = "next"
end
if P.phase == "scan" then
local all = true
for _, id in ipairs(P.members) do if not (P.scanned or {})[id] then all = false end end
if not all and now - P.scanT < 45 then return end
P.phase = "next"
end

local T = partyTarget(P)
if not T then return TT.partyStop("finished") end
local n = #P.members
local cx, cy, cz = 0, 0, 0
for _, id in ipairs(P.members) do
local p = state.turtles[id].pos
cx, cy, cz = cx + p.x, cy + p.y, cz + p.z
end
cx, cy, cz = cx / n, cy / n, cz / n
P.goals = {}
if P.stage == "travel" and math.abs(T.pos.x - cx) + math.abs(T.pos.z - cz) > 30 then

local dx, dz = T.pos.x - cx, T.pos.z - cz
local len = math.sqrt(dx * dx + dz * dz)
local step = math.min(PARTY_HOP, len)
local wx, wz = cx + dx / len * step, cz + dz / len * step
local px, pz = -dz / len, dx / len
for k, id in ipairs(P.members) do
local off = (k - (n + 1) / 2) * PARTY_GAP
P.goals[id] = { x = wx + px * off, y = math.max(cy, T.pos.y), z = wz + pz * off }
end
else

P.stage = (P.stage == "ring1") and "ring2" or ((P.stage == "ring2") and "done" or "ring1")
if P.stage == "done" then

TT.markMissing(T, "the search party")
P.missing[#P.missing + 1] = T.id
P.ti, P.stage = P.ti + 1, "travel"
P.phase = "next"
return
end
local r = (P.stage == "ring1") and 24 or 56
local ring = { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r }, { r, -r }, { -r, r } }
for k, id in ipairs(P.members) do
local o = ring[(k - 1) % #ring + 1]
P.goals[id] = { x = T.pos.x + o[1], y = T.pos.y, z = T.pos.z + o[2] }
end
end
P.phase, P.scanNext = "move", true
TT.partySendGoals()
end


function TT.partyLine()
local P = TT.party
if not P then return nil end
local T = P.targets[P.ti] and state.turtles[P.targets[P.ti]]
local what = (P.stage == "meet") and "meeting at the base"
or (P.stage == "travel") and ("on the way to " .. (T and T.label or "?"))
or ("searching around " .. (T and T.label or "?"))
return "SEARCH PARTY (" .. #P.members .. "): " .. what .. " - " .. (P.ti - 1) .. "/" .. #P.targets ..
" done, found " .. #P.found + #P.located .. ", missing " .. #P.missing
end
