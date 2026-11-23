








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






function TT.isCopy(t)
if not (t and t.id) then return false end
local _, n = TT.realId(t.id)
return n > 0
end
function TT.copyStays(t)
if not t then return false end
if t.chunkyLent then return true end
return TT.isCopy(t) and not t.ownChunky
end

function TT.stayTwin(t)
if t.chunkyLent then return t.chunkyLent end
return (TT.realId(t.id))
end














TT.PROVE_S, TT.PROVE_N = 180, 3
function TT.notAloneWhy(t)
local p = t.pos
if not (p and tonumber(p.x) and tonumber(p.z)) then return "its position is not known" end
local sim = ((simChunks and simChunks() or 10) + 2) * 16
local on = state.online
for _, e in ipairs(state.players or {}) do
local online = (not on) or on[tostring(e.name):lower()]
if online then
local dimOk = not e.dim or not DRONE_DIM or e.dim == DRONE_DIM
if dimOk then
if not (e.p and tonumber(e.p.x) and tonumber(e.p.z)) then
if e.dim then return "player " .. tostring(e.name) .. "'s position is not known" end
else
local d = math.max(math.abs(e.p.x - p.x), math.abs(e.p.z - p.z))
if d <= sim then return "player " .. tostring(e.name) .. " is " .. math.floor(d) .. " blocks away" end
end
end
end
end
local h = CONFIG.drone and CONFIG.drone.home
local br = tonumber(CONFIG.turtles.baseLoadR) or 128
if h and tonumber(h.x) and math.max(math.abs(h.x - p.x), math.abs(h.z - p.z)) <= br then
return "it is " .. math.floor(math.max(math.abs(h.x - p.x), math.abs(h.z - p.z))) .. " blocks from the base"
end
for _, a in ipairs(type(CONFIG.turtles.loadedAreas) == "table" and CONFIG.turtles.loadedAreas or {}) do
local ax, az = tonumber(a.x or a[1]), tonumber(a.z or a[2])
local ar = tonumber(a.r or a[3]) or 32
if ax and az and math.max(math.abs(ax - p.x), math.abs(az - p.z)) <= ar then return "it is in a force-loaded area" end
end
for oid, o in pairs(state.turtles) do
if oid ~= t.id and TT.online(o) and o.pos and tonumber(o.pos.x) and tonumber(o.pos.z) then
local d = math.max(math.abs(o.pos.x - p.x), math.abs(o.pos.z - p.z))
if d <= 64 then return (o.label or ("turtle " .. oid)) .. " is " .. math.floor(d) .. " blocks away" end
end
end
return nil
end

function TT.chunkCheck(t)
local why = TT.notAloneWhy(t)
t.chunkWhy = why
if why then t.alone = nil return end
local now = os.clock()
if not t.alone or now - (t.alone.last or now) > (CONFIG.turtles.offlineAfter or 60) then t.alone = { from = now, n = 0 } end
t.alone.n, t.alone.last = t.alone.n + 1, now
if now - t.alone.from >= TT.PROVE_S and t.alone.n >= TT.PROVE_N then
t.loadsSelf = now
pcall(TT.chunkProve, t)
end
end
local function provenNow(t) return t and t.loadsSelf and os.clock() - t.loadsSelf < 600 and TT.online(t) end
function TT.chunkProve(t)
local real = TT.realId(t.id)
local function tell(msg)
TT.log(t, msg)
if sysLog then sysLog(t.label .. ": " .. msg) end
if pushNote then pcall(pushNote, "INFO", t.label .. ": " .. msg, C and C.info) end
TT.listDirty = true
end
if TT.isCopy(t) and not t.ownChunky then
local twin = state.turtles[real]
if provenNow(twin) then
t.ownChunky, t.chunkyProof = true, "its own Chunky: it answered alone while turtle " .. real .. " did too"
tell("CHUNK TEST: loads its own chunk while turtle " .. real .. " does too - two Chunkies, it may move again")
elseif not (twin and TT.online(twin)) then
t.ownChunky, t.chunkyProof = true, "holds the shared Chunky: it answered alone while turtle " .. real .. " was offline"
if twin then twin.chunkyLent = t.id end
tell("CHUNK TEST: loads its own chunk while turtle " .. real .. " is OFFLINE - it holds the Chunky: it moves, " ..
"turtle " .. real .. " stays put from now on")
end
end


local other = t.chunkyLent and t
if not other then
local tw = state.turtles[real]
if tw and tw.chunkyLent == t.id and provenNow(tw) then other = tw end
end
if other then
local holder = state.turtles[other.chunkyLent]
if other ~= t or provenNow(holder) or not holder then
t = other
TT.log(t, "CHUNK TEST: loads its own chunk while " .. (holder and holder.label or ("turtle " .. t.chunkyLent)) ..
" does too - two Chunkies, it may move again")
if sysLog then sysLog(t.label .. ": CHUNK TEST - two Chunkies, it may move again") end
TT.listDirty = true
t.chunkyLent = nil
end
end
end

function TT.chunkTick()
local now = os.clock()
for id, t in pairs(state.turtles) do
local want = TT.copyStays(t) or (t.chunkTestUntil and now < t.chunkTestUntil)
if want and TT.online(t) and not t.chunkWhy and now - (t.chunkPingAt or -999) >= 20 then
t.chunkPingAt = now
TT.send(id, "ping", {}, true)
end
end
end

function TT.chunkText(t)
if t.chunkyProof then return "proven: " .. t.chunkyProof end
if not TT.online(t) then return "offline - cannot be tested now" end
if t.chunkWhy then return "cannot tell here: " .. t.chunkWhy end
if t.alone then
return "alone - answered " .. t.alone.n .. " times in " .. math.floor(os.clock() - t.alone.from) .. " s (needs " ..
TT.PROVE_N .. " in " .. TT.PROVE_S .. " s)"
end
return "waiting for its next answer"
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




function TT.homeCost(t, raw)
if not (t and t.pos and t.pos.x and t.home and t.home.x) then return 0 end
local flat = math.abs(t.pos.x - t.home.x) + math.abs(t.pos.z - t.home.z)
if flat <= 48 then return flat + math.abs((t.pos.y or 0) - (t.home.y or 0)) end
local full = tonumber(t.homeFuel) or
(math.floor((flat + math.max(0, 150 - (t.pos.y or 0)) + math.max(0, 150 - (t.home.y or 0))) * 1.15) + 300)
if raw then return math.floor((full - 300) / 1.15) end
return full
end


function TT.surveyFuelNeed(t)
local minFuel = tonumber(CONFIG.map.surveyMinFuel) or 500
if t and t.endless then return minFuel end
return math.max(minFuel, TT.homeCost(t) + (tonumber(CONFIG.map.batchFuel) or 800))
end


local QUIET_TASK = { "waiting", "refuel", "gps", "install", "building", "starting the new turtle", "crafting", "scanning",
"looking around", "checking the end automata", "driven by hand", "restarted", "duplicate" }




TT.MOVE_FAIL = { "blocked", "could not reach", "no progress", "going in circles", "out of fuel", "gave up after", "no way" }
function TT.isStuck(t)
if not (t and t.stuck) then return false end
local s = tostring(t.stuck):lower()
local mv = false
for _, w in ipairs(TT.MOVE_FAIL) do if s:find(w, 1, true) then mv = true break end end
if not mv then return false end

local sp, p = t.stuckPos, t.pos
if sp and sp.x and p and p.x and math.abs(p.x - sp.x) + math.abs((p.y or 0) - (sp.y or 0)) + math.abs(p.z - sp.z) > 3 then
return false
end
return true
end
local TROUBLE_TASK = { "backing up", "retracing", "planning a route", "following a planned route" }
function TT.stillFor(t)
return os.clock() - math.max(t.movedAt or os.clock(), t.taskAt or 0)
end
function TT.idleWhy(t)
local fuel = tonumber(t.fuel)
local minFuel = TT.surveyFuelNeed(t)
local q = MAP and MAP.queue
if not (t.pos and t.pos.x) then return "position unknown - press GPS LOCATE", C.warn end
if t.anchor then return "anchor - keeps the base loaded", C.purple end
if TT.copyStays(t) then
if t.chunkyLent then
return "stays put - turtle " .. t.chunkyLent .. " (its copy) holds the shared Chunky (CHUNK TEST)", C.purple
end
return "a COPY - its Chunky shares turtle " .. TT.realId(t.id) .. "'s chunk loading: it stays put " ..
"(chunk test: " .. TT.chunkText(t) .. "; new Chunky on it, then: turtle " .. t.id .. " newchunky)", C.purple
end
if t.rescuerRole then return "rescuer - waits for a turtle in trouble", C.warn end
if t.party then return "in the SEARCH PARTY - waits for the others", C.label end
if t.dwAnchor then return "keeps a drone build site loaded (schem status)", C.purple end
local fr = TT.factoryRole(t)
if fr then return "factory " .. fr .. " - stays at the factory (no surveys)", C.label end
if t.surveyFail and os.clock() - t.surveyFail.at < 120 then
return "REFUSED its survey spots: " .. tostring(t.surveyFail.msg) .. " (tried again in " ..
math.ceil(120 - (os.clock() - t.surveyFail.at)) .. " s)", C.bad
end
if t.dwWant then
return "fuel " .. tostring(fuel) .. " - a DRONE brings fuel out here (no trip home)", C.warn
end
if t.fuelShort then
return "fuel " .. tostring(fuel) .. " is not enough to get home (" .. TT.homeCost(t, true) .. ") - waits there for a " ..
"drone / the rescuer to bring fuel", C.bad
end
if fuel and fuel < minFuel then
return "fuel " .. fuel .. " is below " .. minFuel .. " (the way home + a batch) - " ..
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
(t.rescuer and " - rescue on its way" or "") ..
(TT.atBase(t) and " - at the base: picked up?" or ""))
end
local task = tostring(t.task or "idle")
local busy = task ~= "idle"
local low = task:lower()
local fuel = tonumber(t.fuel)
if fuel and fuel < 20 then return "nofuel", "NO FUEL", C.bad, "fuel " .. fuel .. " - it cannot move" end

if not busy and TT.isStuck(t) then return "stuck", "STUCK", C.bad, tostring(t.stuck) end
if t.held then return "held", "STOPPED", C.warn, "stopped by you - any button (e.g. PING) releases it" end
if busy then
for _, w in ipairs(TROUBLE_TASK) do
if low:find(w, 1, true) then return "trouble", "FINDING A WAY", C.warn, "going round something in its way - " .. task end
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






local CLEAN = {
str = { "label", "task", "gear", "ver", "msg", "cmd", "want", "mode", "name", "scan", "route", "walls", "dead", "clears",
"dim", "role", "phase", "code", "err", "ses", "scanErr", "updReady", "refused" },
strOrFalse = { "front", "up", "down" },
num = { "fuel", "fuelMax", "items", "freeSlots", "homeFuel", "free", "ci", "li", "nl", "idx", "transit", "rowLength", "nextDump",
"lastCmd", "scanR", "tx", "tz", "fx", "fz", "py", "x", "y", "z", "trail", "copy", "leader", "partner" },
pos = { "pos", "home", "at", "station" },
tbl = { "seen", "recipe", "missing", "notes", "team", "stats", "carry", "got" },
}
local function cleanPos(p)
if type(p) ~= "table" then return nil end
local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
if not (x and z) or x ~= x or z ~= z or math.abs(x) > 3e7 or math.abs(z) > 3e7 then return nil end
local out = {}
for k, v in pairs(p) do out[k] = v end
out.x, out.y, out.z = x, (y and y == y and math.abs(y) < 1e5) and y or nil, z
return out
end
function TT.clean(m)
for _, k in ipairs(CLEAN.str) do
local v = m[k]
if type(v) == "number" then m[k] = tostring(v) elseif v ~= nil and type(v) ~= "string" then m[k] = nil end
end
for _, k in ipairs(CLEAN.strOrFalse) do
local v = m[k]
if v ~= nil and v ~= false and type(v) ~= "string" then m[k] = nil end
end
for _, k in ipairs(CLEAN.num) do
local v = m[k]
if v ~= nil then
v = tonumber(v)
if v and (v ~= v or v == math.huge or v == -math.huge) then v = nil end
m[k] = v
end
end
for _, k in ipairs(CLEAN.pos) do if m[k] ~= nil then m[k] = cleanPos(m[k]) end end
for _, k in ipairs(CLEAN.tbl) do if m[k] ~= nil and type(m[k]) ~= "table" then m[k] = nil end end

for _, k in ipairs({ "carry", "got" }) do
if m[k] then
local o = {}
for name, n in pairs(m[k]) do
n = tonumber(n)
if type(name) == "string" and n and n == n and n ~= math.huge then o[name] = n end
end
m[k] = o
end
end
for _, k in ipairs({ "team", "missing" }) do
if m[k] then
local o = {}
for _, v in ipairs(m[k]) do v = tonumber(v) if v then o[#o + 1] = v end end
m[k] = o
end
end
if m.seen then
local o = {}
for _, p in ipairs(m.seen) do p = cleanPos(p) if p then o[#o + 1] = p end end
m.seen = o
end
if m.notes then
local o = {}
for _, v in ipairs(m.notes) do if type(v) == "string" or type(v) == "number" then o[#o + 1] = tostring(v) end end
m.notes = o
end
return m
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
TT.clean(m)

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
t.endless = m.endless and true or nil

local op, np = t.pos, m.pos

if not t.movedAt or not prevSeen or os.clock() - prevSeen > CONFIG.turtles.offlineAfter then
t.movedAt = os.clock()
end
if type(np) == "table" and np.x and (not (op and op.x) or math.abs(np.x - op.x) + math.abs((np.y or 0) - (op.y or 0))
+ math.abs(np.z - op.z) >= 1) then
t.movedAt = os.clock()
end
if m.task ~= t.task then t.taskAt = os.clock() end
pcall(TT.statAdd, t, prevSeen)
t.pos, t.task, t.home = m.pos, m.task, m.home
pcall(TT.chunkCheck, t)

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
if m.task and m.task ~= "idle" and not tostring(m.task):find("^waiting") then t.prevTask = m.task end
t.freeSlots = tonumber(m.freeSlots)
t.homeFuel = tonumber(m.homeFuel)


if m.refused and m.refused ~= (t.refused and t.refused.raw) then
local c, k = tostring(m.refused):match("^([^:]*):(.*)$")
local why = (k == "ses" and "it was for another session (a copy of this id)") or (k == "dup" and "it is a stopped duplicate")
or (k and k:sub(1, 1) == "n" and ("an old message number (it last took " .. k:sub(2) .. ")")) or tostring(m.refused)
t.refused = { raw = m.refused, why = tostring(c or "?") .. " - " .. why, at = os.clock() }
end
if m.gear then

local function has(g, w) for part in tostring(g or ""):gmatch("[^,]+") do if part == w then return true end end end
if t.gear then
for _, w in ipairs({ "scanner", "pick" }) do
if has(t.gear, w) and not has(m.gear, w) then
local what = (w == "scanner") and "Geo Scanner" or "pickaxe"
local where = (type(m.pos) == "table" and m.pos.x) and (m.pos.x .. " " .. m.pos.y .. " " .. m.pos.z) or "?"
local line = (t.label or ("Turtle " .. id)) .. " LOST its " .. what .. " (last job: " .. tostring(t.prevTask or "?") ..
", now at " .. where .. ", " .. tostring(m.freeSlots or "?") .. " free slots)"
TT.log(t, line)
if sysLog then sysLog(line, "WARNING") end
pushNote("WARNING", line, C.warn)
end
end
end
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


TT.send(id, "setting", { "dig", tostring(CONFIG.turtles.dig == true) }, true)
t.zoneSent = nil
elseif m.t == "scan" then
local ok = pcall(MAP.addScan, m)
if ok then
TT.statNew(t)
t.stat.scans = t.stat.scans + 1
TT.statScans = (TT.statScans or 0) + 1
end
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
if m.cmd == "ping" and t.pingAsk then
local p = t.pingAsk
t.pingAsk = nil
local msg = t.label .. " answered PING after " .. math.floor(os.clock() - p.at + 0.5) .. " s" ..
(p.tries > 1 and (" (try " .. p.tries .. " - it did not hear the first one)") or "")
TT.log(t, msg)
setToast(msg, C.good, 6)
end
if m.cmd == "drive" then
t.driveMsg = { ok = m.ok, msg = tostring(m.msg), at = os.clock() }

t.driveAnyway = (not m.ok and tostring(m.msg):find("DIG ANYWAY", 1, true)) and t.driveLast or nil
end
if m.cmd == "fuelup" and TT.fuelTrip and TT.fuelTrip.id == id then TT.fuelTrip = nil end
if m.cmd == "surveypts" and MAP.batchResult then pcall(MAP.batchResult, id, m.ok, m.msg) end
if m.cmd == "build" and FACTORY then pcall(FACTORY.result, id, m.ok, m.msg) end

if FACTORY and FACTORY.leaving and FACTORY.leaving.id == id and not m.ok
and (m.cmd == "home" or m.cmd == "goto") then FACTORY.leaving.why = tostring(m.msg) end
if m.cmd == "craft" and FACTORY then pcall(FACTORY.craftResult, id, m.ok, m.msg) end
if m.cmd == "restart" and not m.ok and sysLog then sysLog(t.label .. ": " .. tostring(m.msg), "ERROR") end
TT.log(t, (m.ok and "Done: " or "Failed: ") .. tostring(m.msg))
if not m.ok then setToast(t.label .. ": " .. tostring(m.msg), C.warn, 6) end
end
pcall(TT.sendZone, t)
if not state.tSel then state.tSel = id end
os.queueEvent("inv_update")
end



function TT.sendZone(t)
if not (t and t.id and TT.online(t)) then return end
local b = CONFIG.drone and CONFIG.drone.home or state.basePos
if not (b and b.x) then return end
local at = math.floor(b.x) .. "," .. math.floor(b.y or 64) .. "," .. math.floor(b.z)
local r = math.floor(tonumber(CONFIG.turtles.noDigBase) or 96)
local key = at .. "|" .. r .. "|" .. tostring(CONFIG.turtles.dig == true)
if t.zoneSent == key then return end
t.zoneSent = key
TT.send(t.id, "setting", { "baseAt", at }, true)
TT.send(t.id, "setting", { "noDigBase", tostring(r) }, true)
TT.send(t.id, "setting", { "dig", tostring(CONFIG.turtles.dig == true) }, true)
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
local t = readSafe(VER_FILE)
if type(t) == "table" and type(t.byHash) == "table" then
local by, top = {}, 0
for h, n in pairs(t.byHash) do
if type(h) == "string" and tonumber(n) then by[h] = tonumber(n) top = math.max(top, tonumber(n)) end
end
TT.versions = { next = math.max(tonumber(t.next) or 1, top + 1), byHash = by }
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


val = tostring(val):gsub('[\\"]', "\\%0"):gsub("%%", "%%%%")
return (code:gsub('(\n%s*' .. name .. '%s*=%s*)"[^"\n]*"', '%1"' .. val .. '"', 1))
end



local function modTime(p)
local ok, a = pcall(function() return fs.attributes and fs.attributes(p) end)
return (ok and type(a) == "table" and tonumber(a.modified)) or 0
end



function TT.localCode()
local name = CONFIG.turtles.codeFile or "node.lua"
local here = fs.combine(BASE_DIR or "", name)
local top = name
if top ~= here and fs.exists(top) and (not fs.exists(here) or modTime(top) > modTime(here)) then return top end
if fs.exists(here) then return here end
end




TT.WHERE_FILE = "node_where.dat"
function TT.codeWhere()
local w = readSafe(TT.WHERE_FILE)
return type(w) == "table" and type(w.path) == "string" and w or nil
end
function TT.codePath()
local l = TT.localCode()
if l then return l end
local w = TT.codeWhere()
if w then return w.path end
local name = CONFIG.turtles.codeFile or "node.lua"
for _, d in ipairs(mountedDisks()) do
local p = fs.combine(d.mount, name)
if fs.exists(p) then return p end
end
return fs.combine(BASE_DIR or "", name)
end


function TT.codeStore(text, from)
local okS, small = pcall(TT.shrinkCode, text)
if okS and type(small) == "string" and load(small, "node", "t", {}) then text = small end
if not load(text, "node", "t", {}) then return false, "it does not compile" end
local name = CONFIG.turtles.codeFile or "node.lua"
local hash = codeHash(text)
local old = TT.codeWhere()
local where

if STORE then
local ids = {}
for id, h in pairs(STORE.helpers) do
if STORE.usable(h) and (h.free or 0) >= #text + 32 * 1024 then ids[#ids + 1] = id end
end
local oldId = old and STORE.parse(old.path)
table.sort(ids, function(a, b)
if (a == oldId) ~= (b == oldId) then return a == oldId end
return (STORE.helpers[a].free or 0) > (STORE.helpers[b].free or 0)
end)
for _, id in ipairs(ids) do
local p = "store:" .. id .. "/" .. name
local okW = STORE.write(p, text)
if okW and STORE.read(p) == text then where = p break end
end
end

if not where then
for _, d in ipairs(mountedDisks()) do
if d.data and not d.installer then
local p = fs.combine(d.mount, name)
local room = (d.free or 0) + (fs.exists(p) and fs.getSize(p) or 0)


if room >= #text + 2048 and writeSafe(p, text) then where = p break end
end
end
end
if not where then return false, "no storage helper / data floppy with " .. math.ceil(#text / 1024) .. " KB free" end
writeSafe(TT.WHERE_FILE, serialSmall({ path = where, hash = hash, size = #text, from = from }))

if old and old.path ~= where then
if STORE and STORE.isRemote(old.path) then pcall(STORE.delete, old.path)
elseif fs.exists(old.path) then pcall(fs.delete, old.path) end
end
return true, where
end

function TT.codeRead(w)
w = w or TT.codeWhere()
if not w then return nil end
local text
if STORE and STORE.isRemote(w.path) then
local ok, t = pcall(STORE.read, w.path)
text = ok and t or nil
elseif fs.exists(w.path) then
local h = fs.open(w.path, "r")
text = h and h.readAll()
if h then h.close() end
end
if text and w.hash and codeHash(text) ~= w.hash then return nil end
return text
end

function TT.codeOffload()
local l = TT.localCode()
if not l then return false end
local h = fs.open(l, "r")
local text = h and h.readAll()
if h then h.close() end
if not text or not load(text, "node", "t", {}) then return false end

local from = TT.codeWhere() and "dropped" or "old"
local ok, where = TT.codeStore(text, from)
if not ok then return false, where end
local name = CONFIG.turtles.codeFile or "node.lua"
for _, p in ipairs({ fs.combine(BASE_DIR or "", name), name }) do
if fs.exists(p) then pcall(fs.delete, p) end
end
if sysLog then sysLog("node.lua moved off this computer (" .. math.ceil(#text / 1024) .. " KB) - kept on " .. where, "INFO") end
return true, where
end

function TT.fetchCode(log)
log = log or function() end
if not http then return false, "no internet (http is off)" end
local up = fs.combine(BASE_DIR or "", "upgrade.lua")
local fn = fs.exists(up) and loadfile(up, "t", _ENV)
if not fn then return false, "upgrade.lua is missing next to inventory.lua" end
local okR, done, body, v = pcall(fn, { fetch = CONFIG.turtles.codeFile or "node.lua", group = "node", dir = BASE_DIR or "", log = log })
if not (okR and done and type(body) == "string") then return false, "the download did not work" end
local w = TT.codeWhere()
local okS, small = pcall(TT.shrinkCode, body)
local cmp = (okS and type(small) == "string" and load(small, "node", "t", {})) and small or body
if w and w.hash == codeHash(cmp) then
if w.from ~= "github" then w.from = "github" writeSafe(TT.WHERE_FILE, serialSmall(w)) end
return true, "turtle program up to date (" .. tostring(v) .. ")"
end
local ok, where = TT.codeStore(body, "github")
if not ok then return false, where end
pcall(TT.codeLoad, true, true)
return true, "turtle program " .. tostring(v) .. " stored on " .. where
end








local function shrinkScan(s)
local res, i, n = {}, 1, #s
while i <= n do
local c = s:sub(i, i)
if c == '"' or c == "'" then
local j = i + 1
while j <= n and s:sub(j, j) ~= c do
j = j + ((s:sub(j, j) == "\\") and 2 or 1)
end
res[#res + 1] = s:sub(i, j)
i = j + 1
elseif c == "[" and s:find("^%[=*%[", i) then
local eq = s:match("^%[(=*)%[", i)
local closer = "]" .. eq .. "]"
local e = s:find(closer, i + #eq + 2, true)
if not e then res[#res + 1] = s:sub(i) return table.concat(res), "str", closer end
res[#res + 1] = s:sub(i, e + #closer - 1)
i = e + #closer
elseif c == "-" and s:sub(i + 1, i + 1) == "-" then
local eq = s:match("^%[(=*)%[", i + 2)
if not eq then return table.concat(res) end
local closer = "]" .. eq .. "]"
local e = s:find(closer, i + 2 + #eq + 2, true)
if not e then return table.concat(res), "com", closer end
res[#res + 1] = " "
i = e + #closer
else
local j = s:find("[\"'%[%-]", i + 1) or (n + 1)
res[#res + 1] = s:sub(i, j - 1)
i = j
end
end
return table.concat(res)
end



function TT.shrinkCode(text)
local out, mode, closer = {}, nil, nil
for line in (text .. "\n"):gmatch("(.-)\n") do
local t
if mode == "str" then
local e = line:find(closer, 1, true)
if not e then t = line
else
local head, rest = line:sub(1, e + #closer - 1), line:sub(e + #closer)
local body
body, mode, closer = shrinkScan(rest)
t = (head .. body):gsub("%s+$", "")
end
elseif mode == "com" then
local e = line:find(closer, 1, true)
if not e then t = ""
else
local body
body, mode, closer = shrinkScan((line:sub(e + #closer):gsub("^%s+", "")))
t = body:gsub("%s+$", "")
end
else
local body
body, mode, closer = shrinkScan((line:gsub("^%s+", "")))
t = (mode == "str") and body or body:gsub("%s+$", "")
end
out[#out + 1] = t
if #out % 300 == 0 then TT.workYield() end
end
if out[#out] == "" then out[#out] = nil end
return table.concat(out, "\n") .. "\n"
end




function TT.codeLoad(force, canWait)
local path, mod, text
local l = TT.localCode()
if l then
path = l

mod = path .. ":" .. modTime(path) .. ":" .. fs.getSize(path)
if CODE and CODE.mod == mod and not force then return end
local h = fs.open(path, "r")
if not h then return end
text = h.readAll() or ""
h.close()
else
local w = TT.codeWhere()
if w then
path, mod = w.path, w.path .. "#" .. tostring(w.hash)
if CODE and CODE.mod == mod and not force then return end
if STORE and STORE.isRemote(w.path) and not canWait then return end
text = TT.codeRead(w)
if not text then return end
else
path = TT.codePath()
if not fs.exists(path) then CODE = nil return end
mod = path .. ":" .. modTime(path) .. ":" .. fs.getSize(path)
if CODE and CODE.mod == mod and not force then return end
local h = fs.open(path, "r")
if not h then return end
text = h.readAll() or ""
h.close()
end
end
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


local only
if FACTORY and FACTORY.leaving and FACTORY.leaving.id then only = FACTORY.leaving.id end
if not forced and CONFIG.turtles.updateWhenAway ~= false and AWAY and not AWAY.on
and AWAY.ownerOnline() == true and os.clock() - TT.codeSeenAt < 7200 then
TT.updWaiting = true
if not only then return end
else
only = nil
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


local sharing = {}
for id in pairs(TT.sending) do sharing[(TT.realId(id))] = true end
for _, t in ipairs(TT.list()) do
if busy >= 3 then break end
if TT.online(t) and TT.outdated(t) and t.updReady ~= CODE.ver and not TT.sending[t.id]
and not sharing[(TT.realId(t.id))]
and (not t.updRetry or now > t.updRetry) and (not only or t.id == only) then
sharing[(TT.realId(t.id))] = true
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



TT.statSince = TT.statSince or os.clock()
TT.STAT_KINDS = { "survey", "sky", "way", "home", "fuel", "idle", "other", "offline" }
TT.STAT_NAME = { survey = "surveying", sky = "long trips (sky highway)", way = "finding a way (stuck)",
home = "going home", fuel = "fuel", idle = "idle / waiting", other = "other jobs", offline = "offline" }
function TT.statKind(task)
task = tostring(task or "idle")
if task == "idle" or task:find("^waiting") then return "idle" end
if task:find("^survey") then return "survey" end
if task:find("sky highway", 1, true) or task:find("climbing", 1, true) then return "sky" end
for _, w in ipairs({ "backing up", "retracing", "planning a route", "following a planned route",
"scanning the surroundings", "going back" }) do
if task:find(w, 1, true) then return "way" end
end
if task:find("home", 1, true) then return "home" end
if task:find("fuel", 1, true) then return "fuel" end
return "other"
end
function TT.statNew(t)
if not t.stat then
t.stat = { scans = 0 }
for _, k in ipairs(TT.STAT_KINDS) do t.stat[k] = 0 end
end
end
function TT.statAdd(t, prevSeen)
TT.statNew(t)
local now = os.clock()
if t.statAt and prevSeen then
local dt = now - t.statAt
if dt > 0 then
local k = (now - prevSeen > CONFIG.turtles.offlineAfter) and "offline" or TT.statKind(t.task)
t.stat[k] = t.stat[k] + dt
end
end
t.statAt = now
end

function TT.statLines(n)
local out, all, tot = {}, { scans = 0 }, 0
for _, k in ipairs(TT.STAT_KINDS) do all[k] = 0 end
local rows = {}
for _, t in pairs(state.turtles) do
if t.stat then
local sum = 0
for _, k in ipairs(TT.STAT_KINDS) do all[k] = all[k] + t.stat[k] sum = sum + t.stat[k] end
all.scans = all.scans + t.stat.scans
tot = tot + sum
rows[#rows + 1] = { t = t, sum = sum }
end
end
local hours = (os.clock() - TT.statSince) / 3600
out[#out + 1] = string.format("Since the base started (%.1f h of game clock): %d scans = %.0f an hour (~%.0f chunks an hour)",
hours, all.scans, all.scans / math.max(0.01, hours), all.scans * 1.13 / math.max(0.01, hours))
if tot > 0 then
local parts = {}
for _, k in ipairs(TT.STAT_KINDS) do
if all[k] > 0 then parts[#parts + 1] = TT.STAT_NAME[k] .. " " .. math.floor(all[k] * 100 / tot + 0.5) .. "%" end
end
out[#out + 1] = "The fleet's time: " .. table.concat(parts, ", ")
end
table.sort(rows, function(a, b) return a.t.stat.scans > b.t.stat.scans end)
for i, r in ipairs(rows) do
if i > (n or 12) then out[#out + 1] = "  ... and " .. (#rows - i + 1) .. " more" break end
local s, best, bk = r.t.stat, 0, "idle"
for _, k in ipairs(TT.STAT_KINDS) do if s[k] > best then best, bk = s[k], k end end
out[#out + 1] = string.format("  %s: %d scans (%.0f/h), mostly %s (%d%%)", r.t.label, s.scans,
s.scans / math.max(0.01, r.sum / 3600), TT.STAT_NAME[bk],
r.sum > 0 and math.floor(best * 100 / r.sum + 0.5) or 0)
end
return out
end


function TT.lostLines()
local out, rows = {}, {}
local base = CONFIG.drone and CONFIG.drone.home
local count = { copy = 0, missing = 0, atBase = 0, short = 0, other = 0 }
for _, t in pairs(state.turtles) do
if not TT.online(t) then rows[#rows + 1] = t end
end
table.sort(rows, function(a, b) return (a.seenEpoch or 0) > (b.seenEpoch or 0) end)
for _, t in ipairs(rows) do
local fuel = tonumber(t.fuel)
local why
if TT.isCopy(t) then why = "COPY (shares turtle " .. TT.realId(t.id) .. "'s Chunky)" count.copy = count.copy + 1
elseif t.missing then why = "MISSING (looked for, not found)" count.missing = count.missing + 1
elseif TT.atBase(t) then why = "at the base" count.atBase = count.atBase + 1
elseif fuel and t.home and fuel < TT.homeCost(t, true) then
why = "fuel " .. fuel .. " < way home " .. TT.homeCost(t, true)
count.short = count.short + 1
else why = "?" count.other = count.other + 1 end
local where = "position unknown"
if t.pos and t.pos.x then
where = t.pos.x .. " " .. tostring(t.pos.y) .. " " .. t.pos.z
if base and base.x then
where = where .. " (" .. (math.abs(t.pos.x - base.x) + math.abs(t.pos.z - base.z)) .. " from the base)"
end
end
local last = t.log and t.log[1] and (t.log[1].t .. " " .. t.log[1].msg) or "-"
out[#out + 1] = string.format("%s #%d: silent %s | %s | task: %s | fuel %s | %s | last: %s", t.label, t.id,
TT.ago(t.seenEpoch), why, tostring(t.task or (t.prevTask and ("was " .. t.prevTask)) or "none"),
t.fuel and tostring(t.fuel) or "?", where, last)
end
table.insert(out, 1, #rows .. " offline: " .. count.copy .. " copies, " .. count.short .. " without fuel for the way home, " ..
count.missing .. " missing, " .. count.atBase .. " at the base, " .. count.other .. " not known why (newest first)")
return out
end


function TT.saveList()
local out = {}
for id, t in pairs(state.turtles) do
out[#out + 1] = { id = id, label = t.label, pos = t.pos, home = t.home, seen = t.seenEpoch,
task = t.task, ver = t.ver, gear = t.gear, anchor = t.anchor, rescuerRole = t.rescuerRole,
held = t.held, recall = t.recall, missing = t.missing, ownChunky = t.ownChunky,
fuel = tonumber(t.fuel), chunkyLent = t.chunkyLent, chunkyProof = t.chunkyProof }
end
saveFileSafe(dataPath(CONFIG.turtles.listFile), serialSmall(out))
TT.listDirty = false
end

function TT.loadList()
local lp = dataPath(CONFIG.turtles.listFile)
local list = readSafe(lp)
if type(list) ~= "table" then return end
for _, e in ipairs(list) do
if type(e) == "table" and tonumber(e.id) then
local t = TT.get(tonumber(e.id))

local seen = tonumber(e.seen)
local c = { label = e.label, pos = e.pos, home = e.home, task = e.task, ver = e.ver, gear = e.gear }
if TT.clean then TT.clean(c) end
if c.label then t.label = c.label end
t.pos, t.home, t.seenEpoch, t.task = c.pos, c.home, seen, c.task
t.ver, t.gear, t.anchor = c.ver, c.gear, e.anchor
t.rescuerRole = e.rescuerRole
t.held = e.held
t.recall = e.recall
t.missing = e.missing
t.ownChunky = e.ownChunky == true or nil
t.chunkyLent = tonumber(e.chunkyLent)
t.chunkyProof = type(e.chunkyProof) == "string" and e.chunkyProof or nil
t.fuel = t.fuel or tonumber(e.fuel)
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





function TT.atBase(t)
local b = CONFIG.drone and CONFIG.drone.home or state.basePos
local r = tonumber(CONFIG.turtles.atBaseRange) or 1024
if not (b and b.x and t and t.pos and t.pos.x) or r <= 0 then return false end
return math.abs(t.pos.x - b.x) <= r and math.abs(t.pos.z - b.z) <= r
end
function TT.lostAtBase()
local out = {}
for _, t in pairs(state.turtles) do
if not TT.online(t) and not t.missing and TT.atBase(t) then out[#out + 1] = t end
end
table.sort(out, function(a, b) return a.id < b.id end)
return out
end

function TT.forgetAtBase()
local n = 0
for _, t in ipairs(TT.lostAtBase()) do TT.forget(t.id) n = n + 1 end
return n
end

local function problemOf(t)
local now = os.clock()
if t.missing and not TT.online(t) then return nil end
if TT.copyStays(t) then return nil end
if TT.online(t) then
t.offlineNoted = nil
local idle = (t.task == nil or t.task == "idle")
local fuel = tonumber(t.fuel)
if fuel and fuel < 20 then t.lowFuelSince = t.lowFuelSince or now else t.lowFuelSince = nil end
if idle and TT.isStuck(t) then t.stuckSince = t.stuckSince or now else t.stuckSince = nil end

if t.lowFuelSince and now - t.lowFuelSince > 60 and not (DW and DW.fuelBusy and DW.fuelBusy(t)) then return "fuel" end

if t.fuelShort and idle then t.shortSince = t.shortSince or now else t.shortSince = nil end
if t.shortSince and now - t.shortSince > 120 and not (DW and DW.fuelBusy and DW.fuelBusy(t)) then return "fuel" end
if t.stuckSince and now - t.stuckSince > 60 then return "stuck" end
return nil
end

if not (t.pos and t.pos.x and t.seenEpoch) then return nil end
if TT.atBase(t) then return nil end
local after = tonumber(CONFIG.turtles.rescueAfter) or 180
if (os.epoch("utc") - t.seenEpoch) / 1000 < after then return nil end
return "lost"
end
TT.problemOf = problemOf


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



TT.COPY_MOVES = { "survey", "scanning", "sky highway", "climbing", "going home", "going to", "fuel", "party",
"finding", "backing up", "retracing", "planning a route", "following a planned route" }
function TT.copyMoveTask(task)
task = tostring(task or "")
for _, w in ipairs(TT.COPY_MOVES) do if task:find(w, 1, true) then return true end end
return false
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



if fuel and not low and not t.endless and fuel < TT.surveyFuelNeed(t) then low = true end
if low and t.endless and fuel >= 20 then low = false end


local cost = TT.homeCost(t, true)
if low and on and idle and fuel and not t.endless and not TT.copyStays(t) and fuel < cost and cost > 300 then
low = false
if not t.fuelShort then
t.fuelShort = true
TT.log(t, "Fuel " .. fuel .. " is not enough for the way home (" .. cost .. ") - waits for fuel to be brought")
end
elseif not (fuel and fuel < cost) or TT.copyStays(t) then
t.fuelShort = nil
end



if t.dwWant and not (low and on and idle) then t.dwWant = nil end
if low and low ~= "wait" and on and idle and not t.endless and not t.fuelShort and not TT.copyStays(t)
and cost >= (tonumber(CONFIG.turtles.droneFuelFrom) or 600)
and DW and DW.canFuel and DW.canFuel() and not (t.dwEdgeFail and now - t.dwEdgeFail < 1800) then
if not t.dwWant then
t.dwWant = true
TT.log(t, "Low on fuel " .. "(" .. tostring(fuel) .. ") " .. cost .. " blocks out - a drone brings fuel (no trip home)")
end
low = false
end


local fc = CONFIG.turtles.fuelChest
if TT.fuelTrip and (not state.turtles[TT.fuelTrip.id] or now - TT.fuelTrip.t0 > 600) then TT.fuelTrip = nil end
if TT.copyStays(t) then
low = false
if on and not idle and t.task and TT.copyMoveTask(t.task) and (not t.copyStopAt or now - t.copyStopAt > 600) then
t.copyStopAt = now
TT.send(id, "stop", {}, true, true)
TT.log(t, "A COPY on a trip ('" .. tostring(t.task) .. "') - stopped: moving it unloads turtle " ..
TT.stayTwin(t) .. "'s chunk")
end
end
if low and fc and fc.x and idle and on and t.pos and t.pos.x and not t.held and not t.anchor and not TT.isStuck(t)
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
if low ~= "wait" and idleHome > 0 and idle and t.home and t.pos and t.pos.x and not t.held and not t.anchor and not t.party and not t.dwAnchor
and not TT.copyStays(t)
and not TT.isStuck(t) and not t.rescuer and now - t.idleSince > wait
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



local stuckNow = TT.isStuck(t)
if not stuckNow then t.digOutTries = nil end
if on and idle and stuckNow and t.home and not t.held and not t.anchor and not t.missing
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
and not t.rescuerRole and not t.party and not t.dwAnchor and not TT.factoryRole(t) and not TT.copyStays(t) then
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





function TT.pingWhy(t)
local why = {}
local ago = t.lastSeen and math.floor(os.clock() - t.lastSeen) or nil
if not ago then why[#why + 1] = "it never reported"
elseif ago > 60 then why[#why + 1] = "its last report was " .. ago .. " s ago (offline?)"
else why[#why + 1] = "it still reports (" .. ago .. " s ago) but did not hear me" end
if t.refused and os.clock() - t.refused.at < 600 then
why[#why + 1] = "it REFUSED a command lately: " .. t.refused.why
elseif ago and ago <= 60 then
why[#why + 1] = "the modem may be off (scanning / digging: " .. tostring(t.task) .. ") or the base is out of its radio range"
end
return table.concat(why, "; ")
end
function TT.pingTick()
for _, t in pairs(state.turtles) do
local p = t.pingAsk
if p and os.clock() - p.last >= 3 then
if p.tries >= 10 then
t.pingAsk = nil
local msg = t.label .. ": no answer to PING after " .. math.floor(os.clock() - p.at) .. " s - " .. TT.pingWhy(t)
TT.log(t, msg)
setToast(msg, C.warn, 10)
else
p.tries, p.last = p.tries + 1, os.clock()
TT.send(t.id, "ping", {}, true, true)
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


local hand = (USER_ACTION or HAND_CMD or cmd == "drive") and cmd ~= "stop" or nil
state.tOut[#state.tOut + 1] = { id = id, msg = { t = "cmd", n = n, cmd = cmd, args = a, ses = ses, hand = hand,
sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) } }

if t and t.held and cmd ~= "stop" and not quiet then t.held = nil TT.listDirty = true end
if cmd == "ping" and t and not again and not quiet then t.pingAsk = { tries = 1, last = os.clock(), at = os.clock() } end
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






function TT.partyY(x, z, fallback)
local top, rough
if MAP and MAP.get then
for _, d in ipairs({ { 0, 0 }, { 4, 0 }, { -4, 0 }, { 0, 4 }, { 0, -4 } }) do
local h = MAP.get(math.floor(x + d[1]), math.floor(z + d[2]))
if h then top = math.max(top or h, h)
elseif MAP.getOverview then
local o = MAP.getOverview(math.floor(x + d[1]), math.floor(z + d[2]))
if o then rough = math.max(rough or o, o) end
end
end
end
if top or rough then return math.max((top or -64) + 3, (rough or -64) + 10) end
return math.max(tonumber(CONFIG.turtles.partySkyY) or 150, 64)
end

local function flat(a, b) return math.abs(a.x - b.x) + math.abs(a.z - b.z) end


function TT.lostList()
local out = {}
for _, t in pairs(state.turtles) do
if not TT.online(t) and not t.missing and t.pos and t.pos.x and not TT.atBase(t) and not TT.copyStays(t) then
out[#out + 1] = t
end
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
and not TT.factoryRole(t) and not TT.copyStays(t) then
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
local gx, gz = meet.x + (k - 1) * 2 - #members, meet.z + 3
TT.party.goals[id] = { x = gx, y = TT.partyY(gx, gz, math.max(meet.y or 64, t.pos.y)), z = gz }
end
TT.partySendGoals()
if sysLog then sysLog("Search party: " .. #members .. " turtle(s) look for " .. #order .. " lost one(s)", "INFO") end
return true, #members .. " turtle(s) meet at the base, then look for " .. #order .. " lost turtle(s)"
end


function TT.partySendGoals()
local P = TT.party
P.sentAt, P.done = os.clock(), {}




local far = 0
for id, g in pairs(P.goals) do
local t = state.turtles[id]
if t and t.pos and t.pos.x then far = math.max(far, math.abs(t.pos.x - g.x) + math.abs(t.pos.z - g.z)) end
TT.send(id, "goto", { math.floor(g.x), math.floor(g.y), math.floor(g.z) }, true)
end
P.limit = math.max(300, far / 1.5 + 240)
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
local msg = "Search party " .. (why or "called back") .. ": " .. #P.found .. " woke up, " ..
#P.located .. " found for the rescuer" .. (#TT.rescueQ > 0 and (" (" .. #TT.rescueQ .. " still to fetch)") or "") ..
", MISSING (deleted / broken) " .. #P.missing ..
((P.unreached and #P.unreached > 0) and (", could not get to " .. #P.unreached) or "")
pushNote("DONE", msg, C.good)
if sysLog then sysLog(msg, "INFO") end
return true, msg
end


local function partyTarget(P)
while P.targets[P.ti] do
local t = state.turtles[P.targets[P.ti]]
if t and not t.missing and not TT.online(t) and not P.locatedSet[t.id] then return t end
P.ti, P.stage, P.nearTarget, P.stuckRounds = P.ti + 1, "travel", nil, 0
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


TT.rescueQ[#TT.rescueQ + 1] = { id = best.id, x = x, y = y, z = z, at = os.clock() }
local text = "Search party: " .. (best.label or ("#" .. best.id)) .. " found at " .. x .. " " .. y .. " " .. z ..
" - the rescuer goes there " .. (#TT.rescueQ > 1 and ("after " .. (#TT.rescueQ - 1) .. " other(s)") or "now")
TT.log(best, text)
pushNote("DONE", text, C.good)
if sysLog then sysLog(text, "DONE") end
TT.rescueQueueTick()
end
end
end
end




TT.rescueQ = {}
function TT.rescueQueueTick()
local q = TT.rescueQ
if #q == 0 then return end

local keep = {}
for _, e in ipairs(q) do
local t = state.turtles[e.id]
if t and not TT.online(t) and not t.missing then keep[#keep + 1] = e end
end
TT.rescueQ = keep
q = keep
if #q == 0 then return end
local r
for _, o in pairs(state.turtles) do if o.rescuerRole and TT.online(o) then r = o end end
local busyR = false
if r then
busyR = not (r.task == nil or r.task == "idle") or r.held
for _, o in pairs(state.turtles) do
if o.rescuer == r.id and not TT.online(o) and not o.missing and o.id ~= q[1].id then busyR = true end
end
end
if busyR then return end
local e = q[1]
local ok, msg = TT.rescue(e.id, e.x, e.y, e.z, 6, r)
local t = state.turtles[e.id]
if ok then
table.remove(q, 1)
TT.log(t, "Search party find: " .. msg)
elseif not e.told then
e.told = true
local text = "Found " .. (t.label or ("#" .. e.id)) .. " at " .. e.x .. " " .. e.y .. " " .. e.z ..
" but no rescuer can go yet (" .. tostring(msg) .. ") - it waits; or get it yourself"
pushNote("WARNING", text, C.warn)
if sysLog then sysLog(text, "WARNING") end
end
end


function TT.partyTick()
pcall(TT.rescueQueueTick)
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
local idleNow = (t.task == nil or t.task == "idle")
local idle = idleNow and now - P.sentAt > 20



if (near and idleNow and now - P.sentAt > 8) or idle then
P.done[id] = true
if near then P.reachedN = (P.reachedN or 0) + 1 end
else
all = false
end
end
end
if not all and now - P.sentAt < (P.limit or 300) then return end

local T0 = P.targets[P.ti] and state.turtles[P.targets[P.ti]]
if T0 and T0.pos and T0.pos.x then
for _, mid in ipairs(P.members) do
local m = state.turtles[mid]
if m and m.pos and m.pos.x and flat(m.pos, T0.pos) <= 64 then P.nearTarget = true end
end
end

if (P.reachedN or 0) == 0 and P.stage ~= "meet" then P.stuckRounds = (P.stuckRounds or 0) + 1
else P.stuckRounds = 0 end
P.reachedN = 0
if P.stage == "meet" then P.stage = "travel" end
if (P.stuckRounds or 0) >= 3 and T0 then

P.unreached = P.unreached or {}
P.unreached[#P.unreached + 1] = T0.id
local text = "Search party: could not get to " .. (T0.label or ("#" .. T0.id)) .. " (no way through) - " ..
"not marked missing; going on to the next one"
TT.log(T0, text)
pushNote("WARNING", text, C.warn)
P.ti, P.stage, P.stuckRounds, P.nearTarget, P.phase = P.ti + 1, "travel", 0, nil, "next"
P.scanNext = false
end
if P.scanNext then
P.scanNext, P.scanned, P.phase, P.scanT = false, {}, "scan", now
local Tn = P.targets[P.ti] and state.turtles[P.targets[P.ti]]

local floor = (Tn and Tn.pos and Tn.pos.y) and (math.floor(Tn.pos.y) + 2) or nil
for _, id in ipairs(P.members) do
TT.send(id, "findturtles", { (P.stage ~= "meet" and floor) or nil }, true)
end
return
end
P.phase = "next"
end
if P.phase == "scan" then




local all = true
for _, id in ipairs(P.members) do
local t = state.turtles[id]
local idle = t and (t.task == nil or t.task == "idle")
if not (idle and now - P.scanT > 15) then all = false end
end
if not all and now - P.scanT < 240 then return end
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




do

P.stage = (P.stage == "ring1") and "ring2" or ((P.stage == "ring2") and "done" or "ring1")
if P.stage == "done" then
if P.nearTarget then

TT.markMissing(T, "the search party")
P.missing[#P.missing + 1] = T.id
else

P.unreached = P.unreached or {}
P.unreached[#P.unreached + 1] = T.id
TT.log(T, "Search party: could not get close to its last spot - not marked missing")
end
P.nearTarget = nil
P.ti, P.stage = P.ti + 1, "travel"
P.phase = "next"
return
end
local r = (P.stage == "ring1") and 24 or 56
local ring = { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r }, { r, -r }, { -r, r } }
for k, id in ipairs(P.members) do
local o = ring[(k - 1) % #ring + 1]
local gx, gz = T.pos.x + o[1], T.pos.z + o[2]
P.goals[id] = { x = gx, y = TT.partyY(gx, gz, math.max(cy, T.pos.y)), z = gz }
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
