-- base_workers.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   The background workers (all slow game calls happen here) and the screen
--   loop. inventory.lua runs these together: uiLoop, invWorker, pageWorker,
--   actionWorker, droneWorker, terminalWorker, chatWorker, commsWorker.

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
      local ok, err = pcall(runAction, a)
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
      pcall(MAP.autoSave)                -- changed map regions, at most once a minute
      local okF, errF = pcall(MAP.feedSurvey)  -- a big survey: next batch to each idle turtle
      if not okF and (not state.feedErrAt or os.clock() - state.feedErrAt > 60) then
        state.feedErrAt = os.clock()
        setToast("Big survey error: " .. tostring(errF), C.bad)
      end
      pcall(TT.updateTick)               -- turtle program updates, one turtle at a time
      pcall(TT.stopTick)                 -- STOP again until the turtle answers
      pcall(TT.patrolTick)               -- the rescue turtle: send it where it is needed
      pcall(TT.homeTick)                 -- homes for new turtles; idle turtles go home
      pcall(MAP.autoTick)                -- auto-map: a survey always running (from the base outward)
      if TT.listDirty and codeTick % 15 == 0 then pcall(TT.saveList) end
      codeTick = codeTick + 1
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
      local wake = handleTouch(b, c)
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

