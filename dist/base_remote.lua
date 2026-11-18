


















REMOTE = { alive = -1000, startedAt = -1000, fails = 0, why = nil, tab = nil, said = nil }
REMOTE.SITE = "https://cloud-catcher.squiddev.cc"

function REMOTE.cfg(k, default)
local r = CONFIG.remote
local v
if type(r) == "table" then v = r[k] end
if v == nil then return default end
return v
end

function REMOTE.validToken(t)
return type(t) == "string" and #t == 32 and not t:find("[^%a%d]")
end
function REMOTE.token()
local t = REMOTE.cfg("token")
if REMOTE.validToken(t) then return t end
return nil
end

function REMOTE.groups()
local t = REMOTE.token() or ""
local g = {}
for i = 1, #t, 4 do g[#g + 1] = t:sub(i, i + 3) end
return table.concat(g, " ")
end
function REMOTE.link()
local t = REMOTE.token()
return t and (REMOTE.SITE .. "/?id=" .. t) or nil
end


function REMOTE.newToken()


local cs = "34679ADEFGHJLMNRTYabdefghmnqrty"
local x = (os.epoch("utc") + os.getComputerID() * 7919 + math.floor(os.clock() * 1000)) % 2147483647
local out = {}
for i = 1, 32 do
x = (x * 16807 + math.random(0, 1048575) + i) % 2147483647
local k = x % #cs + 1
out[i] = cs:sub(k, k)
end
return table.concat(out)
end


function REMOTE.running()
return os.clock() - REMOTE.alive < 30
end


function REMOTE.blocker()
if not (http and http.websocket) then
return "this computer cannot reach the internet - the server has HTTP / websockets switched off"
end
if not (multishell and shell and shell.openTab) then
return "it needs an ADVANCED Computer (it runs in a second tab)"
end
return nil
end


function REMOTE.client()
local p = dataPath("cloud.lua")
if fs.exists(p) and fs.getSize(p) > 1000 then return p end
if fs.exists("cloud.lua") and fs.getSize("cloud.lua") > 1000 then return "cloud.lua" end
local okG, h = pcall(http.get, REMOTE.SITE .. "/cloud.lua")
if not okG or not h then return nil, "could not download cloud.lua from " .. REMOTE.SITE end
local text = h.readAll() or ""
h.close()
if #text < 1000 or not load(text, "cloud.lua", "t", {}) then return nil, "cloud.lua from the web did not compile" end
local dir = fs.getDir(p)
local okF, free = pcall(fs.getFreeSpace, dir == "" and "/" or dir)
if okF and type(free) == "number" and free < #text + 16 * 1024 then
return nil, "no room for cloud.lua (" .. math.ceil(#text / 1024) .. " KB) - put a data floppy in (`disks data`)"
end
if not saveFileSafe(p, text) then return nil, "could not save cloud.lua" end
return p
end


function REMOTE.start()
local tok = REMOTE.token()
if not tok then return false, "no link yet - type: remote on" end
local b = REMOTE.blocker()
if b then return false, b end
if http.checkURL then
local okC, good, err = pcall(http.checkURL, REMOTE.SITE)
if okC and good == false then return false, "the server does not allow " .. REMOTE.SITE .. ": " .. tostring(err) end
end
local rpath = fs.combine(BASE_DIR or "", "remote.lua")
if not fs.exists(rpath) then return false, "remote.lua is missing next to inventory.lua (run upgrade)" end
local path, err = REMOTE.client()
if not path then return false, err end
REMOTE.startedAt, REMOTE.counted = os.clock(), nil
local okT, id = pcall(shell.openTab, "/" .. path, tok, "--", "/" .. rpath)
if not okT or not id then return false, "could not open a tab: " .. tostring(id) end
REMOTE.tab = id
pcall(multishell.setTitle, id, "remote")
return true
end


function REMOTE.tick()
if not REMOTE.cfg("on", false) then REMOTE.why = nil return end
if REMOTE.running() then REMOTE.why, REMOTE.fails = nil, 0 return end


if REMOTE.startedAt > 0 and REMOTE.alive < REMOTE.startedAt and not REMOTE.counted
and os.clock() - REMOTE.startedAt >= 60 then
REMOTE.fails, REMOTE.counted = REMOTE.fails + 1, true
end
local wait = math.min(600, 60 * (2 ^ math.min(REMOTE.fails, 4)))
if os.clock() - REMOTE.startedAt < wait then return end
local ok, why = REMOTE.start()
if ok then
REMOTE.why = "starting (connecting to " .. REMOTE.SITE .. ")"
if REMOTE.fails >= 2 then
REMOTE.why = "could not connect " .. REMOTE.fails .. " times - is the internet allowed on this server? " ..
"Test on this computer: wget https://example.com test.txt"
end
else
REMOTE.why = why
REMOTE.startedAt, REMOTE.counted = os.clock(), true
REMOTE.fails = REMOTE.fails + 1
end
if REMOTE.why ~= REMOTE.said and REMOTE.fails >= 1 then
REMOTE.said = REMOTE.why
if sysLog then sysLog("Remote access: " .. tostring(REMOTE.why), "WARNING") end
end
end


function REMOTE.run(req, line)
line = tostring(line or "")
local out
if line:match("^%s*drive%s") then
out = { "DRIVE needs the keys of this computer - use: turtle <id> goto x y z / home / stop" }
else
HAND_CMD = true
local ok, res = pcall(handleCommand, line)
HAND_CMD = false
out = ok and res or { "Error: " .. tostring(res) }
end
if sysLog and line ~= "" then sysLog("Remote command: " .. line, "INFO") end
os.queueEvent("remote_out", req, out)
os.queueEvent("inv_update")
end


function REMOTE.setOn(on)
if on and not REMOTE.token() then setSetting("remote.token", REMOTE.newToken()) end
setSetting("remote.on", on and true or false)
if on then
REMOTE.startedAt, REMOTE.fails = -1000, 0
else
os.queueEvent("remote_quit")
REMOTE.alive = -1000
end
end


function REMOTE.useToken(tok)
tok = tostring(tok or ""):gsub("^%s+", ""):gsub("%s+$", "")
tok = tok:match("id=(%w+)") or tok
if not REMOTE.validToken(tok) then return false end
if tok ~= REMOTE.token() then os.queueEvent("remote_quit") end
setSetting("remote.token", tok)
setSetting("remote.on", true)
REMOTE.alive, REMOTE.startedAt, REMOTE.fails = -1000, -1000, 0
return true
end
function REMOTE.renew()
setSetting("remote.token", REMOTE.newToken())
os.queueEvent("remote_quit")
REMOTE.alive, REMOTE.startedAt, REMOTE.fails = -1000, -1000, 0
end


function REMOTE.tellLink(name)
local link = REMOTE.link()
if not (link and name) then return end
state.chatOut[#state.chatOut + 1] = { name = name, text = "Your base in the browser (keep it secret): " .. link,
json = textutils.serializeJSON({ { text = "Your base in the browser: " }, { text = "OPEN",
color = "aqua", underlined = true, clickEvent = { action = "open_url", value = link } },
{ text = "  " }, { text = "COPY", color = "aqua", underlined = true,
clickEvent = { action = "copy_to_clipboard", value = link } },
{ text = "  (keep the link secret - it lets you type commands into the base)", color = "gray" } }) }
os.queueEvent("chat_send")
end


function remoteWorker()
while state.running do
local ev = { os.pullEventRaw() }
if ev[1] == "remote_alive" then
REMOTE.alive, REMOTE.fails, REMOTE.why = os.clock(), 0, nil
elseif ev[1] == "pocket_local" then
REMOTE.alive = os.clock()
pcall(POCKET.receiveLocal, ev[2])
elseif ev[1] == "remote_cmd" then
REMOTE.alive = os.clock()
pcall(REMOTE.run, ev[2], ev[3])
end
end
end


function REMOTE.lines()
local L = {}
local on = REMOTE.cfg("on", false)
L[#L + 1] = "Remote access (the console in your web browser): " .. (on and "ON" or "OFF") ..
(on and (REMOTE.running() and " - connected" or "") or "")
if REMOTE.why then L[#L + 1] = "  " .. REMOTE.why end
local b = REMOTE.blocker()
if b then L[#L + 1] = "  Cannot run here: " .. b end
if on and REMOTE.link() then
L[#L + 1] = "  Link (keep it SECRET - it lets anyone type commands here):"
L[#L + 1] = "  " .. REMOTE.link()
L[#L + 1] = "  Code in groups (type them without the spaces): " .. REMOTE.groups()
end
L[#L + 1] = "  remote on | off | new (a new link, the old one stops) | link (sent to you in chat)"
L[#L + 1] = "  remote <code>: use the code the web page shows (open " .. REMOTE.SITE .. ")"
return L
end
