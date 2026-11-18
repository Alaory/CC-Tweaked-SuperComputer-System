-- base_remote.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   REMOTE ACCESS (REMOTE): the base's console in your web browser, also while you are
--   NOT in the game (the base stays loaded by the anchor turtle). It uses Cloud Catcher
--   (cloud-catcher.squiddev.cc, free, by the author of CC:Tweaked): its program cloud.lua
--   mirrors one terminal to a web page and sends your typing back.
--   - The base runs it in its OWN TAB (multishell, an Advanced Computer): cloud.lua stops
--     when its connection drops, and everything running inside it with it - so the base is
--     never inside it. In that tab runs remote.lua, a small console: what you type there is
--     sent to the base as an event ("remote_cmd"), the base runs it like a command typed on
--     this computer (handleCommand) and sends the answer back ("remote_out").
--   - remote.lua says "remote_alive" every 5 s; no word for 30 s (the connection dropped,
--     the server restarted) -> the base starts the tab again (60 s apart, longer after
--     failures). Started / stopped with `remote on|off` (console) or `$drone remote` (chat).
--   - The LINK holds a secret token (32 letters / digits, made here, kept in settings.dat):
--     whoever has it can type commands into the base. `remote new` makes a new one.
--   - cloud.lua is downloaded once (checked: it must compile), onto a data floppy first.

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
-- the code in groups of 4 (easier to read off the screen and type)
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

-- a new secret token: 32 letters / digits (like the web page makes them)
function REMOTE.newToken()
  -- (no look-alikes: the code is read off the computer's screen and typed - 0 O Q o, 1 I l i j, 5 S s,
  --  2 Z z, 8 B, u v V U, c C k K p P w W x X are left out: the screen font made the owner misread it)
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

-- is it running? (remote.lua said so within 30 s)
function REMOTE.running()
  return os.clock() - REMOTE.alive < 30
end

-- what can stop it here (nil = nothing)
function REMOTE.blocker()
  if not (http and http.websocket) then
    return "this computer cannot reach the internet - the server has HTTP / websockets switched off"
  end
  if not (multishell and shell and shell.openTab) then
    return "it needs an ADVANCED Computer (it runs in a second tab)"
  end
  return nil
end

-- cloud.lua: downloaded once (a data floppy first); must compile
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

-- start it now (the tab); returns true or false, why
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

-- mapWorker, every ~5 s: keep it running while it is switched on
function REMOTE.tick()
  if not REMOTE.cfg("on", false) then REMOTE.why = nil return end
  if REMOTE.running() then REMOTE.why, REMOTE.fails = nil, 0 return end
  -- started and never heard of = a failed start (counted once); give it time, then try
  -- again - longer after each failure (60 s, 2, 4, 8 .. 10 min)
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

-- a command typed in the browser: run like one typed on this computer
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

-- switch on (a link is made the first time) / off / new link
function REMOTE.setOn(on)
  if on and not REMOTE.token() then setSetting("remote.token", REMOTE.newToken()) end
  setSetting("remote.on", on and true or false)
  if on then
    REMOTE.startedAt, REMOTE.fails = -1000, 0
  else
    os.queueEvent("remote_quit")                  -- remote.lua ends -> cloud.lua ends -> the tab closes
    REMOTE.alive = -1000
  end
end
-- use the code the web page made (the owner cannot click links in game: open
-- cloud-catcher.squiddev.cc in the browser, copy the code it shows, paste it in chat)
function REMOTE.useToken(tok)
  tok = tostring(tok or ""):gsub("^%s+", ""):gsub("%s+$", "")
  tok = tok:match("id=(%w+)") or tok                -- (the whole link pasted: the code from it)
  if not REMOTE.validToken(tok) then return false end
  if tok ~= REMOTE.token() then os.queueEvent("remote_quit") end   -- a tab with the old code quits
  setSetting("remote.token", tok)
  setSetting("remote.on", true)
  REMOTE.alive, REMOTE.startedAt, REMOTE.fails = -1000, -1000, 0
  return true
end
function REMOTE.renew()
  setSetting("remote.token", REMOTE.newToken())
  os.queueEvent("remote_quit")                    -- the old link stops working; started again with the new one
  REMOTE.alive, REMOTE.startedAt, REMOTE.fails = -1000, -1000, 0
end

-- the link to the owner in chat (privately; clickable where the Chat Box can)
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

-- the event side (its own worker: a command may wait for peripherals)
function remoteWorker()
  while state.running do
    local ev = { os.pullEventRaw() }
    if ev[1] == "remote_alive" then
      REMOTE.alive, REMOTE.fails, REMOTE.why = os.clock(), 0, nil
    elseif ev[1] == "remote_cmd" then
      REMOTE.alive = os.clock()
      pcall(REMOTE.run, ev[2], ev[3])
    end
  end
end

-- text lines for the console / chat
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
