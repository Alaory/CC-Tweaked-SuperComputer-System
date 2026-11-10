









MINE = { units = {}, dirty = false, saved = 0 }
local FILE = "mining.dat"


function MINE.cfg(k, default)
local m = CONFIG.mining
local v
if type(m) == "table" then v = m[k] end
if v == nil then return default end
return v
end

function MINE.cfgArgs()
local function list(v)
if type(v) ~= "table" then return "" end
local out = {}
for _, s in ipairs(v) do out[#out + 1] = tostring(s) end
return table.concat(out, ",")
end
return { "dumpEvery=" .. tostring(MINE.cfg("dumpEvery", 600)),
"rowLength=" .. tostring(MINE.cfg("rowLength", 16)),
"noMine=" .. tostring(MINE.cfg("noMine", 64)),
"want=" .. list(MINE.cfg("want", {})),
"keep=" .. list(MINE.cfg("keep", {})),
"extraOres=" .. list(MINE.cfg("ores", {})),
"skipOres=" .. list(MINE.cfg("skipOres", {})),
"fuelItems=" .. list(MINE.cfg("fuelItems", { "*mining_dim_core*" })) }
end

function MINE.load()
local path = dataPath and dataPath(FILE) or FILE
if not fs.exists(path) then return end
local h = fs.open(path, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if type(t) == "table" then
for id, u in pairs(t) do
u.id, u.log, u.queue = tonumber(id) or u.id, u.log or {}, {}
MINE.units[u.id] = u
end
end
end
function MINE.save()
local out = {}
for id, u in pairs(MINE.units) do
out[id] = { id = u.id, label = u.label, role = u.role, dim = u.dim, got = u.got, stats = u.stats,
seenEpoch = u.seenEpoch, pos = u.pos, log = u.log }
end
saveFileSafe(dataPath and dataPath(FILE) or FILE, serialSmall(out))
MINE.dirty, MINE.saved = false, os.clock()
end
MINE.load()

function MINE.log(u, msg)
local okD, t = pcall(os.date, "%H:%M")
table.insert(u.log, 1, { t = okD and t or "", e = os.epoch("utc"), msg = msg })
while #u.log > 30 do table.remove(u.log) end
end


function MINE.online(u)
local limit = (u.role == "miner") and 150 or 60
return u.lastSeen ~= nil and os.clock() - u.lastSeen < limit
end


function MINE.cmd(id, cmd, args, quiet)
local u = MINE.units[id]
if not u then return end
local n = os.epoch("utc")
if n <= state.tLastN then n = state.tLastN + 1 end
state.tLastN = n
local a = {}
for i, v in ipairs(args or {}) do a[i] = tostring(v) end

local ses = (u.dups and #u.dups > 0) and u.mainSes or nil
local msg = { t = "cmd", n = n, cmd = cmd, args = a, ses = ses, sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) }
u.queue = u.queue or {}
u.queue[#u.queue + 1] = msg
state.tOut[#state.tOut + 1] = { id = id, msg = msg }
if not quiet then MINE.log(u, "> " .. cmd) end
os.queueEvent("turtle_send")
end


function MINE.receive(id, m)
local u = MINE.units[id]
if not u then
u = { id = id, log = {}, queue = {} }
MINE.units[id] = u
end

if type(m.ses) == "string" and TT.dupSeen and TT.dupSeen(u, id, m, {
where = true,
canUse = function(mm) return mm.role ~= "loader" end,
log = function(text) MINE.log(u, text) end,
stop = function(ses, cmd, args)
cmd, args = cmd or "dupstop", args or {}
local n = os.epoch("utc")
if n <= state.tLastN then n = state.tLastN + 1 end
state.tLastN = n
local a = {}
for i, v in ipairs(args) do a[i] = tostring(v) end
state.tOut[#state.tOut + 1] = { id = id, msg = { t = "cmd", n = n, cmd = cmd, args = a, ses = ses,
sig = TT.sign(CONFIG.turtles.key, "cmd", n, cmd, a) } }
os.queueEvent("turtle_send")
end }) then return end
if m.n <= (u.lastN or 0) then return end
u.lastN = m.n
u.lastSeen, u.seenEpoch = os.clock(), os.epoch("utc")
for _, k in ipairs({ "label", "role", "dim", "task", "fuel", "fuelMax", "free", "pos", "partner", "running", "err",
"ci", "li", "nl", "phase", "station", "carry", "got", "stats", "ver", "rowLength",
"team", "leader", "ready", "idx", "transit" }) do
u[k] = m[k]
end

local ores = type(u.stats) == "table" and tonumber(u.stats.ores) or 0
if u.running then
if not u.runT0 then u.runT0, u.ores0 = os.clock(), ores end
else
u.runT0, u.ores0 = nil, nil
end
u.nextDump = m.nextDump and (os.clock() + m.nextDump) or nil
for _, msg in ipairs(type(m.notes) == "table" and m.notes or {}) do
msg = tostring(msg)
MINE.log(u, msg)
if msg:find("STOPPED", 1, true) or msg:find("Could not", 1, true) or msg:find("failed", 1, true)
or msg:find("STUCK", 1, true) or msg:find("full", 1, true) then
pushNote("WARNING", (u.label or ("#" .. id)) .. ": " .. msg, C.warn)
if sysLog then sysLog("Mining " .. tostring(u.dim) .. ": " .. (u.label or ("#" .. id)) .. " - " .. msg, "WARNING") end
end
end

local keep = {}
for _, q in ipairs(u.queue or {}) do
if q.n > (tonumber(m.lastCmd) or 0) then
keep[#keep + 1] = q
state.tOut[#state.tOut + 1] = { id = id, msg = q }
end
end
u.queue = keep

local cfg = MINE.cfgArgs()
local key = table.concat(cfg, ";")
if u.cfgSent ~= key then
u.cfgSent = key
MINE.cmd(id, "cfg", cfg, true)
end
if #keep > 0 then os.queueEvent("turtle_send") end
MINE.dirty = true
if os.clock() - MINE.saved > 60 then pcall(MINE.save) end
end


function MINE.teams()
local t = {}
for _, u in pairs(MINE.units) do
local d = u.dim or "?"
t[d] = t[d] or { miners = {} }
if u.role == "loader" then
local cur = t[d].loader
if not cur or (u.seenEpoch or 0) > (cur.seenEpoch or 0) then t[d].loader = u end
elseif u.role == "miner" then
t[d].miners[#t[d].miners + 1] = u
end
end
for _, team in pairs(t) do
table.sort(team.miners, function(a, b) return a.id < b.id end)
team.miner = team.miners[1]
end
return t
end

function MINE.totals(team)
local T = { ores = 0, dumps = 0, got = {}, carry = {}, rate = 0, ci = team.loader and team.loader.ci }

local tr = team.loader and tonumber(team.loader.transit)
if T.ci and tr then T.ci, T.moving = math.max(0, T.ci - tr), T.ci < tr end
for _, m in ipairs(team.miners or {}) do
local st = type(m.stats) == "table" and m.stats or {}
T.ores, T.dumps = T.ores + (tonumber(st.ores) or 0), T.dumps + (tonumber(st.dumps) or 0)
for k, v in pairs(m.got or {}) do T.got[k] = (T.got[k] or 0) + v end
for k, v in pairs(m.carry or {}) do T.carry[k] = (T.carry[k] or 0) + v end
if m.runT0 and os.clock() - m.runT0 > 300 then
T.rate = T.rate + ((tonumber(st.ores) or 0) - (m.ores0 or 0)) / ((os.clock() - m.runT0) / 3600)
end
end
return T
end


function MINE.status(u)
if not u then return "MISSING", C.bad, "no turtle yet - run miner.lua on it" end
if not MINE.online(u) then
return "OFFLINE", C.bad, "last seen " .. (u.seenEpoch and TT.ago(u.seenEpoch) or "never")
end
local task = tostring(u.task or "")
local fuel = tonumber(u.fuel)
if fuel and fuel < 100 then
return "NO FUEL", C.bad, "fuel " .. fuel .. " - put coal in it and type  refuel all  on the turtle"
end
if u.role == "loader" and fuel and fuel < 2000 then
return "LOW FUEL", C.warn, "fuel " .. fuel .. " - give it fuel: an endless fuel item (if your pack has one) or coal"
end
if u.role == "loader" then
if task:find("STUCK", 1, true) or task:find("blocked", 1, true) then return "BLOCKED", C.bad, task end
if u.err and not u.running then return "STOPPED", C.bad, tostring(u.err) end
if not u.partner then return "NO MINERS", C.warn, task end
if not u.running then return "PAUSED", C.label, task end
if task:find("crossing", 1, true) then return "MOVING", C.good, task end
return "LOADING", C.good, task
end
if u.err and not u.running then return "STOPPED", C.bad, tostring(u.err) end
if not u.partner then return "NO LOADER", C.warn, task end
if not u.running then return "PAUSED", C.label, task end
if task:find("teleport", 1, true) or task:find("unload", 1, true) or task:find("Import", 1, true) then
return "UNLOADING", C.purple, task
end
if task:find("waiting for the loader", 1, true) or task:find("ready at my lane", 1, true)
or task:find("team mate", 1, true) or task:find("asking the loader", 1, true) then
return "WAITING", C.label, task
end
return "MINING", C.good, task
end



function MINE.drop(id)
local u = MINE.units[id]
if not u then return false, "no mining turtle #" .. tostring(id) end
if u.role ~= "miner" then


MINE.units[id] = nil
pcall(MINE.save)
return true, "loader #" .. id .. " forgotten. Put a new loader (miner.lua, role l) in the same dimension: " ..
"the miners join it after 10 min without their old loader, then press START TEAM"
end
local team = MINE.teams()[u.dim or "?"]
local l = team and team.loader
if not l then return false, "no loader for " .. tostring(u.dim) .. " - nothing to drop it from" end
MINE.cmd(l.id, "drop", { id })
MINE.units[id] = nil
pcall(MINE.save)
return true, "the loader #" .. l.id .. " takes miner #" .. id .. " out of the team (its layer goes to the others)" ..
(MINE.online(l) and "" or " - the loader is offline: it gets this when it reports again")
end
