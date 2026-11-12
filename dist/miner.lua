











































CONFIG = {
protocol   = "basectl",
baseName   = "base",
team       = "basemine",
dumpEvery  = 600,
rowLength  = 16,
noMine     = 64,
noDig      = 24,
minY       = -56,
layerStep  = 17,
scanR      = 8,
checkIn    = 30,
lowFuel    = 2000,
fuelTarget = 20000,
keepCoal   = 64,

fuelItems  = { "*mining_dim_core*" },
wantMax    = 64,
maxMiners  = 5,
joinRange  = 40,


junk = { "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate",
"minecraft:dirt", "minecraft:gravel", "minecraft:sand", "minecraft:red_sand", "minecraft:andesite",
"minecraft:diorite", "minecraft:granite", "minecraft:tuff", "minecraft:calcite",
"minecraft:netherrack", "minecraft:basalt", "minecraft:smooth_basalt", "minecraft:blackstone",
"minecraft:end_stone", "minecraft:dripstone_block", "minecraft:pointed_dripstone",
"minecraft:rooted_dirt", "minecraft:mud", "minecraft:soul_sand", "minecraft:soul_soil",
"minecraft:moss_block", "minecraft:clay", "minecraft:flint" },

want = {},
ores = { "*_ore", "minecraft:ancient_debris" },

protect = { "computercraft:*", "*shulker*", "ae2:*", "*chest*", "*barrel*", "sophisticatedstorage:*",
"*spawner*", "minecraft:bedrock", "*interface*", "*drive*" },
}

STATE_FILE = "miner_state"
MYVER = "m21"
DX = { [0] = 0, 1, 0, -1 }
DZ = { [0] = -1, 0, 1, 0 }
FNAME = { [0] = "north", "east", "south", "west" }
NOTES = {}
S = {}
LEADER_SEEN = os.clock()
task = "starting"
LAST_CHECK = -1000
LAST_STATUS = -1000
ARRIVED = nil
DUMP_NOW = false
STASHING = false
lastN = 0








SESSION = tostring(math.random(100000, 999999)) .. "-" .. tostring(os.epoch("utc") % 100000)
DUP = false



COPY = tonumber((os.getComputerLabel() or ""):match("%[c(%d+)%]%s*$"))
MYTID = (COPY or 0) * 100000 + os.getComputerID()
if COPY then STATE_FILE = STATE_FILE .. "_c" .. COPY end
function now() return math.floor(os.epoch("utc") / 1000) end
function save()
if DUP then return end
local h = fs.open(STATE_FILE .. ".tmp", "w")
if not h then return end
local ok = pcall(function() h.write(textutils.serialize(S)) end)
h.close()
if ok then
if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
fs.move(STATE_FILE .. ".tmp", STATE_FILE)
end
end
function loadState()
if fs.exists(STATE_FILE) then
local h = fs.open(STATE_FILE, "r")
local t = textutils.unserialize(h.readAll() or "")
h.close()
if type(t) == "table" then S = t end
end
S.stats = S.stats or { dug = 0, ores = 0, dumps = 0 }
S.carry = S.carry or {}
S.got = S.got or {}

for k, v in pairs(S.cfg or {}) do CONFIG[k] = v end
end
function note(msg)
print(msg)
NOTES[#NOTES + 1] = msg
while #NOTES > 8 do table.remove(NOTES, 1) end
end









function codeHash(text)
local h = 0
for i = 1, #text, 64 do
local b = { string.byte(text, i, math.min(#text, i + 63)) }
for k = 1, #b do h = (h * 31 + b[k]) % 4294967296 end
end
return string.format("%08x", h)
end
function myProgram()
local p = shell and shell.getRunningProgram and shell.getRunningProgram()
if not p or p == "" or p == "startup.lua" or p == "startup" then p = "miner.lua" end
return p
end

CODEVER = nil
do
local okR = pcall(function()
local h = fs.open(myProgram(), "rb")
if h then
CODEVER = codeHash(h.readAll() or "")
h.close()
end
end)
if not okR then CODEVER = nil end
end
UPD, UPD_READY = nil, nil
function updPiece(a)
local ver, i, n, text = tostring(a[1] or ""), tonumber(a[2]), tonumber(a[3]), a[4]
if not (i and n and type(text) == "string") or ver == "" then return end
if ver == CODEVER or (UPD_READY and UPD_READY.ver == ver) then return end
if not UPD or UPD.ver ~= ver then UPD = { ver = ver, n = n, parts = {}, got = 0 } end
if not UPD.parts[i] then UPD.parts[i], UPD.got = text, UPD.got + 1 end
if UPD.got < UPD.n then return end
local all = table.concat(UPD.parts)
UPD = nil
if codeHash(all) ~= ver then note("Update arrived damaged - the base sends it again") return end
local fn, err = load(all, "=miner.lua", "t", {})
if not fn then note("Update does not compile - not installed: " .. tostring(err)) return end
UPD_READY = { ver = ver, text = all }
note("Update " .. ver .. " ready - installs as soon as the team is paused")
end

function installMinerUpdate()
local u = UPD_READY
if not u then return false end
local prog, tmp = myProgram(), "miner.new"
if fs.exists(tmp) then fs.delete(tmp) end
local h = fs.open(tmp, "wb")
local okW = h and pcall(h.write, u.text)
if h then pcall(h.close) end
if not (okW and fs.exists(tmp) and fs.getSize(tmp) >= #u.text) then
if fs.exists(tmp) then fs.delete(tmp) end
UPD_READY = nil
note("Update NOT installed: the disk is too full - the old program keeps running")
return false
end
if fs.exists(prog .. ".old") then fs.delete(prog .. ".old") end
if fs.exists(prog) then fs.move(prog, prog .. ".old") end
fs.move(tmp, prog)
UPD_READY = nil
S.updatedAt = os.epoch and os.epoch("utc") or nil
save()
note("Update installed - restarting (team and job are kept)")
pcall(sendBase, "status")
sleep(1)
os.reboot()
return true
end
function setTask(t)
task = t
end


function match(name, list)
name = tostring(name or "")
local short = name:match(":(.+)$") or name
for _, p in ipairs(list or {}) do
local a, z = p:sub(1, 1) == "*", p:sub(-1) == "*"
if a and z then
if name:find(p:sub(2, -2), 1, true) then return true end
elseif a then
local s = p:sub(2)
if name:sub(-#s) == s then return true end
elseif z then
local s = p:sub(1, -2)
if name:sub(1, #s) == s then return true end
elseif p == name or p == short then
return true
end
end
return false
end
function isProtected(name) return match(name, CONFIG.protect) end
function isLiquid(name) return match(name, { "*water*", "*lava*" }) end
TOOLS = { "pickaxe", "modem", "geo_scanner", "geoscanner", "shulker", "automata", "chunk" }
function isTool(name) return match(name, { "*pickaxe*", "*modem*", "*geo_scanner*", "*geoscanner*", "*shulker*",
"*automata*", "*chunk*" }) or isEndless(name) end
function isEndless(name) return match(name, CONFIG.fuelItems) or (S.reuse and S.reuse[name]) end
function isCoal(name) return name == "minecraft:coal" or name == "minecraft:charcoal" or name == "minecraft:coal_block" end
function isJunk(name)
if match(name, CONFIG.want) or match(name, CONFIG.keep or {}) then return false end
if match(name, CONFIG.junk) then return true end

return S.junkDrops and S.junkDrops[name] and not (S.oreDrops and S.oreDrops[name]) and not isCoal(name) or false
end
function isLoot(name) return not isTool(name) and not isJunk(name) end


function sign(key, t, n, cmd, args)
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
function nextN()
local n = os.epoch("utc")
if n <= lastN then n = lastN + 1 end
lastN = n
return n
end
function modemSide()
for _, side in ipairs({ "left", "right" }) do
if peripheral.hasType(side, "modem") then return side end
end
end
function baseId()
if S.baseId then return S.baseId end
local ok, id = pcall(rednet.lookup, CONFIG.protocol, CONFIG.baseName)
if ok and id then S.baseId = id end
return S.baseId
end
function topN(t, n)
local list = {}
for k, v in pairs(t or {}) do list[#list + 1] = { k, v } end
table.sort(list, function(a, b) return a[2] > b[2] end)
local out = {}
for i = 1, math.min(n, #list) do out[list[i][1]] = list[i][2] end
return out
end

function showLink(msg)
LINK = msg
local okS, w, h = pcall(term.getSize)
if not okS or not h then return end
local x, y = term.getCursorPos()
term.setCursorPos(1, h - 1)
term.clearLine()
term.write(("> " .. (task or "")):sub(1, w))
term.setCursorPos(1, h)
term.clearLine()
term.write(msg:sub(1, w))
term.setCursorPos(x, math.min(y, h - 2))
end
function sendBase(t, extra)
if not modemSide() then showLink("NO MODEM EQUIPPED - cannot report to the base") return end
if not rednet.isOpen(modemSide()) then pcall(rednet.open, modemSide()) end
local id = baseId()
if not id then
showLink("BASE NOT FOUND - is the base's Ender Modem on? (protocol " .. CONFIG.protocol .. ")")
return
end
local m = {}
for k, v in pairs(extra or {}) do m[k] = v end
m.t, m.n = t, nextN()
m.sig = sign(S.key or "change-me", m.t, m.n)
m.mine = true
m.ses = SESSION
m.copy = COPY
if DUP then m.dup = true end
m.role, m.dim, m.ver = S.role, S.dim, MYVER
m.code = CODEVER
m.updReady = UPD_READY and UPD_READY.ver or nil
m.label = os.getComputerLabel() or ("Turtle " .. os.getComputerID())
m.task = task
local fuel = turtle.getFuelLevel()
m.fuel = fuel
m.fuelMax = (fuel ~= "unlimited") and turtle.getFuelLimit() or nil
m.rowLength = CONFIG.rowLength
m.free = freeSlots()
m.pos = S.pos and { x = S.pos.x, y = S.pos.y, z = S.pos.z, f = FNAME[S.pos.f or 0] } or nil
m.partner = (S.role == "miner") and S.leader or (S.team and S.team[1]) or nil
m.lastCmd = S.lastCmd
m.running = S.running
m.err = S.err
m.team = S.team
m.leader = S.leader
if S.role == "loader" and S.plan then
m.ci, m.phase = S.plan.ci, S.plan.phase
local n = 0
for _ in pairs(S.plan.ready or {}) do n = n + 1 end
m.ready = n
m.rowLength = CONFIG.rowLength
m.transit = S.plan.transit
end
if S.role == "miner" then
local J, tp = S.job, S.tp
m.ci = J and J.ci or nil
m.li = J and J.li or nil
m.nl = tp and #layers(tp.yt) or nil
m.li = J and J.cur or nil
m.phase = J and J.phase or nil
m.idx = myIndex()
m.station = S.station and true or false
m.nextDump = S.lastDump and math.max(0, CONFIG.dumpEvery - (now() - S.lastDump)) or nil
m.carry = topN(S.carry, 12)
m.got = topN(S.got, 12)
m.stats = S.stats
end
if #NOTES > 0 then m.notes = NOTES NOTES = {} end
local okS, errS = pcall(rednet.send, id, m, CONFIG.protocol)


if S.role == "miner" and S.leader then pcall(sendTeam, S.leader, "hello", { dumping = S.dumping and true or false }) end
showLink(okS and ("reported to base #" .. id .. " at " .. textutils.formatTime(os.time(), true) ..
" (key " .. tostring(S.key) .. ")")
or ("SEND FAILED: " .. tostring(errS)))
LAST_STATUS = os.clock()
end
function sendTeam(to, t, extra)
if DUP or not modemSide() then return end
if not rednet.isOpen(modemSide()) then pcall(rednet.open, modemSide()) end
local m = {}
for k, v in pairs(extra or {}) do m[k] = v end
m.t, m.n = t, nextN()
m.sig = sign(S.key or "change-me", m.t, m.n)
m.dim = S.dim
m.from, m.to = MYTID, to

if S.role == "miner" and S.station then m.st = { x = S.station.x, y = S.station.y, z = S.station.z } end
if to then pcall(rednet.send, to % 100000, m, CONFIG.team) else pcall(rednet.broadcast, m, CONFIG.team) end
end

JOIN_SAID = {}

function minerHere(to)
local p = S.pos
sendTeam(to, "minerhere", { pos = (p and p.x) and { x = p.x, y = p.y, z = p.z } or nil })
end

function isMember(id)
for _, t in ipairs(S.team or {}) do if t == id then return true end end
return false
end

function handle(id, m, proto)
if type(m) ~= "table" then return end
if HEAR_ONLY_DUP then



if not (proto == CONFIG.protocol and m.cmd == "dupstop") then
BACKLOG[#BACKLOG + 1] = { id, m, proto }
return
end
HEAR_ONLY_DUP = false
end
if proto == CONFIG.protocol and m.t == "cmd" then
if m.ses ~= nil and m.ses ~= SESSION then return end
if (tonumber(m.copy) or 0) ~= (COPY or 0) then return end
if DUP and m.cmd ~= "dupfree" and m.cmd ~= "dupstop" and m.cmd ~= "becomecopy" then return end
if type(m.n) ~= "number" or m.n <= (S.lastCmd or 0) then return end
if m.sig ~= sign(S.key or "change-me", "cmd", m.n, m.cmd, m.args) then return end
S.lastCmd = m.n
S.baseId = id
if m.cmd == "dupstop" then
if not DUP then dupPark() end
return
elseif m.cmd == "dupfree" then
DUP = false
return
elseif m.cmd == "becomecopy" then
becomeCopy(tonumber((m.args or {})[1]))
return
end
doCmd(tostring(m.cmd), m.args or {})
save()
elseif DUP then
return
elseif proto == CONFIG.team then
if type(m.n) ~= "number" or m.sig ~= sign(S.key or "change-me", m.t, m.n) then return end
if m.to and tonumber(m.to) ~= MYTID then return end
id = tonumber(m.from) or id
if m.dim ~= S.dim then return end
if S.role == "loader" then
S.seen = S.seen or {}
S.seen[id] = now()
if S.lost then S.lost[id] = nil end

if S.pausedFor == id and S.plan then
S.pausedFor, S.err = nil, nil
S.running, S.plan.running = true, true
note("Miner " .. id .. " is back - the team goes on by itself")
save()
sendPlan()
end

if S.stationUse and S.stationUse.id == id and m.t == "hello" and m.dumping == false
and now() - (S.stationUse.t or 0) > 30 then
S.stationUse = nil
end
if type(m.st) == "table" and tonumber(m.st.x) and tonumber(m.st.z) then
S.stations = S.stations or {}
S.stations[id] = { x = tonumber(m.st.x), y = tonumber(m.st.y) or 0, z = tonumber(m.st.z) }
end
if m.t == "minerhere" then
S.team = S.team or {}
local inTeam = false
for _, t in ipairs(S.team) do if t == id then inTeam = true end end

local can = not inTeam and #S.team < CONFIG.maxMiners
and not (S.plan and S.dropped and S.dropped[id])
if can and S.plan and S.running then




local P = S.plan
local why, text
if P.phase ~= "work" then
why = "wait"
else
local cx, cz = chunkAt(P, P.ci)
local mx, mz = center(cx, cz)
local p, R = m.pos, tonumber(CONFIG.joinRange) or 40
if type(p) ~= "table" or not tonumber(p.x) or not tonumber(p.z) then
why, text = "old", "it runs an old miner.lua (or has no position) - copy the new miner.lua onto it"
elseif math.abs(p.x - mx) > R or math.abs(p.z - mz) > R then
why, text = "far", "it is too far away - put it within " .. R .. " blocks of " .. mx .. ", " .. mz ..
" (the chunk the team works in now)"
end
end
if not why then
S.team[#S.team + 1] = id
P.ready[id] = nil
JOIN_SAID[id] = nil
save()
note("Miner " .. id .. " joined the RUNNING team as miner " .. #S.team .. " (chunk " .. P.ci ..
") - the team waits for it before the next crossing")
inTeam = true
elseif text and JOIN_SAID[id] ~= why then
JOIN_SAID[id] = why
note("Miner " .. id .. " wants to join but cannot yet: " .. text)
sendTeam(id, "joinno", { why = text })
end
elseif can then
S.team[#S.team + 1] = id
if not S.plan then table.sort(S.team) end
save()
note("Miner " .. id .. " joined the team (" .. #S.team .. ")")
inTeam = true
end
if inTeam then sendPlan() end
elseif (m.t == "ready" or m.t == "needlayer" or m.t == "unloadreq") and not isMember(id) then

sendTeam(id, "team", { team = S.team, plan = S.plan })
elseif m.t == "ready" and S.plan and m.ci == S.plan.ci then
S.plan.ready[id] = m.ci
save()
elseif m.t == "needlayer" and S.plan and m.ci == S.plan.ci then
local P = S.plan
P.assigned = P.assigned or {}
if m.done and P.assigned[id] == m.done then P.assigned[id] = nil end
if not P.assigned[id] then
P.queue = P.queue or {}
P.assigned[id] = table.remove(P.queue, 1)
end
save()
sendTeam(id, "layer", { ci = P.ci, li = P.assigned[id] })
elseif m.t == "stepped" then
STEPPED = STEPPED or {}
STEPPED[id] = true
elseif m.t == "unloadreq" then


local st = S.stationUse
if not st or st.id == id or type(st.t) ~= "number" or now() - st.t > 360 or now() < st.t then
S.stationUse = { id = id, t = now() }
sendTeam(id, "unloadok")
else
sendTeam(id, "unloadwait", { who = st.id })
end
elseif m.t == "unloaded" then
if S.stationUse and S.stationUse.id == id then S.stationUse = nil end
end
elseif S.role == "miner" then
if id == S.leader then LEADER_SEEN = os.clock() end


if m.t == "loaderhere" and S.leader and id ~= S.leader and os.clock() - (LEADER_SEEN or 0) > 600
and not crossingDue() then
note("My loader #" .. S.leader .. " is silent for 10+ min - offering myself to loader #" .. id)
S.leader, S.team, S.tp, S.job, S.running = nil, nil, nil, nil, false
save()
end
if m.t == "loaderhere" and not S.leader then
minerHere(id)
elseif m.t == "joinno" and not S.leader then

if S.joinNo ~= m.why then
S.joinNo = m.why
note("Cannot join loader " .. id .. "'s running team yet: " .. tostring(m.why))
end
elseif m.t == "team" and (not S.leader or S.leader == id) then
local mine = false
for _, t in ipairs(m.team or {}) do if t == MYTID then mine = true end end
if mine then
if S.leader ~= id then note("In the team of loader " .. id) end
S.leader, S.team = id, m.team
S.joinNo = nil
local newPlan = m.plan and (not S.tp or S.tp.id ~= m.plan.id)


if newPlan and (tonumber(m.plan.ci) or 0) > 0 then S.lateFor = m.plan.id end
S.tp = m.plan or nil
if not m.plan then S.job = nil end
S.running = (m.plan and m.plan.running) and true or false
if newPlan or not m.plan then GO = nil end
if newPlan then S.err = nil end
save()
elseif S.leader == id then


S.leader, S.team, S.tp, S.job, S.running = nil, nil, nil, nil, false
note("Taken out of the team by the loader - waiting to join again")
save()
end
elseif m.t == "go" and id == S.leader then
GO = m.ci
elseif m.t == "layer" and id == S.leader then
LAYER = { ci = m.ci, li = m.li }
elseif m.t == "unloadok" and id == S.leader then
UNLOAD_OK = true
elseif m.t == "unloadwait" and id == S.leader then
UNLOAD_OK = false
elseif m.t == "unloadnow" and id == S.leader then
DUMP_NOW = true
end
end
end
end
function doCmd(cmd, args)

if cmd == "start" then
S.err, S.pausedFor, FAILS = nil, nil, 0
if S.role == "loader" then
local ok, err = true, nil
if not S.plan then ok, err = newTeamPlan() end
if ok then
S.running, S.plan.running = true, true
note("START (" .. #S.team .. " miners)")
else
S.err = "cannot start: " .. tostring(err)
note(S.err)
end
save()
sendPlan()
end
elseif cmd == "pause" then
S.running = false
if S.role == "loader" and S.plan then S.plan.running = false sendPlan() end
note("PAUSED")
elseif cmd == "unload" then
if S.role == "loader" then teamMsg("unloadnow") else DUMP_NOW = true end
note("Unload asked")
elseif cmd == "newfield" then
S.running = false
if S.role == "loader" and S.plan and S.plan.goSent == S.plan.ci then
NEWFIELD_LATER = true
note("New field after this crossing (the miners are on their way over)")
sendBase("status")
return
end
if S.role == "loader" then
S.plan = nil
teamMsg("team", { team = S.team, plan = false })
end
S.job = nil
note("New field: it starts where the loader stands (the way it faces) on the next START")
elseif cmd == "drop" then


local id = tonumber(args[1])
if S.role == "loader" and id then
local found = false
for i = #(S.team or {}), 1, -1 do if S.team[i] == id then table.remove(S.team, i) found = true end end
if S.plan then
local P = S.plan


P.ready = {}
if P.phase == "cross" and P.goSent ~= P.ci then P.phase = "work" end
if P.assigned and P.assigned[id] then
P.queue = P.queue or {}
table.insert(P.queue, 1, P.assigned[id])
P.assigned[id] = nil
end
end
if S.seen then S.seen[id] = nil end
if S.lost then S.lost[id] = nil end
if S.stationUse and S.stationUse.id == id then S.stationUse = nil end
S.dropped = S.dropped or {}
S.dropped[id] = true
if found then S.err = nil end
save()
sendPlan()
sendTeam(id, "team", { team = S.team, plan = S.plan })
note(found and ("Miner " .. id .. " taken out of the team (" .. #S.team .. " left)") or ("Miner " .. id .. " is not in the team"))
end
elseif cmd == "upd" then
updPiece(args)
elseif cmd == "unpair" then
S.partner, S.leader, S.team, S.tp = nil, nil, nil, nil
note("Left the team")
elseif cmd == "cfg" then

S.cfg = S.cfg or {}
for _, a in ipairs(args) do
local k, v = tostring(a):match("^([%w_]+)=(.*)$")
if k then
local val
if k == "want" or k == "keep" or k == "extraOres" or k == "skipOres" or k == "fuelItems" then
val = {}
for w in v:gmatch("[^,]+") do val[#val + 1] = w end
else
val = tonumber(v)
end
if val ~= nil then CONFIG[k] = val S.cfg[k] = val end
end
end
elseif cmd == "status" then

end
sendBase("status")
end



function dupPark()
DUP = true
S.running = false
task = "DUPLICATE copy - stopped (break me)"
local okG, x, y, z = pcall(gps.locate, 2)
if okG and x then S.pos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5), f = S.pos and S.pos.f } end
note("I am a DUPLICATE copy of this turtle (server crash) - stopped here, break me")
print("DUPLICATE COPY of this turtle (server crash) - stopped. Break this one.")
while true do
pcall(sendBase, "status")
listen(30)
if not DUP then os.reboot() end
end
end


BACKLOG = {}
HEAR_ONLY_DUP = false
function hearDup()
HEAR_ONLY_DUP = true
local t0 = os.clock()
while os.clock() - t0 < 0.05 do
local id, m, proto = rednet.receive(nil, 0.05)
if not id then break end
handle(id, m, proto)
end
HEAR_ONLY_DUP = false
end





function becomeCopy(k)
if not k or k < 1 then return end
DUP = true
local name = (os.getComputerLabel() or ("Turtle " .. os.getComputerID())):gsub("%s*%[c%d+%]%s*$", "")
name = name .. " [c" .. k .. "]"
os.setComputerLabel(name)
local own = { role = S.role, key = S.key, dim = S.dim, cfg = S.cfg, reuse = S.reuse, station = S.station,
oreDrops = S.oreDrops, junkDrops = S.junkDrops, running = false }
local okG, x, y, z = pcall(gps.locate, 2)
if okG and x then own.pos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5), f = S.pos and S.pos.f }
elseif S.pos then own.pos = { x = S.pos.x, y = S.pos.y, z = S.pos.z, f = S.pos.f } end
pcall(function()
local h = fs.open("miner_state_c" .. k, "w")
h.write(textutils.serialize(own))
h.close()
end)
pcall(sendBase, "result", { cmd = "becomecopy", ok = true, msg = "now '" .. name .. "' - restarting as a team member of its own" })
print("I am a COPY - now '" .. name .. "'. Restarting as a turtle of my own.")
sleep(1)
os.reboot()
end


function listen(secs)
while #BACKLOG > 0 and not HEAR_ONLY_DUP do
local b = table.remove(BACKLOG, 1)
handle(b[1], b[2], b[3])
end
local t0 = os.clock()
while true do
local left = secs - (os.clock() - t0)
if left <= 0 then break end
local id, m, proto = rednet.receive(nil, left)
if id then handle(id, m, proto) end
end
end


function freeSlots()
local n = 0
for i = 1, 16 do if turtle.getItemCount(i) == 0 then n = n + 1 end end
return n
end
function findSlot(test)
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and test(d.name) then return i, d end
end
end
function dropJunk()
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and isJunk(d.name) then
turtle.select(i)
if not turtle.dropUp() then turtle.dropDown() end
end
end
turtle.select(1)
end

function burnCoal()
local fuel = turtle.getFuelLevel()
if fuel == "unlimited" or fuel >= CONFIG.lowFuel then return end



local cc = core()
if cc and type(cc.chargeTurtle) == "function" then
local okC, got = pcall(cc.chargeTurtle, CONFIG.fuelTarget - fuel)
if okC and tonumber(got) and tonumber(got) > 0 then
if not S.cellUsed then S.cellUsed = true note("Charged " .. got .. " fuel from an energy cell - cells are used first") end
fuel = turtle.getFuelLevel()
if fuel >= CONFIG.lowFuel then return end
end
end

for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and isEndless(d.name) then
turtle.select(i)
for _ = 1, 500 do
local before, n0 = turtle.getFuelLevel(), turtle.getItemCount(i)
if before >= CONFIG.fuelTarget then break end
local ok = turtle.refuel(1)
if not ok or turtle.getFuelLevel() <= before then
if not S.notFuel then S.notFuel = true note(d.name .. " does not work as turtle fuel here") end
break
end
if turtle.getItemCount(i) < n0 then break end
end
end
end
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and isCoal(d.name) then
turtle.select(i)
while turtle.getFuelLevel() < CONFIG.fuelTarget and turtle.getItemCount(i) > 0 do
if not turtle.refuel(1) then break end
end
end
end




if turtle.getFuelLevel() < CONFIG.lowFuel then
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and not isTool(d.name) and not isCoal(d.name) and not isJunk(d.name) then
turtle.select(i)
if turtle.refuel(0) then
while turtle.getFuelLevel() < CONFIG.fuelTarget do
local before = turtle.getFuelLevel()
if not turtle.refuel(1) or turtle.getFuelLevel() <= before then break end
local after = turtle.getItemDetail(i)
if after and after.name == d.name and after.count == d.count then
S.reuse = S.reuse or {}
if not S.reuse[d.name] then
S.reuse[d.name] = true
note("Endless fuel found: " .. d.name .. " (kept, never unloaded)")
save()
end
elseif not after or after.name ~= d.name then
break
end
end
end
end
end
end
turtle.select(1)
end


function dropLoot(dropFn)
local moved, keptCoal = {}, 0
local own = {}
for k, v in pairs(S.own or {}) do own[k] = v end
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and isLoot(d.name) then
local give = d.count

if own[d.name] and own[d.name] > 0 then
local keep = math.min(give, own[d.name])
own[d.name] = own[d.name] - keep
give = give - keep
end
if isCoal(d.name) and keptCoal < CONFIG.keepCoal then
local keep = math.min(d.count, CONFIG.keepCoal - keptCoal)
keptCoal = keptCoal + keep
give = d.count - keep
end
if give > 0 then
turtle.select(i)
local before = turtle.getItemCount(i)
dropFn(give)
local went = before - turtle.getItemCount(i)
if went > 0 then moved[d.name] = (moved[d.name] or 0) + went end
end
end
end
turtle.select(1)
return moved
end
function addTo(t, moved)
for k, v in pairs(moved) do t[k] = (t[k] or 0) + v end
end


function coreSide()
for _, side in ipairs({ "left", "right" }) do
local t = peripheral.getType(side)
if t and tostring(t):lower():gsub("[^%a]", ""):find("automata", 1, true) then return side end
end
end
function toolSide()
local c = coreSide()
if c == "left" then return "right" end
return "left"
end






function toolNow()
local side = toolSide()
local f = (side == "left") and turtle.getEquippedLeft or turtle.getEquippedRight
if f then
local ok, d = pcall(f)
if ok then
if type(d) ~= "table" or not d.name then return "none" end
local n = tostring(d.name):lower()
if n:find("modem", 1, true) then return "modem" end
if n:find("geo", 1, true) then return "geo" end
if n:find("pickaxe", 1, true) then return "pickaxe" end
return n
end
end
local t = peripheral.getType(side)
if not t then return "pickaxe" end
t = tostring(t):lower()
if t:find("geo", 1, true) then return "geo" end
if t:find("modem", 1, true) then

local okW, w = pcall(peripheral.call, side, "isWireless")
if okW and w == false then return "pickaxe" end
return "modem"
end
return "pickaxe"
end
TOOL_ITEM = { pickaxe = "*pickaxe*", modem = "*modem*", geo = "*geo_scanner*" }
function equipTool(kind)
if toolNow() == kind then

if kind == "modem" and not rednet.isOpen(toolSide()) then pcall(rednet.open, toolSide()) end
return true
end
local slot = findSlot(function(n) return match(n, { TOOL_ITEM[kind] }) end)
if not slot then
return false, "no " .. kind .. " in the inventory"
end
turtle.select(slot)
local side = toolSide()
local ok = (side == "left") and turtle.equipLeft() or turtle.equipRight()
turtle.select(1)
if not ok then return false, "could not equip the " .. kind end

for _ = 1, 40 do
if toolNow() == kind then break end
sleep(0.05)
end
if toolNow() ~= kind then return false, "the " .. kind .. " did not show up after equipping it" end
if kind == "modem" then pcall(rednet.open, side) end
return true
end
function ensurePick()
if S.role ~= "miner" then return false end
return equipTool("pickaxe")
end


function turnTo(f)
f = f % 4
local d = (f - S.pos.f) % 4
if d == 1 then turtle.turnRight()
elseif d == 2 then turtle.turnRight() turtle.turnRight()
elseif d == 3 then turtle.turnLeft() end
S.pos.f = f
end

function cellFor(d)
local p = S.pos
if d == "u" then return p.x, p.y + 1, p.z end
if d == "d" then return p.x, p.y - 1, p.z end
return p.x + DX[p.f], p.y, p.z + DZ[p.f]
end
function nearStation(x, z, r)
local st = S.station
if not st then return false end
return math.sqrt((x - st.x) ^ 2 + (z - st.z) ^ 2) < r
end

function digDir(d)
local insp = (d == "u" and turtle.inspectUp) or (d == "d" and turtle.inspectDown) or turtle.inspect
local okI, b = insp()
if not okI then return true end
if isLiquid(b.name) then return true end
if isProtected(b.name) then return false, "will not dig " .. b.name end
local x, _, z = cellFor(d)
if nearStation(x, z, CONFIG.noDig) then return false, "too close to the unload station - no digging there" end
local okP, errP = ensurePick()
if not okP then return false, errP end
local dig = (d == "u" and turtle.digUp) or (d == "d" and turtle.digDown) or turtle.dig
local before = {}
for i = 1, 16 do before[i] = turtle.getItemCount(i) end
local okD, err = dig()
if not okD then return false, tostring(err or "cannot dig") end
S.stats.dug = S.stats.dug + 1
learnDrops(before, DIG_TARGET or isOreBlock(b) or match(b.name, CONFIG.want))
return true
end



function learnDrops(before, fromOre)
S.oreDrops, S.junkDrops = S.oreDrops or {}, S.junkDrops or {}
for i = 1, 16 do
if turtle.getItemCount(i) > before[i] then
local dd = turtle.getItemDetail(i)
if dd and not isTool(dd.name) then
if fromOre then S.oreDrops[dd.name] = true
elseif not S.oreDrops[dd.name] and not S.junkDrops[dd.name] then S.junkDrops[dd.name] = true end
end
end
end
end




function step(d)
if S.role ~= "miner" then burnCoal() end


if S.role == "miner" and os.clock() - (LAST_HEAR or 0) > 10 then
LAST_HEAR = os.clock()
hearDup()
end
if CHUNK_LOCK and S.role == "miner" then
local x, _, z = cellFor(d)
if math.floor(x / 16) ~= CHUNK_LOCK[1] or math.floor(z / 16) ~= CHUNK_LOCK[2] then
gpsCheck()
local f = checkFacing()
if f then S.pos.f = f end
return false, "would leave chunk " .. CHUNK_LOCK[1] .. "," .. CHUNK_LOCK[2] .. " (position re-checked - next try)"
end
end
local mv = (d == "u" and turtle.up) or (d == "d" and turtle.down) or turtle.forward
local det = (d == "u" and turtle.detectUp) or (d == "d" and turtle.detectDown) or turtle.detect
local att = (d == "u" and turtle.attackUp) or (d == "d" and turtle.attackDown) or turtle.attack
local insp = (d == "u" and turtle.inspectUp) or (d == "d" and turtle.inspectDown) or turtle.inspect
for try = 1, 60 do
if mv() then
local x, y, z = cellFor(d)
S.pos.x, S.pos.y, S.pos.z = x, y, z
if TUNNEL2 and d == "f" and S.role == "miner" then
for _ = 1, 8 do
if not turtle.detectUp() or not digDir("u") then break end
end
end
afterMove()
return true
end
if turtle.getFuelLevel() == 0 then return false, "out of fuel" end
local okI, bI = insp()
if okI and tostring(bI.name):find("computercraft:turtle", 1, true) then

if try >= 50 then return false, "a turtle is in the way at " .. fmtPos() end
if try % 10 == 1 then setTask("a team mate is in the way - waiting") end
sleep(1)
elseif det() then
if S.role == "miner" then
local ok, err = digDir(d)
if not ok then return false, err end
else

if try % 10 == 0 then setTask("blocked at " .. fmtPos() .. " - waiting") sendBase("status") end
sleep(1)
end
else
if S.role == "miner" then ensurePick() pcall(att) end
sleep(0.3)
end
end
return false, "blocked at " .. fmtPos()
end


function goTo(x, y, z, trail)
local function addPt()
if trail then
local l = trail[#trail]
if not l or l.x ~= S.pos.x or l.y ~= S.pos.y or l.z ~= S.pos.z then
trail[#trail + 1] = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
end
end
end
local function vert()
while S.pos.y < y do local ok, e = step("u") if not ok then return false, e end end
while S.pos.y > y do local ok, e = step("d") if not ok then return false, e end end
addPt()
return true
end
if y > S.pos.y then local ok, e = vert() if not ok then return false, e end end
if x ~= S.pos.x then
turnTo(x > S.pos.x and 1 or 3)
while S.pos.x ~= x do local ok, e = step("f") if not ok then return false, e end end
addPt()
end
if z ~= S.pos.z then
turnTo(z > S.pos.z and 2 or 0)
while S.pos.z ~= z do local ok, e = step("f") if not ok then return false, e end end
addPt()
end
if y ~= S.pos.y then local ok, e = vert() if not ok then return false, e end end
return true
end
function fmtPos()
local p = S.pos or {}
return tostring(p.x) .. " " .. tostring(p.y) .. " " .. tostring(p.z)
end


function afterMove()
if S.role ~= "miner" then
save()
if os.clock() - LAST_STATUS > 10 then sendBase("status") end
return
end
save()
if STASHING then return end

if os.clock() - LAST_CHECK > CONFIG.checkIn then
LAST_CHECK = os.clock()
if equipTool("modem") then
sendBase("status")
listen(1.5)
end
end
keepInventory()
end

function keepInventory()
if STASHING then return end
burnCoal()
if freeSlots() <= 2 then
dropJunk()
if freeSlots() <= 2 then

local mined = false
local own = {}
for k, v in pairs(S.own or {}) do own[k] = v end
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and isLoot(d.name) and not isCoal(d.name) then
local keep = math.min(d.count, own[d.name] or 0)
own[d.name] = (own[d.name] or 0) - keep
if d.count > keep then mined = true end
end
end
if not mined then
HALT = "the inventory is full of YOUR items (in it before START) - take them out, then START"
else
local ok, err = stash()
if not ok then note("Could not use the shulker: " .. tostring(err)) DUMP_NOW = true end
end
end
end
end




function stash()
local slot = findSlot(function(n) return n:find("shulker", 1, true) ~= nil end)
if not slot then return false, "no shulker box" end
STASHING = true
local okP, okR, errR = pcall(function()

local ok, e = digDir("f")
if not ok then return false, e end
ok, e = step("u")
if not ok then return false, e end


for _ = 1, 12 do
ok, e = digDir("f")
if not ok or not turtle.detect() then break end
sleep(0.4)
end
if ok and turtle.detect() then ok, e = false, "falling blocks keep filling the space above the shulker" end
local okD, eD = step("d")
if not ok then return false, e end
if not okD then return false, eD end
slot = findSlot(function(n) return n:find("shulker", 1, true) ~= nil end)
turtle.select(slot)
if not turtle.place() then turtle.select(1) return false, "could not place the shulker" end
local moved = dropLoot(function(n) return turtle.drop(n) end)
addTo(S.carry, moved)
local left = 0
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and isLoot(d.name) and not isCoal(d.name) then left = left + 1 end
end
ensurePick()
turtle.select(1)
local okG = turtle.dig()
if not okG then return false, "could not pick the shulker up again!" end
save()
if left > 0 then DUMP_NOW = true return true end
return true
end)
STASHING = false
if not okP then okR, errR = false, tostring(okR) end
turtle.select(1)
return okR, errR
end


function core() local s = coreSide() return s and peripheral.wrap(s) end
function hasPoint(c, name)
local okP, pts = pcall(c.getPoints)
if not okP or type(pts) ~= "table" then return nil end
for k, v in pairs(pts) do if v == name or k == name then return true end end
return false
end
function savePoint(name)
local c = core()
if not c then return false, "no End Automata Core equipped" end
pcall(c.deletePoint, name)
local ok, a, b = pcall(c.savePoint, name)
if not ok or a == false or a == nil then return false, tostring(b or a) end
return true
end
function warp(name, pt)
local c = core()
if not c then return false, "no End Automata Core equipped" end
if hasPoint(c, name) == false then return false, "warp point '" .. name .. "' is not in the core any more" end
local okC, cost = pcall(c.estimateWarpCost, name)
cost = okC and tonumber(cost) or 0
local fuel = turtle.getFuelLevel()
if fuel ~= "unlimited" and cost > fuel - 100 then return false, "not enough fuel to teleport (" .. cost .. ")" end
local ok, a, b = pcall(c.warpToPoint, name)
if not ok or a == false or a == nil then return false, "teleport failed: " .. tostring(b or a) end
S.pos.x, S.pos.y, S.pos.z = pt.x, pt.y, pt.z
save()
return true
end

function whereAmI()
local c = core()
if not c then return nil end
local okA, a = pcall(c.estimateWarpCost, "station")
local okB, b = pcall(c.estimateWarpCost, "work")
a, b = okA and tonumber(a), okB and tonumber(b)
if a and b then return (a <= b) and "station" or "work" end
end
function stationHere()
local ok, err = savePoint("station")
if not ok then print("Could not save the station: " .. tostring(err)) return false end
S.station = { x = S.pos.x, y = S.pos.y, z = S.pos.z, f = S.pos.f }
save()
print("Unload station saved here: " .. fmtPos() .. " facing " .. FNAME[S.pos.f])
return true
end


function unloadHere()
turnTo(S.station.f)
local total = {}
addTo(total, S.carry)
local front = peripheral.isPresent("front") and peripheral.hasType("front", "inventory")
local sh = findSlot(function(n) return n:find("shulker", 1, true) ~= nil end)
if front then

local moved = dropLoot(function(n) return turtle.drop(n) end)
addTo(total, moved)
if sh and next(S.carry) then
if turtle.detectUp() then
note("Unload: no room above the station for the shulker - its items stay in it")
else
turtle.select(sh)
if turtle.placeUp() then
setTask("unloading the shulker")
local stuck = 0
while true do
local free
for i = 1, 16 do if turtle.getItemCount(i) == 0 then free = i break end end
if not free then break end
turtle.select(free)
if not turtle.suckUp(64) then break end
if not turtle.drop() then
stuck = stuck + 1
turtle.dropUp()
note("Unload: the inventory in front is full")
break
end
end
ensurePick()
turtle.select(1)
if not turtle.digUp() then note("Could not pick the shulker up at the station!") end
if stuck == 0 then S.carry = {} end
end
end
elseif not next(S.carry) then
S.carry = {}
end
else

if not sh then return false, "no shulker box to unload with" end
if turtle.detect() then return false, "the block in front of the station is not empty" end
turtle.select(sh)
if not turtle.place() then turtle.select(1) return false, "could not place the shulker at the station" end
local moved = dropLoot(function(n) return turtle.drop(n) end)
addTo(total, moved)
local p = peripheral.wrap("front")
local t0 = os.clock()
while p and os.clock() - t0 < 600 do
local okL, list = pcall(p.list)
local n = 0
if okL and type(list) == "table" then for _, it in pairs(list) do n = n + (it.count or 0) end end
if n == 0 then break end
setTask("waiting for the Import Bus (" .. n .. " items left)")
if os.clock() - LAST_STATUS > 10 then sendBase("status") end
sleep(2)
end
ensurePick()
turtle.select(1)
if not turtle.dig() then note("Could not pick the shulker up at the station!") end
S.carry = {}
end
addTo(S.got, total)
local n = 0
for _, v in pairs(total) do n = n + v end
S.stats.dumps = S.stats.dumps + 1
note("Unloaded " .. n .. " items")
turtle.select(1)
return true
end
function doDump()
DUMP_NOW = false
if not S.station then
note("No unload station set - everything stays in the shulker")
S.lastDump = now()
return true
end
setTask("teleporting to the unload station")
local ok, err = savePoint("work")
if not ok then return false, "cannot save the work spot: " .. tostring(err) end
S.workPt = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
S.dumping = "warping"
save()
ok, err = warp("station", S.station)
if not ok then


S.dumping = nil
S.dumpFails = (S.dumpFails or 0) + 1
local waitS = math.min(3600, 300 * 2 ^ (S.dumpFails - 1))
S.dumpRetry = now() + waitS
save()
note("Cannot teleport to the unload station (" .. tostring(err) .. ") - working on, trying again in " ..
math.floor(waitS / 60) .. " min")
return true, "later"
end
S.dumpFails, S.dumpRetry = nil, nil
S.dumping = "at"
save()
return finishDump()
end
function finishDump()
local ok, err = unloadHere()
if not ok then note("Unload failed: " .. tostring(err)) end
burnCoal()
setTask("teleporting back to work")
local okW, errW = warp("work", S.workPt)


local tries = 1
while not okW and tries < 12 do
if not S.running then return false, "paused" end
local waitS = math.min(180, 20 * tries)
setTask("at the station: cannot teleport back (" .. tostring(errW) .. ") - again in " .. waitS .. " s")
note("Cannot teleport back to work (" .. tostring(errW) .. ") - trying again in " .. waitS .. " s")
equipTool("modem")
sendBase("status")
local t0 = os.clock()
while os.clock() - t0 < waitS do listen(2) end
burnCoal()
tries = tries + 1
okW, errW = warp("work", S.workPt)
end
if not okW then return false, "cannot teleport back: " .. tostring(errW) end
S.dumping = nil
S.lastDump = now()
save()
return true
end


function layers(yt)
local out = {}
local y = yt
while y >= CONFIG.minY do out[#out + 1] = y y = y - CONFIG.layerStep end

if #out > 0 and out[#out] - CONFIG.minY > 5 then out[#out + 1] = CONFIG.minY end
return out
end



function chunkAt(P, i)
local T = P.transit or 0
if i < T then return P.sx + DX[P.f] * i, P.sz + DZ[P.f] * i end
local cx, cz = fieldAt(P, i - T)
return cx + DX[P.f] * T, cz + DZ[P.f] * T
end
function fieldAt(P, i)
local L = math.max(1, CONFIG.rowLength)
local r, k = math.floor(i / L), i % L
local along = (r % 2 == 0) and k or (L - 1 - k)
local rf = (P.f + 1) % 4
local cx = P.sx + DX[P.f] * along + DX[rf] * r
local cz = P.sz + DZ[P.f] * along + DZ[rf] * r
return cx, cz
end
function center(cx, cz) return cx * 16 + 8, cz * 16 + 8 end




function rememberOwn()
local cur = {}
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and not isTool(d.name) and not isCoal(d.name) then cur[d.name] = (cur[d.name] or 0) + d.count end
end
if S.own then
local keep = {}
for n, c in pairs(cur) do if S.own[n] then keep[n] = math.min(c, S.own[n]) end end
S.own = keep
return
end
S.own = cur
if next(S.own) then note("Items in me at START are kept (not unloaded)") end
end

function gpsHere(timeout)
if S.role == "miner" and not modemSide() then equipTool("modem") end
if not gps or not modemSide() then return nil end
local ok, x, y, z = pcall(gps.locate, timeout or 1)
if not ok or not x then return nil end
return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
end

function gpsCheck()
if not S.pos then return end
local x, y, z = gpsHere(1)
if not x then return end
S.gpsOk = true
if x ~= S.pos.x or y ~= S.pos.y or z ~= S.pos.z then
note("GPS: position corrected " .. fmtPos() .. " -> " .. x .. " " .. y .. " " .. z)
S.pos.x, S.pos.y, S.pos.z = x, y, z
save()
end
end


function gpsFacing(canDig)
local x0, _, z0 = gpsHere(2)
if not x0 then return nil end
if canDig and S.role == "miner" and turtle.detect() then
local okI, b = turtle.inspect()
if okI and not isProtected(b.name) then digDir("f") end
end
local function dirOf(dx, dz)
for i = 0, 3 do if DX[i] == dx and DZ[i] == dz then return i end end
end
for turn = 0, 3 do
if turtle.forward() then
local x1, _, z1 = gpsHere(2)
turtle.back()
return x1 and dirOf(x1 - x0, z1 - z0)
elseif turtle.back() then
local x1, _, z1 = gpsHere(2)
turtle.forward()
local f = x1 and dirOf(x0 - x1, z0 - z1)
return f
end
turtle.turnRight()
S.pos.f = (S.pos.f + 1) % 4
end
return nil
end




function scanFacing()
if S.role ~= "miner" then return nil end
local res = geoScan(1)
if not res then return nil end
local nb = {}
for _, b in ipairs(res) do
if b.y == 0 and math.abs(b.x) + math.abs(b.z) == 1 then
for i = 0, 3 do if DX[i] == b.x and DZ[i] == b.z then nb[i] = b.name end end
end
end
local seen = {}
for k = 0, 3 do
local okI, bI = turtle.inspect()
seen[k] = okI and bI.name or nil
turtle.turnRight()
end
local found
for f = 0, 3 do
local all = true
for k = 0, 3 do
local a, b = seen[k], nb[(f + k) % 4]

local same = (a == b) or (a and b and a:find("computercraft:turtle", 1, true) and b:find("computercraft:turtle", 1, true))
if not same then all = false break end
end
if all then
if found then return nil end
found = f
end
end
return found
end

function checkFacing()
if S.role == "miner" then
local f = scanFacing()
if f then return f end


local lx, lz = S.pos.x % 16, S.pos.z % 16
if lx >= 1 and lx <= 14 and lz >= 1 and lz <= 14 then
equipTool("modem")
return gpsFacing(true)
end
return nil
end


return gpsFacing()
end

function checkpoint()
if os.clock() - LAST_CHECK > CONFIG.checkIn then
LAST_CHECK = os.clock()
if equipTool("modem") then
gpsCheck()
sendBase("status")
listen(1.5)
end
end
if HALT then
local e = HALT
HALT = nil
return false, e
end
if not S.running then return false, "paused" end
if (DUMP_NOW or (S.lastDump and now() - S.lastDump > CONFIG.dumpEvery)) and now() >= (S.dumpRetry or 0) then

local any = next(S.carry) ~= nil
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and isLoot(d.name) and not isCoal(d.name) then any = true end
end
if not any then
DUMP_NOW = false
S.lastDump = now()
elseif S.job and S.job.phase == "ready" then

elseif S.leader then

if os.clock() - (UNLOAD_ASKED or -100) > 20 then
UNLOAD_ASKED, UNLOAD_OK = os.clock(), nil
if equipTool("modem") then
sendTeam(S.leader, "unloadreq")
local t0 = os.clock()
while UNLOAD_OK == nil and os.clock() - t0 < 2 do listen(0.5) end
end
if UNLOAD_OK then
local ok, err = doDump()
equipTool("modem")
sendTeam(S.leader, "unloaded")
if not ok then return false, err end
else
setTask("unload: another miner is at the station - later")
end
end
else
local ok, err = doDump()
if not ok then return false, err end
end
end
return true
end



function geoScan(radius)
local ok, err = equipTool("geo")
if not ok then return nil, err end
local side = toolSide()
local okM, methods = pcall(peripheral.getMethods, side)
methods = okM and methods or {}
local fname
for _, mth in ipairs(methods) do if mth == "scan" then fname = mth end end
if not fname then
for _, mth in ipairs(methods) do
local l = mth:lower()
if l:find("scan", 1, true) and not l:find("cost", 1, true) and not l:find("cooldown", 1, true) then fname = mth break end
end
end
local what = "side " .. side .. " = " .. tostring(peripheral.getType(side)) .. ": " .. table.concat(methods, ",")
if not fname then return nil, "the Geo Scanner has no scan function (" .. what .. ")" end
local e
for _ = 1, 10 do
local okS, a, b = pcall(peripheral.call, side, fname, radius)
if okS and type(a) == "table" then return a end
e = okS and b or a
sleep(1)
end
return nil, "scan failed: " .. tostring(e) .. " (" .. what .. ")"
end


KNOWN, KBOX, TARGETS_AT = nil, nil, {}
function kkey(x, y, z) return x .. "," .. y .. "," .. z end
function learnScan(res)
local r = CONFIG.scanR
KNOWN = {}
KBOX = { x1 = S.pos.x - r, x2 = S.pos.x + r, y1 = S.pos.y - r, y2 = S.pos.y + r, z1 = S.pos.z - r, z2 = S.pos.z + r }
for _, b in ipairs(res) do KNOWN[kkey(S.pos.x + b.x, S.pos.y + b.y, S.pos.z + b.z)] = b.name end
end
function scanLayer(cx, cz)
local res, err = geoScan(CONFIG.scanR)
if not res then return nil, err end
learnScan(res)
local x0, z0 = cx * 16, cz * 16
local out, wantN = {}, {}
for _, b in ipairs(res) do
local ax, ay, az = S.pos.x + b.x, S.pos.y + b.y, S.pos.z + b.z
if ax >= x0 and ax <= x0 + 15 and az >= z0 and az <= z0 + 15 and not isProtected(b.name) then
if isOreBlock(b) then
out[#out + 1] = { x = ax, y = ay, z = az }
elseif match(b.name, CONFIG.want) and (wantN[b.name] or 0) < CONFIG.wantMax then
wantN[b.name] = (wantN[b.name] or 0) + 1
out[#out + 1] = { x = ax, y = ay, z = az }
end
end
end
return orderTour(out)
end




function isOreBlock(b)
local n = tostring(b.name or "")
if match(n, CONFIG.skipOres or {}) then return false end
if match(n, CONFIG.ores) or match(n, CONFIG.extraOres or {}) then return true end
local short = n:match(":(.+)$") or n
if short:match("_ore$") or short:match("^ore_") or short:find("_ore_", 1, true) or short == "ore" then
return not short:find("_block", 1, true)
end
if type(b.tags) == "table" then
for k, v in pairs(b.tags) do
local tg = (type(k) == "string" and k) or tostring(v)
if (tg:find(":ores", 1, true) or tg:find("_ores", 1, true) or tg:find("/ores", 1, true))
and not tg:find("ores_in_ground", 1, true) then
return true
end
end
end
return false
end

function orderTour(list)
if #list < 3 then return list end
local function d(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z) end
local left, tour, cur = {}, {}, { x = S.pos.x, y = S.pos.y, z = S.pos.z }
for i, t in ipairs(list) do left[i] = t end
while #left > 0 do
local bi, bd = 1, nil
for i, t in ipairs(left) do
local dd = d(cur, t)
if not bd or dd < bd then bi, bd = i, dd end
end
cur = table.remove(left, bi)
tour[#tour + 1] = cur
end
local start = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
for _ = 1, 8 do
local better = false
for i = 1, #tour - 2 do
local a = (i == 1) and start or tour[i - 1]
local b = tour[i]
for j = i + 1, #tour - 1 do
local c, e = tour[j], tour[j + 1]
if d(a, c) + d(b, e) < d(a, b) + d(c, e) then

local lo, hi = i, j
while lo < hi do tour[lo], tour[hi] = tour[hi], tour[lo] lo, hi = lo + 1, hi - 1 end
better = true
b = tour[i]
end
end
end
if not better then break end
end
return tour
end

function cellCost(x, y, z)
if not KBOX or x < KBOX.x1 or x > KBOX.x2 or y < KBOX.y1 or y > KBOX.y2 or z < KBOX.z1 or z > KBOX.z2 then
return 2.5
end
local n = KNOWN[kkey(x, y, z)]
if not n then return 1 end
if isProtected(n) then return nil end
if n:find("lava", 1, true) then return 8 end
if isLiquid(n) then return 1.5 end
if TARGETS_AT[kkey(x, y, z)] then return 1.2 end
return 2.5
end

local D6 = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 0, -1, 0 } }
function planTo(t, cx, cz)
local x0, z0 = cx * 16, cz * 16
local y1, y2 = math.max(-63, math.min(S.pos.y, t.y) - 4), math.max(S.pos.y, t.y) + 4
local function h(x, y, z) return math.max(0, math.abs(x - t.x) + math.abs(y - t.y) + math.abs(z - t.z) - 1) end
local g, par, X, Y, Z, HD, closed = {}, {}, {}, {}, {}, {}, {}
local hf, hk, hn = {}, {}, 0
local function push(f, k)
hn = hn + 1
local i = hn
while i > 1 do
local p = math.floor(i / 2)
if hf[p] <= f then break end
hf[i], hk[i] = hf[p], hk[p]
i = p
end
hf[i], hk[i] = f, k
end
local function pop()
local k = hk[1]
local lf, lk = hf[hn], hk[hn]
hf[hn], hk[hn] = nil, nil
hn = hn - 1
if hn > 0 then
local i = 1
while true do
local c = i * 2
if c > hn then break end
if c < hn and hf[c + 1] < hf[c] then c = c + 1 end
if hf[c] >= lf then break end
hf[i], hk[i] = hf[c], hk[c]
i = c
end
hf[i], hk[i] = lf, lk
end
return k
end
local sk = kkey(S.pos.x, S.pos.y, S.pos.z)
g[sk], X[sk], Y[sk], Z[sk], par[sk], HD[sk] = 0, S.pos.x, S.pos.y, S.pos.z, false, S.pos.f
push(h(S.pos.x, S.pos.y, S.pos.z), sk)
local n = 0
while hn > 0 do
local k = pop()
if not closed[k] then
closed[k] = true
local x, y, z = X[k], Y[k], Z[k]
if math.abs(x - t.x) + math.abs(y - t.y) + math.abs(z - t.z) == 1 then
local path = {}
while par[k] do
table.insert(path, 1, { X[k], Y[k], Z[k] })
k = par[k]
end
return path
end
n = n + 1
if n > 6000 then return nil end
for _, d in ipairs(D6) do
local nx, ny, nz = x + d[1], y + d[2], z + d[3]
if nx >= x0 and nx <= x0 + 15 and nz >= z0 and nz <= z0 + 15 and ny >= y1 and ny <= y2
and not (nx == t.x and ny == t.y and nz == t.z) then
local c = cellCost(nx, ny, nz)
if c then
local nk = kkey(nx, ny, nz)
if not closed[nk] then
local f = (d[2] == 0) and ((d[1] == 1 and 1) or (d[1] == -1 and 3) or (d[3] == 1 and 2) or 0) or nil
if f and HD[k] and f ~= HD[k] then c = c + ((f - HD[k]) % 2 == 0 and 0.8 or 0.4) end
local ng = g[k] + c
if not g[nk] or ng < g[nk] then
g[nk], X[nk], Y[nk], Z[nk], par[nk] = ng, nx, ny, nz, k
HD[nk] = f or HD[k]
push(ng + h(nx, ny, nz) * 1.001, nk)
end
end
end
end
end
end
end
return nil
end

function walkPath(path)
for _, c in ipairs(path) do
local d
if c[2] > S.pos.y then d = "u" elseif c[2] < S.pos.y then d = "d"
else
turnTo((c[1] > S.pos.x and 1) or (c[1] < S.pos.x and 3) or (c[3] > S.pos.z and 2) or 0)
d = "f"
end
DIG_TARGET = TARGETS_AT[kkey(c[1], c[2], c[3])] and true or false
local ok, err = step(d)
DIG_TARGET = false
if not ok then return false, err end
local key = kkey(S.pos.x, S.pos.y, S.pos.z)
if KNOWN then KNOWN[key] = nil end

if TARGETS_AT[key] and P_NOW then
TARGETS_AT[key] = nil
S.stats.ores = S.stats.ores + 1
for i = #P_NOW.targets, 1, -1 do
local t = P_NOW.targets[i]
if t.x == S.pos.x and t.y == S.pos.y and t.z == S.pos.z then table.remove(P_NOW.targets, i) end
end
end
end
return true
end


function mineAround(P)
local n = 0
local p = S.pos
local order = { { 0, 1, 0, "u" }, { 0, -1, 0, "d" } }
for k = 0, 3 do
local f = (p.f + k) % 4
order[#order + 1] = { DX[f], 0, DZ[f], "f", f }
end
for _, o in ipairs(order) do
local x, y, z = p.x + o[1], p.y + o[2], p.z + o[3]
local key = kkey(x, y, z)
if TARGETS_AT[key] then
if o[5] then turnTo(o[5]) end
DIG_TARGET = true
local ok = digDir(o[4])
DIG_TARGET = false
TARGETS_AT[key] = nil
for i = #P.targets, 1, -1 do
local t = P.targets[i]
if t.x == x and t.y == y and t.z == z then table.remove(P.targets, i) end
end
if ok then
n = n + 1
S.stats.ores = S.stats.ores + 1
if KNOWN then KNOWN[key] = nil end
end
keepInventory()
end
end
if n > 0 then save() end
return n
end
function nearest(list)
local bi, bd
for i, t in ipairs(list) do
local d = math.abs(t.x - S.pos.x) + math.abs(t.y - S.pos.y) + math.abs(t.z - S.pos.z)
if not bd or d < bd then bi, bd = i, d end
end
return bi
end
















SHAFTS = { { 4, 4 }, { 11, 11 }, { 4, 11 }, { 11, 4 }, { 2, 8 }, { 13, 8 } }
function dirTo(tp, i)
local cx, cz = chunkAt(tp, i)
local nx, nz = chunkAt(tp, i + 1)
return (nx > cx and 1) or (nx < cx and 3) or (nz > cz and 2) or 0
end

function chunkCols(tp, i)
local x, z = tp.x0, tp.z0
for k = 0, i do
local cx, cz = chunkAt(tp, k)
local d = dirTo(tp, k)
local ex, ez = x, z
if d == 1 then ex = cx * 16 + 15 elseif d == 3 then ex = cx * 16 end
if d == 2 then ez = cz * 16 + 15 elseif d == 0 then ez = cz * 16 end


if ex == x and ez == z then
if d == 1 or d == 3 then ez = (z < cz * 16 + 15) and z + 1 or z - 1
else ex = (x < cx * 16 + 15) and x + 1 or x - 1 end
end
if k == i then return x, z, ex, ez, d end
x, z = ex + DX[d], ez + DZ[d]
end
end




function isTransit(tp, ci) return tp.transit and ci < tp.transit or false end
function tunY(tp, ci) return isTransit(tp, ci) and tp.fy or tp.yt end

function chunkDist(cx, cz, st)
local dx = math.max(cx * 16 - st.x, 0, st.x - (cx * 16 + 15))
local dz = math.max(cz * 16 - st.z, 0, st.z - (cz * 16 + 15))
return math.sqrt(dx * dx + dz * dz)
end



function planTransit(P)
local near, top = {}, P.yt + 1
for _, id in ipairs(S.team or {}) do
local st = S.stations and S.stations[id]
if st and chunkDist(P.sx, P.sz, st) < CONFIG.noDig + 1 then
near[#near + 1] = st
if st.y > top then top = st.y end
end
end
if #near == 0 then return end
local fx, fz = DX[P.f], DZ[P.f]
local n = 1
while n < 8 do
local cx, cz = P.sx + fx * n, P.sz + fz * n

local edge = math.min(fx * cx * 16 + fz * cz * 16, fx * (cx * 16 + 15) + fz * (cz * 16 + 15))
local clear = true
for _, st in ipairs(near) do
if edge - (fx * st.x + fz * st.z) < CONFIG.noDig + 1 then clear = false end
end
if clear then break end
n = n + 1
end
P.transit = n

P.fy = math.min(300, top + 4 + #S.team)
end
function myIndex()
for k, id in ipairs(S.team or {}) do if id == MYTID then return k, #S.team end end
return 1, math.max(1, #(S.team or {}))
end
function myLayers(tp)
local L = layers(tp.yt)
local k, n = myIndex()
local out = {}
for i = k, #L, n do out[#out + 1] = L[i] end
return out
end

function goVH(x, y, z)
local ok, err = goTo(S.pos.x, y, S.pos.z)
if not ok then return false, err end
return goTo(x, y, z)
end

function goHV(x, y, z)
local ok, err = goTo(x, S.pos.y, z)
if not ok then return false, err end
return goTo(x, y, z)
end

function tunnel2(x, z)
local ok, err = goTo(x, S.pos.y, S.pos.z)
if ok then ok, err = goTo(x, S.pos.y, z) end
return ok, err
end
TUNNEL2 = false


function newJob(tp, ci)
local k = myIndex()
local cx, cz = chunkAt(tp, ci)
local mx, mz = center(cx, cz)
local mine = ci > 0 and not isTransit(tp, ci) and not (S.station and nearStation(mx, mz, CONFIG.noMine))
S.job = { ci = ci, phase = (k == 1) and "tunnel" or (mine and "layers" or "lane"), li = 1, mine = mine,
plan = tp.id, late = (S.lateFor == tp.id) or nil }
S.lateFor = nil
save()
end



function crossingDue()
local J, tp = S.job, S.tp
return J and tp and J.phase == "ready" and J.plan == tp.id and (tp.goSent == J.ci or GO == J.ci) or false
end
function teamStep()
local okC, errC = true, nil
if not crossingDue() then okC, errC = checkpoint() end
if not okC then return false, errC end
local tp, J = S.tp, S.job
if not J or J.plan ~= tp.id then newJob(tp, tp.ci) J = S.job end
local ci = J.ci
local k, n = myIndex()
local cx, cz = chunkAt(tp, ci)
local mx, mz = center(cx, cz)
local x1, z1, ex, ez, dir = chunkCols(tp, ci)
local sx, sz = cx * 16 + SHAFTS[(k - 1) % #SHAFTS + 1][1], cz * 16 + SHAFTS[(k - 1) % #SHAFTS + 1][2]
local ty = tunY(tp, ci)
local lane = ty - (k - 1)


if k == 1 and not J.tunnelDone and J.phase ~= "tunnel" and not crossingDue() then
J.phase = "tunnel"
save()
end

CHUNK_LOCK = (J.phase ~= "ready") and { cx, cz } or nil


local outside = math.floor(S.pos.x / 16) ~= cx or math.floor(S.pos.z / 16) ~= cz
if (ci == 0 or J.late) and outside then CHUNK_LOCK = nil end
if J.late and not outside then J.late = nil save() end
if J.phase == "tunnel" then

setTask(isTransit(tp, ci) and ("moving away from the unload station (chunk " .. ci .. ")")
or ("main tunnel through chunk " .. ci))
local ok, err = goVH(x1, ty, z1)
if not ok then return false, err end
TUNNEL2 = true
ok, err = tunnel2(ex, ez)
TUNNEL2 = false
if not ok then return false, err end
J.phase = J.mine and "layers" or "lane"
J.tunnelDone = true
save()
return true
elseif J.phase == "layers" then

local L = layers(tp.yt)
if not J.cur then
LAYER = nil
local t0, sent = os.clock(), -100
while not LAYER or LAYER.ci ~= ci do
if not S.running then return false, "paused" end
if os.clock() - t0 > 120 then return false, "the loader does not hand out layers" end
if os.clock() - sent > 4 then
equipTool("modem")
sendTeam(S.leader, "needlayer", { ci = ci, done = J.lastDone })
sent = os.clock()
end
setTask("asking the loader for a layer")
listen(0.5)
end
if not LAYER.li then J.phase = "lane" save() return true end
J.cur, J.li = LAYER.li, LAYER.li
save()
end
local ly = L[J.cur]
if not J.targets then
setTask("my shaft to layer " .. J.cur .. "/" .. #L .. " (Y " .. ly .. ")")
local ok, err = goHV(sx, ly, sz)
if not ok then return false, err end
ok, err = goTo(mx, ly, mz)
if not ok then return false, err end
setTask("scanning layer " .. J.cur .. "/" .. #L)
local list, e2 = scanLayer(cx, cz)
if not list then return false, e2 end
J.targets = list
save()
end
if not KNOWN and #J.targets > 0 then
local res = geoScan(CONFIG.scanR)
if res then learnScan(res) end
end
TARGETS_AT, P_NOW = {}, J
for _, t in ipairs(J.targets) do TARGETS_AT[kkey(t.x, t.y, t.z)] = true end
mineAround(J)
while #J.targets > 0 do
local okC2, errC2 = checkpoint()
if not okC2 then return false, errC2 end
local t = J.targets[1]
setTask("chunk " .. ci .. " layer " .. J.cur .. "/" .. #L .. ": " .. #J.targets .. " ores left")
local path = KNOWN and planTo(t, cx, cz)
local ok
if path then ok = walkPath(path)
else ok = goTo(t.x, t.y, t.z) if ok then S.stats.ores = S.stats.ores + 1 end end
mineAround(J)
if J.targets[1] == t then
table.remove(J.targets, 1)
TARGETS_AT[kkey(t.x, t.y, t.z)] = nil
end
save()
end

local ok, err = goTo(mx, ly, mz)
if not ok then return false, err end
ok, err = goTo(sx, ly, sz)
if not ok then return false, err end
J.lastDone, J.cur, J.targets = J.cur, nil, nil
save()
return true
elseif J.phase == "lane" then

setTask(isTransit(tp, ci) and ("moving away from the unload station (chunk " .. ci .. ")")
or ("to my lane at the edge of chunk " .. ci))
local ok, err
if S.pos.y ~= lane then
if J.mine or (math.floor(S.pos.x / 16) == cx and math.floor(S.pos.z / 16) == cz and k > 1 and ci > 0) then
ok, err = goHV(sx, lane, sz)
else
ok, err = goVH(S.pos.x, lane, S.pos.z)
end
if not ok then return false, err end
end
ok, err = goTo(ex, lane, ez)
if not ok then return false, err end
turnTo(dir)
for _ = 1, 12 do
ok, err = digDir("f")
if not ok or not turtle.detect() then break end
sleep(0.4)
end
if not ok then return false, err end
if k == 1 then

ok, err = step("u")
if not ok then return false, err end
ok, err = digDir("f")
local okD, eD = step("d")
if not ok then return false, err end
if not okD then return false, eD end
turnTo(dir)
end
J.phase = "ready"
save()
return true
elseif J.phase == "ready" then

local t0, sent = os.clock(), -1000
while GO ~= ci do
if not S.running and not crossingDue() then return false, "paused" end


if myIndex() ~= k and not crossingDue() then return true end
if os.clock() - sent > 10 then
equipTool("modem")
sendTeam(S.leader, "ready", { ci = ci })
sent = os.clock()
end
setTask("ready at my lane - waiting for the others (" .. math.floor(os.clock() - t0) .. " s)")
if os.clock() - LAST_STATUS > 15 then sendBase("status") end
listen(1)
end
turnTo(dir)
for _ = 1, 8 do
if not turtle.detect() then break end
digDir("f")
end


equipTool("modem")
newJob(tp, ci + 1)
CHUNK_LOCK = nil
LAST_CHECK = os.clock()
local ok, err = step("f")
if not ok then
S.job = J
save()
return false, "could not step into the next chunk: " .. tostring(err)
end
pcall(sendTeam, S.leader, "stepped", { ci = ci })
return true
end
J.phase = "lane"
return true
end


function teamMsg(t, extra)
for _, id in ipairs(S.team or {}) do sendTeam(id, t, extra) end
end
function sendPlan()
teamMsg("team", { team = S.team, plan = S.plan })
end
function newTeamPlan()
if #(S.team or {}) == 0 then return false, "no miners in the team yet" end
table.sort(S.team)
gpsCheck()
local f = gpsFacing()
if f then S.pos.f = f end
local p = S.pos
S.dropped = nil
S.plan = { id = os.epoch("utc"), sx = math.floor(p.x / 16), sz = math.floor(p.z / 16), f = p.f,
yt = p.y - 1, x0 = p.x, z0 = p.z, ci = 0, phase = "work", ready = {}, running = true }
planTransit(S.plan)
fillLayers(S.plan)
save()
note("New field: " .. #S.team .. " miner(s), facing " .. FNAME[p.f] .. ", tunnel at Y " .. (p.y - 1))
if S.plan.transit then
note("Too close to the unload station here: the team first moves " .. S.plan.transit ..
" chunk(s) on through the air (Y " .. S.plan.fy .. "), then mines")
end
return true
end


function fillLayers(P)
P.queue, P.assigned = {}, {}
local cx, cz = chunkAt(P, P.ci)
local mx, mz = center(cx, cz)
if P.ci == 0 or isTransit(P, P.ci) or (S.station and nearStation(mx, mz, CONFIG.noMine)) then return end
for i = #layers(P.yt), 1, -1 do P.queue[#P.queue + 1] = i end
end

function leaderStep()
local P = S.plan


if not P or (not S.running and P.goSent ~= P.ci) then return end
if P.phase == "work" and S.running then
local missing = 0
for _, id in ipairs(S.team) do
if P.ready[id] ~= P.ci and not (S.lost and S.lost[id]) then missing = missing + 1 end


local silent = S.seen and S.seen[id] and now() - S.seen[id]

if silent and silent > (CONFIG.autoDrop or 3600) and P.ready[id] ~= P.ci and #S.team > 1 then
note("Miner " .. id .. " has been silent for " .. math.floor(silent / 60) ..
" min - taking it out of the team so the others go on (it can join a NEW FIELD again)")
doCmd("drop", { id })
S.running, P.running, S.pausedFor = true, true, nil
save()
sendPlan()
return
end
if P.ready[id] ~= P.ci and silent and silent > 1200 and S.running then
S.pausedFor = id
S.running, P.running = false, false
S.err = "miner " .. id .. " is silent for 20 min - team paused (is it stuck? its chunk unloaded?)"
note(S.err)
save()
sendPlan()
return
end
end
setTask("chunk " .. P.ci .. ": " .. (#S.team - missing) .. "/" .. #S.team .. " miners ready")
if missing == 0 and #S.team > 0 then P.phase = "cross" save() end
elseif P.phase == "cross" then
local x1, z1, ex, ez, dir = chunkCols(P, P.ci)
setTask("crossing to chunk " .. (P.ci + 1))

if P.checked ~= P.ci then
gpsCheck()
local f = gpsFacing()
if f and f ~= S.pos.f then note("Facing corrected by GPS: " .. FNAME[S.pos.f] .. " -> " .. FNAME[f]) end
if f then S.pos.f = f end
gpsCheck()
P.checked = P.ci
save()
end
local hy = tunY(P, P.ci) + 1
local ok, err = true, nil
if S.pos.y > hy then ok, err = goTo(S.pos.x, hy, S.pos.z) end
if ok then ok, err = goTo(ex, hy, ez) end
if ok then
gpsCheck()
if S.pos.x ~= ex or S.pos.y ~= hy or S.pos.z ~= ez then return end
end
if not ok then setTask("STUCK at the chunk edge: " .. tostring(err)) note("Loader: " .. tostring(err)) sleep(5) return end

STEPPED = {}
local t0, sent = os.clock(), -1000
while os.clock() - t0 < 15 do
local all = true
for _, id in ipairs(S.team) do
if not STEPPED[id] and P.ready[id] == P.ci then all = false end
end
if all then break end
if os.clock() - sent > 3 then
if P.goSent ~= P.ci then P.goSent = P.ci save() end
teamMsg("go", { ci = P.ci })
sent = os.clock()
end
listen(0.5)
end
turnTo(dir)
ok, err = step("f")
if not ok then setTask("STUCK crossing: " .. tostring(err)) note("Loader: " .. tostring(err)) sleep(5) return end
for _, id in ipairs(S.team) do
if P.ready[id] == P.ci and not STEPPED[id] then note("Miner " .. id .. " did not answer the crossing - maybe left behind") end
end
P.ci, P.phase, P.ready, P.goSent = P.ci + 1, "work", {}, nil
fillLayers(P)
save()

if NEWFIELD_LATER then
NEWFIELD_LATER = nil
S.plan, S.running = nil, false
teamMsg("team", { team = S.team, plan = false })
note("New field: it starts here on the next START")
return
end
sendPlan()
end
end
function equipCore()
if coreSide() then return true end
local slot = findSlot(function(n) return match(n, { "*automata*" }) end)
if not slot then return false, "no End Automata Core (equipped or in the inventory)" end
turtle.select(slot)

local first = peripheral.hasType("left", "modem") and "right" or "left"
local ok = (first == "left") and turtle.equipLeft() or turtle.equipRight()
turtle.select(1)
for _ = 1, 10 do if coreSide() then break end sleep(0.1) end
if not coreSide() then return false, "could not equip the End Automata Core" end
return true
end
function minerRun()
local okE, errE = equipCore()
if equipTool("modem") then
gpsCheck()

if S.running and S.job then
local f = checkFacing()
if f and f ~= S.pos.f then note("Facing corrected by GPS after the restart: " .. FNAME[S.pos.f] .. " -> " .. FNAME[f]) end
if f then S.pos.f = f end
gpsCheck()
end
end
if okE then
note("End Automata Core equipped on the " .. coreSide() .. " side")
else
note("! " .. tostring(errE) .. " - the miner needs one (it stays on)")
end


if S.station and coreSide() and hasPoint(core(), "station") == false then
S.station = nil
save()
note("The unload station was lost from the End Automata Core (picked up?). Put the miner on the station, " ..
"type  miner station, then carry it back and type  miner here")
end

if S.dumping then
local where = (S.dumping == "at") and "station" or whereAmI()
if where == "station" then
S.pos.x, S.pos.y, S.pos.z = S.station.x, S.station.y, S.station.z
S.dumping = "at"
local ok, err = finishDump()
if not ok then note("Unload trip: " .. tostring(err) .. " - it keeps trying by itself") end
else
S.dumping = nil
end
save()
end
if S.running then
note("Restarted - continuing in 6 s")
sleep(6)
end
local lastHello = -1000
while true do

if not S.leader and os.clock() - lastHello > 5 then
lastHello = os.clock()
equipTool("modem")
minerHere(nil)
end
if (not S.running and not crossingDue()) or not S.leader or not S.tp then
equipTool("modem")
if UPD_READY and not S.dumping then installMinerUpdate() end
if not S.leader then setTask("waiting for a loader turtle (same dimension)")
elseif S.err then setTask("PAUSED: " .. S.err)
else setTask(S.tp and "paused" or "in the team - press START on the base") end
if os.clock() - LAST_STATUS > 10 then sendBase("status") end
listen(3)
else

if not S.job or S.job.plan ~= S.tp.id then
gpsCheck()
local f = checkFacing()
if f then S.pos.f = f end
gpsCheck()
rememberOwn()
local used = 0
for i = 1, 16 do
local d = turtle.getItemDetail(i)
if d and S.own[d.name] and not isTool(d.name) and not isCoal(d.name) then used = used + 1 end
end
if used > 4 then
S.running, S.err = false, used .. " slots hold your own items - the miner needs the room. Take them out, then START"
note(S.err)
end
S.lastDump = now()
end
burnCoal()
if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 100 then
S.running, S.err = false, "NO FUEL - give it fuel (an endless fuel item or coal)"
note(S.err)
save()
end
local okR, ok, err = true, false, "paused"
if S.dumping == "at" and S.running then
okR, ok, err = pcall(finishDump)
elseif S.running or crossingDue() then okR, ok, err = pcall(teamStep) end
if not okR then
if tostring(ok):find("Terminated", 1, true) then error("Terminated", 0) end
ok, err = false, "error: " .. tostring(ok)
end
if not ok and tostring(err):find("next try", 1, true) and (RETRIES or 0) < 5 then
RETRIES = (RETRIES or 0) + 1
note(tostring(err))
elseif not ok and err ~= "paused" and (FAILS or 0) < 8 and S.running then


FAILS = (FAILS or 0) + 1
local waitS = math.min(600, 30 * 2 ^ (FAILS - 1))
note("Problem: " .. tostring(err) .. " - trying again by itself in " .. waitS .. " s (" .. FAILS .. "/8)")
equipTool("modem")
sendBase("status")
local t0 = os.clock()
while os.clock() - t0 < waitS and S.running do
setTask("problem: " .. tostring(err) .. " - again in " .. math.floor(waitS - (os.clock() - t0)) .. " s")
if os.clock() - LAST_STATUS > 15 then sendBase("status") end
listen(2)
end
gpsCheck()
local f = checkFacing()
if f then S.pos.f = f end
gpsCheck()
save()
elseif not ok then
if err ~= "paused" then
S.running, S.err = false, tostring(err) .. ((FAILS or 0) >= 8 and " (gave up after 8 tries)" or "")
note("STOPPED: " .. S.err)
FAILS = 0
end
save()
equipTool("modem")
sendBase("status")
else
RETRIES, FAILS = 0, 0
end
end
end
end
function loaderRun()


if S.stationUse then S.stationUse = nil save() end
if type(S.seen) == "table" then
for id, t in pairs(S.seen) do if type(t) ~= "number" or t < 1e9 then S.seen[id] = now() end end
end
local side = modemSide()
if side then pcall(rednet.open, side) else note("No modem on the loader!") end
gpsCheck()
local lastGps, lastHello, lastPlan = os.clock(), -1000, -1000
while true do

if os.clock() - lastHello > 10 then
lastHello = os.clock()
sendTeam(nil, "loaderhere")
end

if os.clock() - lastPlan > 30 then lastPlan = os.clock() sendPlan() end
if UPD_READY and not (S.plan and (S.running or S.plan.goSent == S.plan.ci or S.plan.phase == "cross")) then
installMinerUpdate()
end
if S.plan and (S.running or S.plan.goSent == S.plan.ci) then
local okR, err = pcall(leaderStep)
if not okR then
if tostring(err):find("Terminated", 1, true) then error("Terminated", 0) end
note("Loader error: " .. tostring(err))
sleep(2)
end
elseif S.plan and S.pausedFor then


local id = S.pausedFor
local silent = S.seen and S.seen[id] and now() - S.seen[id] or 0
setTask("paused: miner " .. id .. " silent " .. math.floor(silent / 60) .. " min - goes on when it is back")
if silent > (CONFIG.autoDrop or 3600) and #(S.team or {}) > 1 then
note("Miner " .. id .. " has been silent for " .. math.floor(silent / 60) ..
" min - taking it out of the team so the others go on (it can join a NEW FIELD again)")
doCmd("drop", { id })
S.pausedFor, S.err = nil, nil
S.running, S.plan.running = true, true
save()
sendPlan()
end
else
setTask(#(S.team or {}) == 0 and "waiting for miners (same dimension)"
or (#S.team .. " miner(s) in the team - press START on the base"))
end
if os.clock() - lastGps > 30 and not (S.plan and S.plan.phase == "cross") then lastGps = os.clock() gpsCheck() end
if os.clock() - LAST_STATUS > 10 then sendBase("status") end
listen(2)
end
end


function ask(q, default)
write(q .. (default and (" [" .. default .. "]") or "") .. ": ")
local a = read()
if a == "" and default then return default end
return a
end
function askPos()
if S.role == "miner" then equipTool("modem") end
local gx, gy, gz = gpsHere(2)
if gx then
print("GPS says: " .. gx .. " " .. gy .. " " .. gz .. "  (Enter = use it)")
else
print("Position of THIS turtle (look at it, F3 'Targeted Block').")
end
while true do
local a = ask("x y z", gx and (gx .. " " .. gy .. " " .. gz) or (S.pos and (S.pos.x .. " " .. S.pos.y .. " " .. S.pos.z)) or nil)
local x, y, z = tostring(a):match("^%s*(-?%d+)[%s,]+(-?%d+)[%s,]+(-?%d+)%s*$")
if x then
local f
while not f do
local s = ask("Which way does its FRONT face? (n/e/s/w)", S.pos and FNAME[S.pos.f]:sub(1, 1) or nil)
f = ({ n = 0, e = 1, s = 2, w = 3 })[tostring(s):sub(1, 1):lower()]
end
S.pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z), f = f }
save()
return
end
print("Three numbers, like: 120 64 -35")
end
end
function setup()
term.clear()
term.setCursorPos(1, 1)
print("MINING TEAM setup")
local r = ""
while r ~= "m" and r ~= "l" do r = tostring(ask("Is this the MINER or the LOADER? (m/l)", S.role and S.role:sub(1, 1) or nil)):sub(1, 1):lower() end
S.role = (r == "m") and "miner" or "loader"
S.key = ask("Turtle key (CONFIG.turtles.key in base_config.lua)", S.key)
local d = ""
while d ~= "o" and d ~= "n" and d ~= "e" do
d = tostring(ask("Which mining dimension? (o = overworld, n = nether, e = end)", S.dim and S.dim:sub(1, 1) or "o")):sub(1, 1):lower()
end
S.dim = ({ o = "overworld", n = "nether", e = "end" })[d]
askPos()
if not os.getComputerLabel() then os.setComputerLabel((S.role == "miner" and "Miner " or "Loader ") .. os.getComputerID()) end
if S.role == "miner" then
local okE, errE = equipCore()
if okE then print("End Automata Core: equipped (" .. coreSide() .. " side)")
else print("! " .. tostring(errE)) end
for _, k in ipairs({ "pickaxe", "modem", "geo" }) do
if toolNow() ~= k and not findSlot(function(n) return match(n, { TOOL_ITEM[k] }) end) then
print("! Missing: " .. k)
end
end
if not findSlot(function(n) return n:find("shulker", 1, true) ~= nil end) then print("! Missing: a shulker box") end
local st = tostring(ask("Is it standing on the UNLOAD STATION now, facing its front? (y/n)", "n")):lower()
if st:sub(1, 1) == "y" then stationHere() end
else
if not modemSide() then print("! No modem equipped - the loader needs an Ender Modem") end
if not peripheral.getType("left") and not peripheral.getType("right") then print("! Equip the Chunky upgrade") end
end
save()
print("Done. It starts by itself from now on.")
if S.role == "miner" then print("Press START on the base (TURTLES > MINING).") end
sleep(2)
end


loadState()
local args = { ... }
if not fs.exists("startup.lua") then
local h = fs.open("startup.lua", "w")
h.write('shell.run("' .. (shell and shell.getRunningProgram() or "miner.lua") .. '")\n')
h.close()
end
if args[1] == "setup" or not S.role or not S.pos then setup() end
if args[1] == "here" then
askPos()

S.plan, S.job, S.trail, S.follow, S.running = nil, nil, nil, nil, false
save()
print("Old mining plan cleared - press START on the base when both turtles are placed.")
if S.role == "miner" and S.station then
local c = core()
if c and hasPoint(c, "station") == false then
print("! The unload station is NOT in the core any more (lost when it was picked up).")
elseif c then
print("Unload station still known: " .. S.station.x .. " " .. S.station.y .. " " .. S.station.z)
end
end
end
if args[1] == "station" then
if S.role == "miner" then stationHere() else print("Only the miner has a station.") end
return
end
term.clear()
term.setCursorPos(1, 1)
print(string.upper(S.role) .. " (miner.lua " .. MYVER .. ") - " .. S.dim .. " - " .. fmtPos())
if S.err then print("Last stop: " .. tostring(S.err) .. "  (START on the base clears it)") end
print("Ctrl+T stops it.  'miner setup' asks everything again.")
local okRun, err = pcall(function()
if S.role == "miner" then minerRun() else loaderRun() end
end)
if not okRun and tostring(err) ~= "Terminated" then
local h = fs.open("miner_crash", "w")
if h then h.write(tostring(err)) h.close() end
printError("miner.lua stopped: " .. tostring(err))
S.err = "crashed: " .. tostring(err)
save()
print("Restarting in 5 s ...")
sleep(5)
os.reboot()
end
