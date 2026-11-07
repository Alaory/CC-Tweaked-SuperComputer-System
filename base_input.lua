-- base_input.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   Monitor touches: tabs, buttons (two-tap confirm), selecting items /
--   players / drones / turtles / map spots, closing the popup.

---------------------------------------------------------------------
-- INPUT
---------------------------------------------------------------------
function handleTouch(tx, ty)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if tx >= h[1] and tx <= h[3] and ty >= h[2] and ty <= h[4] then
      if h[5] ~= "act" then state.pending = nil end
      if h[5] == "sort" then
        sortMode = sortMode == "count" and "name"
                or sortMode == "name" and "slot" or "count"
        sortList()
      elseif h[5] == "group" then
        -- a top tab: the page used last in that group
        local pg = openGroup(h[6])
        if pg then
          state.page = pg
          saveFileSafe("ui_page.dat", pg)
          if pg == "events" then state.noteUnread = 0 end
        end
      elseif h[5] == "page" then
        state.page = h[6]
        state.groupLast = state.groupLast or {}
        if groupOf(h[6]) then state.groupLast[groupOf(h[6])] = h[6] end
        saveFileSafe("ui_page.dat", h[6])                 -- opened again after a restart
        if h[6] == "events" then state.noteUnread = 0 end   -- seen
      elseif h[5] == "meitem" then
        state.meSel = (state.meSel ~= h[6]) and h[6] or nil
      elseif h[5] == "meletter" then
        state.meLetter = h[6] or nil
        state.meItemsPage = 1
      elseif h[5] == "mesort" then
        state.meSort = state.meSort == "count" and "name" or "count"
        state.meItemsPage = 1
      elseif h[5] == "mecraft" then
        state.meCraftOnly = not state.meCraftOnly
        state.meItemsPage = 1
        state.meForce = true
      elseif h[5] == "act" then
        local a = h[6]
        if state.pending and state.pending.key == a.key and os.clock() < state.pending.exp then
          state.pending = nil
          if a.kind == "drone" then
            local what = a.name:match("^(%a+)")
            local dr = state.drone
            if dr and a.pass and a.pass ~= "" then dr.passenger = a.pass end
            if submitDrone(dr, { kind = what, passenger = a.pass }) then
              setToast(dr.label .. ": " .. what .. " started", C.label, 4)
            end
          elseif a.kind == "setpos" then
            local def = settingAt(state.setGroup or 1, tonumber(a.name))
            if def then
              local okP, msgP = settingHere(def)
              setToast(msgP, okP and C.good or C.warn, 5)
            end
          elseif a.kind == "minecmd" then
            -- a mining team command that needs a second tap (NEW FIELD)
            local id, cmd = tostring(a.name):match("^(%d+):(%a+)$")
            if id then
              MINE.cmd(tonumber(id), cmd, {})
              setToast(cmd:upper() .. " sent - the miner gets it at its next report (up to 30 s)", C.label, 5)
            end
          elseif a.kind == "syssave" then
            -- the map worker saves (it may have to wait for storage helpers)
            MAP.saveNow = true
            os.queueEvent("map_save")
            setToast("Saving the map ...", C.label, 3)
          elseif a.kind == "sysupdate" then
            pcall(TT.codeLoad, true)
            TT.updateForce = os.clock() + 600          -- also when automatic updates are off
            local n = 0
            for _, t in pairs(state.turtles) do
              if TT.online(t) and TT.outdated(t) then t.updRetry = nil n = n + 1 end
            end
            setToast(CODE and (n == 0 and ("All online turtles run " .. TT.verName(CODE.ver))
                     or (n .. " turtle(s) get " .. TT.verName(CODE.ver) .. ", one by one")) or "No node.lua found", C.label, 5)
          elseif a.kind == "sysrestart" then
            pcall(MAP.save)
            if sysLog then sysLog("Base restarted from the SYSTEM tab", "INFO") end
            if baseExit then pcall(baseExit, nil) end
            os.reboot()
          elseif a.kind == "findlost" then
            local ok, msg = TT.findLost()
            setToast(msg, ok and C.good or C.warn, 8)
          elseif a.kind == "trescue" then
            local ok, msg = TT.rescue(tonumber(a.name))
            setToast(msg, ok and C.good or C.warn, 7)
          elseif a.kind == "tflyme" then
            -- the selected drone carries the owner to the turtle (lands on top of it)
            local t = state.turtles[tonumber(a.name)]
            local dr = state.drone
            if not dr then
              setToast("No drone available", C.warn, 4)
            elseif not (t and t.pos and t.pos.x) then
              setToast("That turtle's position is unknown", C.warn, 4)
            elseif not state.owner then
              setToast("Owner unknown (memory card)", C.warn, 4)
            else
              dr.dest = { kind = "coords", x = t.pos.x, y = t.pos.y + 1, z = t.pos.z }
              dr.passenger = state.owner
              if submitDrone(dr, { kind = "ferry", passenger = state.owner }) then
                setToast(dr.label .. " is coming to take you to " .. t.label, C.good, 6)
              end
            end
          elseif a.kind == "mapclear" then
            MAP.clear()
            state.mapSel = nil
            setToast("Map cleared", C.label, 4)
          elseif a.kind == "survey" or a.kind == "surveyall" then
            -- the area on screen, minus what is mapped, split between turtles
            local x1, z1, x2, z2 = MAP.viewArea()
            local r = CONFIG.map.scanRadius
            if not x1 then
              setToast("Open the map first", C.warn, 4)
            elseif (x2 - x1) * (z2 - z1) > 400 * 400 then
              -- a big area: the base hands it out in batches (survey queue)
              local ids
              if a.kind == "survey" then
                local t = state.turtles[tonumber(a.name)]
                ids = (t and TT.online(t)) and { t.id } or nil
              end
              if a.kind == "survey" and not ids then
                setToast("That turtle is not online", C.warn, 4)
              elseif a.kind == "surveyall" and #TT.available() == 0 then
                setToast("No free turtle (online, idle, position known)", C.warn, 5)
              else
                local n = MAP.queueSurvey(x1, z1, x2, z2, r, ids)
                setToast("Big survey started: " .. n .. " spots (" .. math.floor((x2 - x1) / 16) .. " x " ..
                         math.floor((z2 - z1) / 16) .. " chunks), handed out in batches - progress on the MAP tab",
                         C.good)
              end
            elseif a.kind == "surveyall" then
              -- a smaller area: also through the (saved) queue, so spots a
              -- turtle does not finish are handed out again
              if #TT.available() == 0 then
                setToast("No free turtle (online, idle, position known)", C.warn, 5)
              else
                local n, skipped = MAP.addSurvey(x1, z1, x2, z2, r)
                if n == 0 then
                  setToast("This area is already mapped (" .. skipped .. " spots)", C.label, 5)
                else
                  setToast("Survey: " .. n .. " spots queued" .. (skipped > 0 and (" (" .. skipped .. " already mapped)") or "") ..
                           " - handed out in batches, progress on the MAP tab", C.good, 6)
                end
              end
            else
              local ids
              if a.kind == "survey" then
                local t = state.turtles[tonumber(a.name)]
                ids = (t and TT.online(t)) and { t.id } or {}
              else
                ids = TT.available()
              end
              local spots, skipped = MAP.surveySpots(x1, z1, x2, z2, r)
              local t1 = a.kind == "survey" and state.turtles[tonumber(a.name)]
              if t1 and TT.online(t1) and not (t1.pos and t1.pos.x) then
                setToast(t1.label .. ": position unknown - press GPS LOCATE first", C.warn, 5)
              elseif #ids == 0 then
                setToast("No free turtle (online, idle, position known)", C.warn, 5)
              elseif #spots == 0 then
                setToast("This area is already mapped (" .. skipped .. " spots)", C.label, 5)
              else
                local plan = TT.splitSurvey(spots, ids)
                local parts = {}
                for _, id in ipairs(ids) do
                  if plan[id] then
                    TT.sendSpots(id, plan[id], r)
                    parts[#parts + 1] = state.turtles[id].label .. ": " .. #plan[id]
                  end
                end
                setToast("Survey sent - " .. table.concat(parts, ", ") ..
                         (skipped > 0 and (" (" .. skipped .. " already mapped)") or ""), C.good, 6)
              end
            end
          elseif a.kind == "accdeny" then
            denyPlayer(a.name)
            setToast(a.name .. " can no longer use the chat commands", C.label, 4)
          elseif a.kind == "wpdel" then
            removeWaypoint(a.name)
            for _, k in ipairs(droneOrder) do
              local dr = drones[k]
              if dr.dest and dr.dest.kind == "waypoint" and dr.dest.name == a.name then dr.dest = nil end
            end
          elseif state.busy then
            setToast("Busy: wait for the current transfer to finish", C.warn, 3)
          else
            state.busy = true
            state.actionQueue[#state.actionQueue + 1] = a
            setToast("Working...", C.label, 60)
            os.queueEvent("inv_action")
          end
        else
          state.pending = { key = a.key, exp = os.clock() + 5 }
        end
      elseif h[5] == "metype" then
        state.meType = h[6]
        state.meSel, state.meLetter, state.meItemsPage = nil, nil, 1
      elseif h[5] == "mapcell" then
        local x, z = mapWorldAt(tx, ty)
        if x then state.mapSel = { x = x, z = z } end
      elseif h[5] == "mpan" then
        -- the arrows move in SCREEN directions, whatever way the map is turned
        local V, g = MAP.view(), state.mapGeom
        if g then
          local nx, nz = MAP.toWorld(h[6][1] * math.max(1, math.floor(g.mw / 4)),
                                     h[6][2] * math.max(1, math.floor(g.mh / 4)))
          V.cx, V.cz = nx, nz
          MAP.saveView()
        end
      elseif h[5] == "mrot" then
        local V = MAP.view()
        V.rot = ((V.rot or 0) + 1) % 4
        MAP.saveView()
        local _, _, _, _, upName = MAP.compass()
        setToast("Map: " .. upName .. " is up", C.label, 3)
      elseif h[5] == "mzoom" then
        local V, steps = MAP.view(), { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512 }
        local i = 1
        for k, z in ipairs(steps) do if z == V.zoom then i = k end end
        V.zoom = steps[math.max(1, math.min(#steps, i + h[6]))]
        MAP.saveView()
      elseif h[5] == "mcenter" then
        local V = MAP.view()
        local x, z
        if h[6] == "base" and CONFIG.drone.home then
          x, z = CONFIG.drone.home.x, CONFIG.drone.home.z
        elseif h[6] == "turtle" then
          local t = state.tSel and state.turtles[state.tSel]
          if t and t.pos and t.pos.x then x, z = t.pos.x, t.pos.z end
        elseif h[6] == "me" then
          for _, e in ipairs(state.players or {}) do
            if e.name == state.owner and e.p and e.p.x then x, z = e.p.x, e.p.z end
          end
        end
        if x then V.cx, V.cz = math.floor(x), math.floor(z) MAP.saveView()
        else setToast("Position unknown", C.warn, 3) end
      elseif h[5] == "tstopall" then
        if MAP.queue then MAP.stopSurvey() end   -- STOP ALL also ends a big survey
        local n = 0
        for id, t in pairs(state.turtles) do
          if TT.online(t) then TT.send(id, "stop", {}) n = n + 1 end
        end
        setToast("STOP sent to " .. n .. " turtle(s)", C.warn, 4)
      elseif h[5] == "tmap" then
        local t = state.turtles[h[6]]
        if t and t.pos and t.pos.x then
          local V = MAP.view()
          V.cx, V.cz = t.pos.x, t.pos.z
          MAP.saveView()
          state.mapSel = { x = t.pos.x, z = t.pos.z }
          state.page = "map"
        else
          setToast("That turtle's position is unknown", C.warn, 4)
        end
      elseif h[5] == "tsel" then
        -- tapping the selected turtle again goes back to the FLEET overview
        if state.tSel == h[6] then state.tSel = nil else state.tSel = h[6] end
      elseif h[5] == "trescuer" then
        local t = state.turtles[h[6]]
        if t and t.anchor and not t.rescuerRole then
          setToast(t.label .. " is the ANCHOR - it must stay put. Choose another turtle as rescuer.", C.warn, 6)
        elseif t then
          t.rescuerRole = not t.rescuerRole or nil
          TT.listDirty = true
          pcall(TT.saveList)
          if t.rescuerRole then
            local ready, msg = TT.rescueReady(t)
            setToast(t.label .. " is the rescue turtle now - " .. msg, ready and C.good or C.warn)
            TT.send(t.id, "home", {})
          else
            setToast(t.label .. " is no longer the rescue turtle", C.label)
          end
        end
      elseif h[5] == "tcmd" then
        TT.send(h[6][1], h[6][2], h[6][3])
      elseif h[5] == "minecmd" then
        -- a new field starts where the LOADER stands: every miner must be in its chunk
        local lu = MINE.units[h[6][1]]
        if h[6][2] == "start" and lu and lu.role == "loader" and lu.ci == nil and lu.pos and lu.pos.x then
          local away = {}
          for _, mu in pairs(MINE.units) do
            if mu.role == "miner" and mu.leader == lu.id and mu.pos and mu.pos.x and
               (math.floor(mu.pos.x / 16) ~= math.floor(lu.pos.x / 16) or math.floor(mu.pos.z / 16) ~= math.floor(lu.pos.z / 16)) then
              away[#away + 1] = (mu.label or ("#" .. mu.id))
            end
          end
          if #away > 0 then
            setPopup("MINERS NOT IN THE LOADER'S CHUNK", table.concat(away, ", ") .. " must stand in the same chunk as " ..
                     "the loader (" .. fmtPos(lu.pos.x, lu.pos.y, lu.pos.z) .. ") - only that chunk is loaded at the start.", C.warn)
          end
        end
        MINE.cmd(h[6][1], h[6][2], {})
        local u = MINE.units[h[6][1]]
        local wait = u and u.role == "miner" and u.running
        setToast(string.upper(h[6][2]) .. " sent" .. (wait and " - the miner gets it at its next report (up to 30 s)" or ""),
                 C.label, 5)
      elseif h[5] == "acc_allow" then
        allowPlayer(h[6])
        chatTell(h[6], tostring(state.owner) .. " allowed you to use the drones: $" ..
                 CONFIG.chat.command .. " help")
        setToast(h[6] .. " may now use the chat commands", C.good, 4)
      elseif h[5] == "acc_yes" or h[5] == "acc_no" then
        -- handled by the chat worker exactly like the owner typing it
        state.chatInbox[#state.chatInbox + 1] = {
          uuid = state.ownerUuid, name = state.owner,
          msg = CONFIG.chat.command .. (h[5] == "acc_yes" and " yes " or " no ") .. h[6] }
        os.queueEvent("chat_cmd")
        setToast((h[5] == "acc_yes" and "Approved " or "Declined ") .. h[6], C.label, 4)
      elseif h[5] == "dscroll" then
        state[h[6][1]] = math.max(0, (state[h[6][1]] or 0) + h[6][2])
      elseif h[5] == "dsel" then
        if drones[h[6]] then state.drone = drones[h[6]] end
      elseif h[5] == "dpass" then
        if state.drone then state.drone.passenger = h[6] end
      elseif h[5] == "ddest" then
        if state.drone then state.drone.dest = { kind = "player", name = h[6] } end
      elseif h[5] == "dwp" then
        local w = findWaypoint(h[6])
        if w and state.drone then
          state.drone.dest = { kind = "waypoint", name = w.name, x = w.x, y = w.y, z = w.z }
        end
      elseif h[5] == "dsave" then
        local x, y, z = destPosCached(state.drone)
        if x then
          local n, i = "Place 1", 1
          while findWaypoint(n) do i = i + 1; n = "Place " .. i end
          addWaypoint(n, x, y, z)
          setToast("Saved as '" .. n .. "' (rename: save <name> in the console)", C.good, 5)
        elseif state.drone and state.drone.dest and state.drone.dest.kind == "player" then
          setPopup("CANNOT SAVE", state.drone.dest.name .. " is not in the overworld (or not found).", C.warn)
        end
      elseif h[5] == "dstop" then
        if submitDrone(state.drone, { kind = "stop" }) then
          setToast("Stopping " .. state.drone.label .. "...", C.warn, 4)
        end
      elseif h[5] == "pg" then
        state[h[6][1]] = state[h[6][1]] + h[6][2]
      elseif h[5] == "praw" then
        state.rawView[h[6]] = not state.rawView[h[6]] or nil
      elseif h[5] == "item" then
        if h[6] and h[6] ~= selName then selName = h[6] else selName = nil end
      elseif h[5] == "ndismiss" then
        dismissNote(h[6])
      elseif h[5] == "nclear" then
        state.notes = {}
      elseif h[5] == "mqstop" then
        local wasAuto = MAP.queue and MAP.queue.auto
        MAP.stopSurvey()
        setToast(wasAuto and "Auto-map is OFF (turn it on again on the MAP tab)" or
                 "Big survey stopped (turtles finish their current batch - STOP ALL stops them now)", C.label)
      elseif h[5] == "mauto" then
        MAP.setAuto(not MAP.auto.on)
        setToast(MAP.auto.on and "Auto-map is ON: the turtles keep surveying from the base outward, by themselves"
                 or "Auto-map is OFF", MAP.auto.on and C.good or C.label)
      elseif h[5] == "csel" then
        local cur = state.curiosSel
        if cur and cur.type == h[6][1] and cur.pos == h[6][2] then state.curiosSel = nil
        else state.curiosSel = { type = h[6][1], pos = h[6][2] } state.curiosFitPage = 1 end
      elseif h[5] == "cnotify" then
        -- the CHAT tab's buttons = '$drone notify off|on|all' for the owner
        if state.owner and state.notifySubs then
          local k = tostring(state.owner):lower()
          state.notifySubs[k] = (h[6] ~= "off") and { name = state.owner, level = h[6] } or nil
          pcall(saveNotifySubs)
          setToast("Base messages in chat: " .. ((h[6] == "off") and "OFF" or
                   (h[6] == "all") and "everything" or "warnings + errors"), C.label, 3)
        else
          setToast("Owner unknown (memory card in the Inventory Manager?)", C.warn, 4)
        end
      elseif h[5] == "setgroup" then
        state.setGroup = h[6]
      elseif h[5] == "setdec" or h[5] == "setinc" or h[5] == "setreset" then
        -- SETTINGS page: one step down / up, or back to base_config.lua
        local def = settingAt(state.setGroup or 1, h[6])
        if def then
          local okN, errN
          if h[5] == "setreset" then okN, errN = pcall(settingReset, def)
          else okN, errN = pcall(settingStep, def, h[5] == "setdec" and -1 or 1) end
          if not okN then setToast("Could not change it: " .. tostring(errN), C.warn, 5) end
        end
      elseif h[5] == "evfilter" then
        state.eventsFilter = h[6]
        state.eventsPage = 1
      elseif h[5] == "evclear" then
        noteLogClear()                  -- the list only; events.log keeps everything
        state.eventsPage = 1
      end
      return h[5] == "page" or h[5] == "group" or h[5] == "act" or h[5] == "mecraft"
    end
  end
  return false
end

