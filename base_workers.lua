-- base_workers.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   The background workers (all slow game calls happen here) and the screen
--   loop. inventory.lua runs these together: uiLoop, invWorker, pageWorker,
--   actionWorker, droneWorker, terminalWorker, chatWorker, commsWorker.

-- ===== the SYSTEM log =====
-- Only system things (the base was off / crashed, new turtle program, map
-- floppies, auto-map ...), so they are not pushed out of the EVENTS list by
-- everyday messages. system.log on the computer (16 KB, then system.old.log);
-- the SYSTEM tab shows the newest 100.
local SYS_FILE, SYS_OLD = "system.log", "system.old.log"
SYSLOG = {}
do
  for _, f in ipairs({ SYS_OLD, SYS_FILE }) do
    if fs.exists(f) then
      local h = fs.open(f, "r")
      while h do
        local l = h.readLine()
        if not l then break end
        local d, kind, msg = l:match("^(.-)|(%u+)|(.*)$")
        if d then table.insert(SYSLOG, 1, { when = d, kind = kind, msg = msg }) end
      end
      if h then h.close() end
    end
  end
  while #SYSLOG > 100 do table.remove(SYSLOG) end
end
-- add a line to the system log (kind: "ERROR", "WARNING", "DONE", "INFO")
function sysLog(msg, kind)
  kind = kind or "INFO"
  local okD, d = pcall(os.date, "%d.%m %H:%M")
  d = okD and d or "?"
  msg = tostring(msg):gsub("[\r\n|]", " ")
  table.insert(SYSLOG, 1, { when = d, kind = kind, msg = msg })
  while #SYSLOG > 100 do table.remove(SYSLOG) end
  pcall(function()
    local okF, free = pcall(fs.getFreeSpace, "/")
    if okF and type(free) == "number" and free < 8192 then return end
    if fs.exists(SYS_FILE) and fs.getSize(SYS_FILE) > 16384 then
      if fs.exists(SYS_OLD) then fs.delete(SYS_OLD) end
      fs.move(SYS_FILE, SYS_OLD)
    end
    local h = fs.open(SYS_FILE, "a")
    if h then h.writeLine(d .. "|" .. kind .. "|" .. msg) h.close() end
  end)
end

-- ===== system status for the SYSTEM tab (worker; drawing only reads it) =====
function sysRefresh()
  local s = {}
  local okF, free = pcall(fs.getFreeSpace, "/")
  local okC, cap = pcall(fs.getCapacity, "/")
  s.pcFree, s.pcCap = okF and free or nil, okC and cap or nil
  local okM, mfree, mcount = pcall(MAP.floppySpace)
  s.mapFree, s.mapFloppies = okM and mfree or nil, okM and mcount or nil
  local okU, total, onPc, files = pcall(MAP.diskUse)
  s.mapBytes, s.mapOnPc, s.mapFiles = okU and total or nil, okU and onPc or nil, okU and files or nil
  local up, all = 0, 0
  for _, t in pairs(state.turtles) do
    all = all + 1
    if CODE and t.ver == CODE.ver then up = up + 1 end
  end
  s.turtlesUp, s.turtlesAll = up, all
  s.eventsLog = fs.exists("events.log") and fs.getSize("events.log") or 0
  if STORE then s.helperFree, s.helpers = STORE.space() end
  state.sys = s
end

-- ===== was the base computer off? =====
-- Every 30 s the real time is written to base_alive.dat. On the next start
-- the gap tells how long the computer was off, and why: after an error, you
-- stopped it, or (otherwise) its chunk was unloaded / the server restarted.
-- The last 10 times are kept ('uptime' on the computer).
local ALIVE_FILE = "base_alive.dat"
BASE_ALIVE = { starts = 0, offs = {} }
do
  if fs.exists(ALIVE_FILE) then
    local h = fs.open(ALIVE_FILE, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) == "table" then BASE_ALIVE = t end
  end
  BASE_ALIVE.offs = BASE_ALIVE.offs or {}
end
local function aliveSave() saveFileSafe(ALIVE_FILE, textutils.serialize(BASE_ALIVE)) end
function baseAliveTick()
  BASE_ALIVE.t = os.epoch("utc")
  aliveSave()
end
-- inventory.lua calls this when the program ends (error or Ctrl+T)
function baseExit(crashErr)
  BASE_ALIVE.t = os.epoch("utc")
  if crashErr then BASE_ALIVE.crash = tostring(crashErr) else BASE_ALIVE.stopped = true end
  pcall(aliveSave)
  if MINE and MINE.dirty then pcall(MINE.save) end
end
local function when(ms)
  local ok, r = pcall(os.date, "%d.%m %H:%M", math.floor(ms / 1000))
  return ok and r or "?"
end
function fmtSpan(sec)
  sec = math.floor(sec)
  if sec < 120 then return sec .. " s" end
  if sec < 7200 then return math.floor(sec / 60) .. " min" end
  return math.floor(sec / 3600) .. " h " .. math.floor(sec % 3600 / 60) .. " min"
end
-- on start: report the time the base was off (called once, before the workers run)
function baseStartCheck()
  local now = os.epoch("utc")
  local last = tonumber(BASE_ALIVE.t)
  if last then
    local gap = (now - last) / 1000
    local why = BASE_ALIVE.crash and ("after an ERROR: " .. BASE_ALIVE.crash)
                or BASE_ALIVE.stopped and "you stopped it"
                or "its chunk was unloaded or the server restarted (nothing kept it loaded)"
    if gap > 90 or BASE_ALIVE.crash then
      table.insert(BASE_ALIVE.offs, 1, { from = last, to = now, why = why })
      while #BASE_ALIVE.offs > 10 do table.remove(BASE_ALIVE.offs) end
      local msg = "Off from " .. when(last) .. " to " .. when(now) .. " (" .. fmtSpan(gap) .. ") - " .. why
      sysLog("Base was OFF " .. fmtSpan(gap) .. " (" .. when(last) .. " - " .. when(now) .. "): " .. why,
             BASE_ALIVE.crash and "ERROR" or (BASE_ALIVE.stopped and "INFO" or "WARNING"))
      if BASE_ALIVE.crash or not BASE_ALIVE.stopped then setPopup("BASE WAS OFF", msg, C.warn)
      else setToast("Base was off " .. fmtSpan(gap) .. " (you stopped it)", C.label) end
    end
  end
  BASE_ALIVE.crash, BASE_ALIVE.stopped = nil, nil
  BASE_ALIVE.starts = (BASE_ALIVE.starts or 0) + 1
  BASE_ALIVE.since = now
  BASE_ALIVE.t = now
  aliveSave()
end

---------------------------------------------------------------------
-- MAIN
---------------------------------------------------------------------
---------------------------------------------------------------------
-- BACKGROUND WORKERS  (all the slow game calls live here)
---------------------------------------------------------------------
function fresh(key, ttl)
  local t = state.t[key]
  return t ~= nil and (os.clock() - t) < ttl
end

-- ask the screen to redraw
function notify() os.queueEvent("inv_update") end

-- run fn; if it crashes, remember that the data was "read" so we do not spin
function safe(keys, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    for _, k in ipairs(keys) do state.t[k] = os.clock() end
    state.workerErr = tostring(err)
  end
  return ok, err
end

-- worker 1: owner + inventory (always)
function invWorker()
  while state.running do
    local ttl = state.page == "inventory" and CONFIG.refresh or CONFIG.refresh * 3
    if state.force.inv or not fresh("inv", ttl) then
      state.force.inv = false
      local ok, err = safe({ "inv" }, refreshInventory)
      if not ok then state.status, state.err = "offline", tostring(err) end
      notify()
    end
    waitFor(0.25, "inv_wake")
  end
end

-- worker 2: whatever the visible page needs (only the visible page)
function pageWorker()
  while state.running do
    local page = state.page
    local did = false

    if page == "players" and det then
      if state.force.players or not fresh("players", CONFIG.ttl.players) then
        state.force.players = false
        safe({ "players", "owner" }, refreshPlayers, true)
        did = true
      end

    elseif page == "inventory" and det and state.owner then
      if not fresh("owner", CONFIG.ttl.players) then
        safe({ "owner" }, refreshPlayers, false)
        did = true
      end

    elseif page == "storage" then
      if state.force.storage or not fresh("storage", CONFIG.ttl.storage) then
        state.force.storage = false
        local ok, err = safe({ "storage" }, refreshStorage)
        if not ok then state.storage, state.storageMsg = {}, tostring(err) end
        did = true
      end

    elseif page == "curios" then
      if state.force.curios or not fresh("curios", CONFIG.ttl.curios) then
        state.force.curios = false
        local ok, rows, msg, note = pcall(fetchCurios)
        if ok then
          state.curios, state.curiosMsg, state.curiosNote = rows, msg, note
        else
          state.curios, state.curiosMsg, state.curiosNote = nil, tostring(rows), nil
        end
        state.t.curios = os.clock()
        did = true
      end
      -- an empty slot is selected: the ME list shows what fits (read once a minute)
      local sel = state.curiosSel
      if bridge and sel and not sel.item and (state.meForce or not fresh("me", 60)) then
        state.meForce = false
        local ok, me = pcall(fetchME)
        if ok then state.me = me end
        state.t.me = os.clock()
        did = true
      end

    elseif page == "map" then
      if det and (state.force.players or not fresh("players", CONFIG.ttl.players)) then
        state.force.players = false
        safe({ "players", "owner" }, refreshPlayers, true)
        did = true
      end
      if #droneOrder > 0 and not fresh("drone", 2) then
        safe({ "drone" }, refreshDrones)
        did = true
      end

    elseif page == "access" then
      if det and (state.force.players or not fresh("players", CONFIG.ttl.players)) then
        state.force.players = false
        safe({ "players", "owner" }, refreshPlayers, true)
        did = true
      end

    elseif page == "drone" then
      if #droneOrder > 0 and (state.force.drone or not fresh("drone", 1)) then
        state.force.drone = false
        safe({ "drone" }, refreshDrones)
        did = true
      end
      if det and not fresh("players", CONFIG.ttl.players) then
        safe({ "players", "owner" }, refreshPlayers, true)
        did = true
      end

    elseif page == "me" and bridge then
      local ttl = (state.me and state.me.partial) and 10 or CONFIG.me.refresh
      if state.meForce or not fresh("me", ttl) then
        state.meForce = false
        local ok, me = pcall(fetchME)
        if ok then state.me = me
        else state.me = { err = tostring(me), items = {}, tasks = {}, byName = {} } end
        state.t.me = os.clock()
        did = true
      end
    end

    -- turtles avoid other players: their positions are needed on every page
    if det and next(state.turtles) and (tonumber(CONFIG.turtles.avoidRange or 100) or 0) > 0
       and not fresh("players", 10) then
      safe({ "players", "owner" }, refreshPlayers, true)
      did = true
    end

    -- where is this computer? (for the anchor check; needs the turtle modem
    -- and GPS; asked here, not in the comms worker, so no message is missed)
    if state.tModem and not state.basePosTried then
      state.basePosTried = true
      local ok, x, y, z = pcall(gps.locate, 2)
      if ok and x then
        state.basePos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
        did = true
      end
    end

    -- free disk space (checked every minute): warn before it runs out
    if os.clock() - (state.lastDisk or -100) > 60 then
      state.lastDisk = os.clock()
      local okF, free = pcall(fs.getFreeSpace, "/")
      if okF and type(free) == "number" then
        if free < 48 * 1024 then
          state.diskLow = "DISK ALMOST FULL: " .. math.floor(free / 1024) ..
                          " KB free - see base_config.lua (map.maxChunks, turtles.knowMax)"
        elseif state.diskLow and free > 96 * 1024 then
          state.diskLow = nil
        end
      end
    end

    if det and CONFIG.back and os.clock() - (state.lastTrack or -100) > CONFIG.back.every then
      state.lastTrack = os.clock()
      pcall(trackPlayers)
    end

    if OWED and #OWED > 0 and bridge and os.clock() - (state.lastOwed or -100) > 30 then
      state.lastOwed = os.clock()
      pcall(settleOwed)
    end

    if #droneOrder > 0 and os.clock() - (state.lastPark or -100) > 10 then
      state.lastPark = os.clock()
      pcall(parkCheck)
    end

    if did then notify() end
    waitFor(0.2, "inv_wake")
  end
end

-- worker 3: confirmed transfers / crafts (can take seconds, never blocks the screen)
function actionWorker()
  while state.running do
    local a = table.remove(state.actionQueue, 1)
    if a then
      USER_ACTION = true                -- a button you pressed: its result is always shown
      local ok, err = pcall(runAction, a)
      USER_ACTION = false
      if not ok then setToast("Error: " .. tostring(err), C.bad, 10) end
      state.busy = false
      state.force.inv = true          -- the inventory just changed
      os.queueEvent("inv_wake")
      notify()
    else
      waitFor(0.3, "inv_action")
    end
  end
end

-- worker 4: drone missions. Every drone runs its own mission at the same time
-- (each in its own coroutine), so one busy drone never holds up another.
function droneWorker()
  local running = {}   -- drone key -> { co = coroutine, filter = event name or nil }

  local function finish(k, ok, err)
    local r = running[k]
    running[k] = nil
    local dr = drones[k]
    if dr and dr.requester and r and r.cmd and r.cmd.kind ~= "stop" and r.cmd.kind ~= "release" then
      local m = dr.mission
      if ok and m and m.state == "done" then
        chatTell(dr.requester, "You have arrived. " .. dr.label .. " is flying back to base.")
      elseif m and m.state == "stopped" then
        chatTell(dr.requester, "Your ride was stopped.")
      else
        chatTell(dr.requester, "Your ride failed: " .. ((m and m.err) or cleanErr(err or "unknown")))
      end
      dr.requester = nil
    end
    if dr then
      if not ok then
        dr.mission = { title = "error", steps = {}, state = "failed", err = cleanErr(err) }
        droneLog(dr, "Error: " .. cleanErr(err))
      end
      dr.busy = false
    end
    os.queueEvent("inv_update")
    os.queueEvent("drone_cmd")       -- this drone may have more commands queued
  end

  local function startQueued()
    for _, k in ipairs(droneOrder) do
      local dr = drones[k]
      if dr and not running[k] and #dr.queue > 0 then
        local cmd = table.remove(dr.queue, 1)
        local co = coroutine.create(function() return pcall(runMission, dr, cmd) end)
        running[k] = { co = co, cmd = cmd }
        local okR, okM, errM = coroutine.resume(co)
        if not okR then finish(k, false, okM)
        elseif coroutine.status(co) == "dead" then finish(k, okM, errM)
        else running[k].filter = okM end
      end
    end
  end

  while state.running do
    startQueued()
    local ev = table.pack(os.pullEventRaw())
    for k, r in pairs(running) do
      if r.filter == nil or r.filter == ev[1] or ev[1] == "terminate" then
        local okR, a1, a2 = coroutine.resume(r.co, table.unpack(ev, 1, ev.n))
        if not okR then finish(k, false, a1)
        elseif coroutine.status(r.co) == "dead" then finish(k, a1, a2)
        else r.filter = a1 end
      end
    end
  end
end

-- worker 6: chat commands and private replies. The screen loop puts every
-- chat message into state.chatInbox (so none are lost while this worker is
-- busy talking to a peripheral); replies are paced (the Chat Box needs ~1 s).
-- worker 7: turtles. Opens the wireless/ender modem, receives their reports
-- and sends the queued commands (no game calls that could block the screen).
-- the map worker: saving the map (also onto storage helpers - those calls
-- wait for an answer, so they get a worker of their own: the turtles' messages
-- and the monitor never wait for them) and finding the storage helpers
function mapWorker()
  local lastFind = os.clock() - 280         -- first look for new helpers ~20 s after the start
  while state.running do
    waitFor(5, "map_save")
    if MAP.saveNow then
      MAP.saveNow = false
      local okS = pcall(MAP.save)
      pcall(MAP.checkSpace)
      setToast(okS and not next(MAP.dirty) and "Map saved" or "Map not fully saved (no room?)",
               okS and not next(MAP.dirty) and C.good or C.warn, 4)
    else
      pcall(MAP.autoSave)                -- changed map regions, at most once a minute
    end
    if os.clock() - lastFind > 300 then  -- storage helpers added / gone, and their updates
      lastFind = os.clock()
      pcall(STORE.find)
      pcall(STORE.updateAll)
    end
  end
end

function commsWorker()
  local opened
  local codeTick = 0
  local tick = os.startTimer(2)
  while state.running do
    if not opened then
      local m = TT.findModem()
      if m and pcall(rednet.open, m) then
        pcall(rednet.host, CONFIG.turtles.protocol, CONFIG.turtles.hostname)
        opened = m
        state.tModem = m
        os.queueEvent("inv_update")
      end
    elseif not peripheral.isPresent(opened) then
      opened, state.tModem = nil, nil
    end
    while opened and #state.tOut > 0 do
      local o = table.remove(state.tOut, 1)
      pcall(rednet.send, o.id, o.msg, CONFIG.turtles.protocol)
    end
    local ev, a, b, c = os.pullEventRaw()
    if ev == "rednet_message" and c == CONFIG.turtles.protocol then
      pcall(TT.receive, a, b)
    elseif ev == "disk" and a == TT.installDrive() then
      pcall(TT.codeLoad)
      pcall(TT.prepareInstallFloppy)                -- a floppy in the install drive
    elseif ev == "timer" and a == tick then
      tick = os.startTimer(2)
      if KNOW.dirty and os.clock() - KNOW.saved > 30 then pcall(KNOW.save) end
      local okF, errF = pcall(MAP.feedSurvey)  -- a big survey: next batch to each idle turtle
      if not okF and (not state.feedErrAt or os.clock() - state.feedErrAt > 60) then
        state.feedErrAt = os.clock()
        setToast("Big survey error: " .. tostring(errF), C.bad)
      end
      pcall(TT.updateTick)               -- turtle program updates, one turtle at a time
      pcall(TT.stopTick)                 -- STOP again until the turtle answers
      pcall(TT.patrolTick)               -- the rescue turtle: send it where it is needed
      pcall(TT.homeTick)                 -- homes for new turtles; idle turtles go home
      pcall(TT.avoidTick)                -- turtles keep away from other players
      pcall(TT.stallTick)                -- a turtle hung in its job is stopped
      pcall(MAP.autoTick)                -- auto-map: a survey always running (from the base outward)
      if TT.listDirty and codeTick % 15 == 0 then pcall(TT.saveList) end
      codeTick = codeTick + 1
      if codeTick % 15 == 7 then pcall(baseAliveTick) end    -- every 30 s: "still running"
      if codeTick % 5 == 3 then pcall(sysRefresh) end        -- SYSTEM tab numbers (every 10 s)
      if codeTick % 15 == 1 then pcall(TT.codeLoad) end     -- every 30 s
      os.queueEvent("inv_update")       -- online/offline can change with time
    end
  end
end

-- worker 4: handles chat commands and sends the private replies (1 per second)
function chatWorker()
  local lastSend = -10
  while state.running do
    local m = table.remove(state.chatInbox, 1)
    if m then
      local ok, err = pcall(handleChat, m)
      if not ok then setToast("Chat error: " .. cleanErr(err), C.bad, 6) end
    elseif #state.chatOut > 0 then
      if not chatBox then
        state.chatOut = {}
      elseif os.clock() - lastSend >= 1.05 then
        local o = table.remove(state.chatOut, 1)
        -- private reply. sendMessage(text, { player = ... }) is what this Chat
        -- Box understands (it worked from the start); sendMessageToPlayer only
        -- if that fails. A failure is shown once in EVENTS.
        local okS, errS = pcall(chatBox.sendMessage, o.text, { player = o.name, prefix = CONFIG.chat.replyPrefix })
        if not okS and chatBox.sendMessageToPlayer then
          okS = pcall(chatBox.sendMessageToPlayer, o.text, o.name, CONFIG.chat.replyPrefix)
        end
        if not okS and not state.chatSendWarned then
          state.chatSendWarned = true
          setToast("Chat Box could not send a message to " .. o.name .. ": " .. cleanErr(errS), C.bad)
        end
        lastSend = os.clock()
      else
        -- never wait less than 0.1 s (no busy loop on rounding)
        waitFor(math.max(0.1, 1.1 - (os.clock() - lastSend)), "chat_cmd")
      end
    else
      -- requests nobody answered: tell the player, then forget them
      for k, r in pairs(state.rideRequests) do
        if os.clock() > r.exp then
          state.rideRequests[k] = nil
          chatTell(r.name, "No answer from " .. tostring(state.owner) ..
                           " - your request expired. You can ask again.")
        end
      end
      waitFor(1, "chat_cmd", "chat_send")
    end
  end
end

-- worker 5: the computer's keyboard (type coordinates, save places, ...)
function terminalWorker()
  local okC, completion = pcall(require, "cc.completion")
  local history = {}
  local CMDS = { "help", "dest", "save", "del", "list", "players", "status",
                 "fly", "pickup", "drop", "ferry", "home", "stop", "release",
                 "charger", "allow", "deny", "allowed", "drones", "drone" }

  local function complete(txt)
    if not okC then return nil end
    local sp = txt:find("%s%S*$")
    if not sp then return completion.choice(txt, CMDS, true) end
    local choices = {}
    for _, w in ipairs(state.waypoints) do choices[#choices + 1] = w.name end
    for _, e in ipairs(state.players or {}) do
      choices[#choices + 1] = e.name
      choices[#choices + 1] = "@" .. e.name
    end
    return completion.choice(txt:sub(sp + 1), choices)
  end

  print("Drone console ready - type 'help'.")
  while state.running do
    write((state.drone and state.drone.label or "drone") .. "> ")
    local line = read(nil, history, complete)
    if line == nil then break end
    if line ~= "" then history[#history + 1] = line end
    local ok, out = pcall(handleCommand, line)
    if ok then
      for _, l in ipairs(out) do print(l) end
    else
      print("Error: " .. tostring(out))
    end
    os.queueEvent("inv_update")
  end
end

---------------------------------------------------------------------
-- SCREEN LOOP  (no game calls here: it only draws cached data)
---------------------------------------------------------------------
function uiLoop()
  local lastDraw, drawTimer = -1, nil

  local function drawNow()
    draw()
    lastDraw = os.clock()
  end

  -- draw soon, but never more than ~8 times a second
  local function requestDraw()
    if drawTimer then return end
    local wait = lastDraw + 0.12 - os.clock()
    if wait <= 0 then drawNow() else drawTimer = os.startTimer(wait) end
  end

  drawNow()
  local clockTimer = os.startTimer(1)

  while state.running do
    local ev, a, b, c, d = os.pullEventRaw()

    if ev == "monitor_touch" and a == monName then
      -- messages from what you just tapped are always shown (USER_ACTION, pushNote)
      USER_ACTION = true
      local okT, wake = pcall(handleTouch, b, c)
      USER_ACTION = false
      if not okT then error(wake, 0) end
      if wake then os.queueEvent("inv_wake") end
      drawNow()                         -- react to a touch immediately

    elseif ev == "inv_update" then
      requestDraw()

    elseif ev == "timer" then
      if a == drawTimer then
        drawTimer = nil
        drawNow()
      elseif a == clockTimer then       -- keeps the clock and messages fresh
        clockTimer = os.startTimer(1)
        requestDraw()
      end

    elseif ev == "monitor_resize" and a == monName then
      buildWindow()
      drawNow()

    elseif ev == "me_crafting" or ev == "rs_crafting" then
      setToast(string.format("Craft job #%s: %s", tostring(b), tostring(c)),
               a and C.bad or C.good, 8)
      state.meForce = true
      os.queueEvent("inv_wake")
      requestDraw()

    elseif ev == "peripheral" then
      rescanPeripherals()
      state.force.inv = true
      state.force.players = true
      state.meForce = true
      os.queueEvent("inv_wake")
      requestDraw()

    elseif ev == "peripheral_detach" then
      if type(a) == "string" then forgetDetached(a) end
      state.force.inv = true
      os.queueEvent("inv_wake")
      requestDraw()

    elseif ev == "chat" then
      -- uuid, name, message, isHidden: handled by the chat worker
      state.chatInbox[#state.chatInbox + 1] = { uuid = a, name = b, msg = c, hidden = d }
      os.queueEvent("chat_cmd")

    elseif ev == "playerChangedDimension" then
      rememberDim(a, c)

    elseif ev == "playerJoin" then
      rememberDim(a, b)

    elseif ev == "playerLeave" then
      forgetDim(a)

    elseif ev == "terminate" then
      state.running = false
    end
  end
end

