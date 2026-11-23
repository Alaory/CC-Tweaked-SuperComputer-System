











local PROTO = "basespawn"
local VER = 4
local KEYFILE = "spawn_key.dat"


local function sign(key, t, n, cmd, args)
local parts = {}
for i, v in ipairs(args or {}) do parts[i] = tostring(v) end
local str = key .. "|" .. tostring(t) .. "|" .. tostring(n) .. "|" .. tostring(cmd or "") .. "|" .. table.concat(parts, ",")
local h1, h2 = 5381, 52711
for i = 1, #str do
local c = str:byte(i)
h1 = (h1 * 33 + c) % 4294967296
h2 = (h2 * 131 + c * 7 + i) % 4294967296
end
return string.format("%08x%08x", h1, h2)
end

local function dataHash(d)
local h1, h2 = 7, 13
for i = 1, #d, 16 do
local b = { d:byte(i, i + 15) }
for j = 1, #b do
h1 = (h1 * 31 + b[j]) % 4294967296
h2 = (h2 + b[j] * (i + j)) % 4294967296
end
end
return string.format("%x%x%d", h1, h2, #d)
end
local function unscramble(text, code, id)
local ks, i = {}, 0
while #ks < #text do
i = i + 1
local h = sign(tostring(code), "ks", tostring(id) .. ":" .. i)
for k = 1, #h, 2 do ks[#ks + 1] = tonumber(h:sub(k, k + 1), 16) end
end
local o = {}
for j = 1, #text do o[j] = string.char((text:byte(j) - ks[j]) % 256) end
return table.concat(o)
end

local S = { lastN = 0, queue = {}, played = 0, heard = 0 }
local function load()
local h = fs.open(KEYFILE, "r")
if not h then h = fs.open(KEYFILE .. ".tmp", "r") end
if not h then return end
local t = textutils.unserialize(h.readAll() or "")
h.close()
if type(t) == "table" and type(t.key) == "string" and tonumber(t.base) then S.key, S.base = t.key, tonumber(t.base) end
end
local function save()
local text = textutils.serialize({ key = S.key, base = S.base })
local h = fs.open(KEYFILE .. ".tmp", "w")
if not h then return end
h.write(text)
h.close()
if fs.getSize(KEYFILE .. ".tmp") == #text then
if fs.exists(KEYFILE) then fs.delete(KEYFILE) end
fs.move(KEYFILE .. ".tmp", KEYFILE)
end
end
local function newCode() S.code = string.format("%06d", math.random(0, 999999)) end


local INFOFILE = "spawn_info.txt"
local function loadInfo()
local h = fs.open(INFOFILE, "r")
if h then S.info = h.readAll() h.close() end
end
local function saveInfo()
local h = fs.open(INFOFILE, "w")
if h then h.write(S.info or "") h.close() end
end
local function drawSign()
if not S.info or S.info == "" then return end
local lines = {}
for l in (S.info .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
for _, n in ipairs(peripheral.getNames()) do
if peripheral.hasType(n, "monitor") then
local mon = peripheral.wrap(n)
pcall(function()
mon.setTextScale(1)
local w, h = mon.getSize()
if w < 24 then mon.setTextScale(0.5) w, h = mon.getSize() end
mon.setBackgroundColor(colors.black)
mon.clear()
local y0 = math.max(1, math.floor((h - #lines) / 2) + 1)
for i, l in ipairs(lines) do
local col = (i == 1 and colors.yellow) or (l:find("wish", 1, true) and colors.lime) or (i == 2 and colors.lightGray) or colors.white
mon.setTextColor(col)
mon.setCursorPos(math.max(1, math.floor((w - #l) / 2) + 1), y0 + i - 1)
mon.write(l)
end
end)
end
end
end

local function speakers()
local out = {}
for _, n in ipairs(peripheral.getNames()) do
if peripheral.hasType(n, "speaker") then out[#out + 1] = peripheral.wrap(n) end
end
return out
end
local function openModems()
local n = 0
for _, side in ipairs(peripheral.getNames()) do
if peripheral.hasType(side, "modem") then
local okW, w = pcall(peripheral.call, side, "isWireless")
if okW and w then
if not rednet.isOpen(side) then pcall(rednet.open, side) end
n = n + 1
end
end
end
return n
end

local lastSent = 0
local function nextN()
local n = os.epoch("utc")
if n <= lastSent then n = lastSent + 1 end
lastSent = n
return n
end
local function sendBase(t, fields)
local m = fields or {}
m.t, m.n, m.ver = t, nextN(), VER
m.sp = #speakers()
m.q = #S.queue
m.inf = S.info and dataHash(S.info) or ""
if S.key then
m.sig = sign(S.key, t, m.n, "", { m.sp, m.q })
pcall(rednet.send, S.base, m, PROTO)
else
pcall(rednet.broadcast, m, PROTO)
end
end

local function draw()
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("SPAWN SPEAKER (v" .. VER .. ")  #" .. os.getComputerID())
term.setTextColor(colors.white)
local m = openModems()
local sp = #speakers()
print("Ender / wireless modems: " .. m .. (m == 0 and "  <- PUT ONE ON" or ""))
print("Speakers: " .. sp .. (sp == 0 and "  <- PUT ONE NEXT TO IT" or ""))
print("")
if S.key and S.info and S.info ~= "" then
term.setTextColor(colors.yellow)
for l in (S.info .. "\n"):gmatch("([^\n]*)\n") do print(l) end
term.setTextColor(colors.white)
print("")
end
if S.key then
term.setTextColor(colors.lime)
print("Paired with the base #" .. S.base)
term.setTextColor(colors.white)
print("Pieces played: " .. S.played .. "  waiting: " .. #S.queue)
if S.lastAt then print("Last sound: " .. math.floor((os.epoch("utc") - S.lastAt) / 1000) .. " s ago") end
else
term.setTextColor(colors.orange)
print("NOT PAIRED. Stand here and type in chat:")
term.setTextColor(colors.white)
print("")
print("  $drone spawn here")
print("  $drone spawn pair " .. S.code)
print("")
print("(or on the base console: voice spawn pair " .. S.code .. ")")
end
if S.note then print("") term.setTextColor(colors.lightGray) print(S.note) end
end

local function stopAll()
S.cutN = (S.cutN or 0) + 1
S.queue = {}
for _, s in ipairs(speakers()) do pcall(s.stop) end
os.queueEvent("spawn_cut")
end

local function receive(id, m)
if type(m) ~= "table" or type(m.t) ~= "string" then return end
if m.t == "pair" then
if S.key and id ~= S.base then return end
if not S.code or m.proof ~= sign(S.code, "pair", os.getComputerID()) then return end
if type(m.k) ~= "string" then return end
S.key, S.base, S.lastN = unscramble(m.k, S.code, os.getComputerID()), id, 0
save()
S.note = "Paired."
sendBase("paired")
draw()
return
end
if not S.key or id ~= S.base then return end
if type(m.n) ~= "number" or m.n <= S.lastN then return end
if m.n < os.epoch("utc") - 60000 then return end
local d = type(m.d) == "string" and m.d or ""
if m.sig ~= sign(S.key, m.t, m.n, tostring(m.line or ""), { dataHash(d), tostring(m.v or "") }) then return end
S.lastN = m.n
S.heard = os.epoch("utc")
if m.t == "play" then
if #S.queue < 40 then S.queue[#S.queue + 1] = { d = d, v = tonumber(m.v) or 2, fresh = m.fresh } end
os.queueEvent("spawn_play")
elseif m.t == "cut" then
stopAll()
elseif m.t == "info" then
S.info = d
saveInfo()
draw()
drawSign()
elseif m.t == "ping" then
sendBase("pong")
elseif m.t == "upd" then


local i, n, ver = tostring(m.line or ""):match("^(%d+)/(%d+)/(%w+)$")
i, n = tonumber(i), tonumber(n)
if not (i and n and n <= 40 and i >= 1 and i <= n) then return end
if not S.upd or S.upd.ver ~= ver or S.upd.n ~= n then S.upd = { ver = ver, n = n, parts = {}, got = 0 } end
if not S.upd.parts[i] then S.upd.parts[i], S.upd.got = d, S.upd.got + 1 end
if S.upd.got < n then return end
local code = table.concat(S.upd.parts)
S.upd = nil
if dataHash(code) ~= ver then sendBase("updres", { e = "arrived damaged" }) return end
if not _G.load(code, "=spawn_speaker", "t", {}) then sendBase("updres", { e = "does not compile" }) return end
local prog = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "startup.lua"
local h = fs.open("startup.new", "w")
local okW = h and pcall(h.write, code)
if h then pcall(h.close) end
if not (okW and fs.exists("startup.new") and fs.getSize("startup.new") >= #code) then
pcall(fs.delete, "startup.new")
sendBase("updres", { e = "the disk is full" })
return
end
if fs.exists(prog .. ".old") then fs.delete(prog .. ".old") end
if fs.exists(prog) then fs.move(prog, prog .. ".old") end
fs.move("startup.new", prog)
sendBase("updres", { ok = true })
S.note = "Updated - restarting"
draw()
sleep(0.5)
os.reboot()
elseif m.t == "unpair" then
S.key, S.base = nil, nil
fs.delete(KEYFILE)
newCode()
S.note = "Unpaired by the base."
draw()
end
end

local function listener()
while true do
local id, m = rednet.receive(PROTO, 10)
if id then pcall(receive, id, m) end
end
end
local function hello()
while true do
openModems()
sendBase("hello")
draw()
drawSign()
sleep(S.key and 20 or 8)
end
end
local function playOne(dfpwm, dec, it)
if it.fresh then dec = dfpwm.make_decoder() end
local pcm = dec(it.d)
local sps = speakers()
local myCut = S.cutN or 0
local function cut() return (S.cutN or 0) ~= myCut end
for i = 1, #pcm, 16 * 1024 do
if cut() then break end
local buf = {}
for j = i, math.min(#pcm, i + 16 * 1024 - 1) do buf[#buf + 1] = pcm[j] end
for _, s in ipairs(sps) do
local tries = 0
while not cut() and not s.playAudio(buf, it.v) do
tries = tries + 1
if tries > 40 then break end
local t = os.startTimer(0.5)
repeat local ev, a = os.pullEvent()
until cut() or ev == "spawn_cut" or ev == "speaker_audio_empty" or (ev == "timer" and a == t)
end
end
end
return dec
end
local function player()
local okD, dfpwm = pcall(require, "cc.audio.dfpwm")
if not okD then S.note = "This CC:Tweaked has no cc.audio.dfpwm - too old." while true do sleep(60) end end
local dec = dfpwm.make_decoder()
while true do
if #S.queue == 0 then os.pullEvent("spawn_play") end
local it = table.remove(S.queue, 1)
if it then

local ok, d2 = pcall(playOne, dfpwm, dec, it)
if ok then dec = d2 else S.note = "Sound error: " .. tostring(d2) dec = dfpwm.make_decoder() end
S.played, S.lastAt = S.played + 1, os.epoch("utc")
end
end
end

math.randomseed(os.epoch("utc") + os.getComputerID())
load()
loadInfo()
if not S.key then newCode() end
if os.setComputerLabel and not os.getComputerLabel() then pcall(os.setComputerLabel, "Spawn speaker") end
draw()

while true do
local ok, err = pcall(parallel.waitForAny, listener, function() while true do pcall(hello) sleep(5) end end, player)
if not ok and tostring(err):find("Terminated", 1, true) then break end
S.note = "Restarted after: " .. tostring(err)
sleep(2)
end
