-- REMOTE ACCESS (base_remote.lua): the base's console in a web browser through Cloud Catcher,
-- run in its OWN tab (a dropped connection must never stop the base), started again when it
-- goes quiet, commands answered, link kept secret / renewed, blockers named.
local Q = {}
os.queueEvent = function(...) Q[#Q + 1] = { ... } end
local function queued(name)
  for _, e in ipairs(Q) do if e[1] == name then return e end end
end

-- 1. no internet on this server / not an advanced computer: it says so
http, multishell = nil, nil
CHECK((REMOTE.blocker() or ""):find("HTTP", 1, true), "no http: " .. tostring(REMOTE.blocker()))
http = { websocket = function() end, checkURL = function() return true end }
local gets = 0
local CLOUD = string.rep("-- cloud catcher stand-in\n", 60) .. "return 1\n"
http.get = function(url)
  gets = gets + 1
  CHECK(url == "https://cloud-catcher.squiddev.cc/cloud.lua", "downloads cloud.lua from the site (" .. url .. ")")
  return { readAll = function() return CLOUD end, close = function() end }
end
local realShell = shell
shell = { openTab = nil }
CHECK((REMOTE.blocker() or ""):find("ADVANCED", 1, true), "no tabs: " .. tostring(REMOTE.blocker()))

-- 2. switched on: a secret link is made, the tab opened with cloud.lua + remote.lua in it
local opened, titled = {}, nil
multishell = { setTitle = function(id, t) titled = t end }
shell = { openTab = function(...) opened[#opened + 1] = { ... } return 7 end }
REMOTE.setOn(true)
local tok = REMOTE.token()
CHECK(REMOTE.validToken(tok), "a token of 32 letters / digits: " .. tostring(tok))
local bad = 0
for _ = 1, 20 do if REMOTE.newToken():find("[0OQo1Iil5Ss2Zz8BuvVUcCkKpPwWxX]") then bad = bad + 1 end end
CHECK(bad == 0, "codes have no look-alike characters (0/O/Q, 1/I/l ...): " .. bad .. " of 20 had some")
CHECK(#REMOTE.groups() == 39 and REMOTE.groups():sub(5, 5) == " ", "shown in groups of 4: " .. REMOTE.groups())
CHECK(REMOTE.link() == "https://cloud-catcher.squiddev.cc/?id=" .. tok, "the link: " .. tostring(REMOTE.link()))
REMOTE.tick()
local o = opened[1]
CHECK(o and tostring(o[1]):find("cloud.lua$") and o[2] == tok and o[3] == "--" and tostring(o[4]):find("remote.lua$"),
      "a tab runs cloud.lua <token> -- remote.lua (" .. (o and table.concat(o, " ") or "none") .. ")")
CHECK(titled == "remote" and gets == 1, "tab named 'remote', cloud.lua downloaded once")
REMOTE.tick()
CHECK(#opened == 1, "not opened again while it connects")

-- 3. it talks: running; a command typed in the browser is answered
os.queueEvent("x") Q = {}
REMOTE.alive = os.clock()
CHECK(REMOTE.running(), "running while remote.lua says it is alive")
REMOTE.run("r1", "remote")
local ans = queued("remote_out")
CHECK(ans and ans[2] == "r1" and type(ans[3]) == "table" and table.concat(ans[3], "\n"):find(tok, 1, true),
      "the browser's command is run and the answer goes back to it")
Q = {}
REMOTE.run("r2", "drive 5")
ans = queued("remote_out")
CHECK(ans and table.concat(ans[3], " "):find("keys of this computer", 1, true), "DRIVE (keyboard steering) is refused politely")

-- 4. the connection dropped (remote.lua quiet): started again after a while, slower after failures
CLOCK = CLOCK + 40
CHECK(not REMOTE.running(), "quiet 40 s = not running")
CLOCK = CLOCK + 30
REMOTE.tick()
CHECK(#opened == 2, "started again (" .. #opened .. " tabs opened)")
CLOCK = CLOCK + 70
REMOTE.tick()
CHECK(#opened == 2, "after a failed start it waits longer before the next try (" .. #opened .. ")")
CLOCK = CLOCK + 200
REMOTE.tick()
CHECK(#opened == 3 and gets == 1, "then tries again; cloud.lua is not downloaded again (" .. #opened .. ", " .. gets .. ")")

-- 5. the server blocks the site: named
http.checkURL = function() return false, "Domain not permitted" end
CLOCK = CLOCK + 2000
REMOTE.tick()
CHECK(#opened == 3 and tostring(REMOTE.why):find("Domain not permitted", 1, true), "blocked site named: " .. tostring(REMOTE.why))
http.checkURL = function() return true end

-- 6. a new link (the old one stops working), the link sent privately as a clickable chat message
Q = {}
REMOTE.renew()
CHECK(REMOTE.token() ~= tok and REMOTE.validToken(REMOTE.token()) and queued("remote_quit"), "remote new: new token, the old tab quits")
state.chatOut = {}
REMOTE.tellLink("Alaory")
local m = state.chatOut[1]
CHECK(m and m.name == "Alaory" and m.text:find(REMOTE.link(), 1, true) and m.json and m.json:find("open_url", 1, true),
      "the link goes to the owner only, clickable")

-- 7. off: the tab is told to quit, nothing is started again
Q = {}
REMOTE.setOn(false)
CHECK(queued("remote_quit") and CONFIG.remote.on == false, "remote off: the tab quits")
local before = #opened
CLOCK = CLOCK + 5000
REMOTE.tick()
CHECK(#opened == before, "off stays off")

-- 8. console command
local out = handleCommand("remote")
CHECK(table.concat(out, "\n"):find("OFF", 1, true), "console `remote` shows the state")
out = handleCommand("remote on")
CHECK(CONFIG.remote.on == true and table.concat(out, "\n"):find(REMOTE.link(), 1, true), "console `remote on` shows the link")
REMOTE.setOn(false)

-- 9. links cannot be clicked in every game: the code the WEB PAGE shows is pasted on the computer or
--    in chat (the whole link works too); a wrong code is refused
local CODE = "Ab3dEfGh1jKlMn0pQrStUvWxYz123456"
CHECK(#CODE == 32, "test code is 32 long")
CHECK(not REMOTE.useToken("short123"), "a wrong code is refused")
Q = {}
out = handleCommand("remote " .. CODE)
CHECK(REMOTE.token() == CODE and CONFIG.remote.on == true and queued("remote_quit"),
      "console `remote <code>`: that code is used, kept as typed (upper / lower case), switched on")
CHECK(REMOTE.useToken("https://cloud-catcher.squiddev.cc/?id=" .. CODE:reverse()) and REMOTE.token() == CODE:reverse(),
      "the whole link pasted: the code is taken from it")
local said = {}
state.owner = state.owner or "Alaory"
local oldTell = chatTell
chatTell = function(n, t) said[#said + 1] = t end
local okHC, errHC = pcall(handleChat, { name = state.owner, msg = "$" .. CONFIG.chat.command .. " remote " .. CODE })
CHECK(okHC, "chat command runs: " .. tostring(errHC))
chatTell = oldTell
CHECK(REMOTE.token() == CODE, "chat `$drone remote <code>` uses the code (case kept): " .. tostring(REMOTE.token()))
REMOTE.setOn(false)
shell = realShell
