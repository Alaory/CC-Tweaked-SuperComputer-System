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
      elseif h[5] == "page" then
        state.page = h[6]
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
              setToast("Area too big - zoom in first", C.warn, 5)
            else
              local ids
              if a.kind == "survey" then
                local t = state.turtles[tonumber(a.name)]
                ids = (t and TT.online(t)) and { t.id } or {}
              else
                ids = TT.available()
              end
              local spots, skipped = MAP.surveySpots(x1, z1, x2, z2, r)
              if #ids == 0 then
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
        end
      elseif h[5] == "mrot" then
        local V = MAP.view()
        V.rot = ((V.rot or 0) + 1) % 4
        MAP.saveView()
        local _, _, _, _, upName = MAP.compass()
        setToast("Map: " .. upName .. " is up", C.label, 3)
      elseif h[5] == "mzoom" then
        local V, steps = MAP.view(), { 1, 2, 4, 8, 16 }
        local i = 1
        for k, z in ipairs(steps) do if z == V.zoom then i = k end end
        V.zoom = steps[math.max(1, math.min(#steps, i + h[6]))]
      elseif h[5] == "mores" then
        local V = MAP.view()
        V.ores = not V.ores
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
        if x then V.cx, V.cz = math.floor(x), math.floor(z)
        else setToast("Position unknown", C.warn, 3) end
      elseif h[5] == "tstopall" then
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
          state.mapSel = { x = t.pos.x, z = t.pos.z }
          state.page = "map"
        else
          setToast("That turtle's position is unknown", C.warn, 4)
        end
      elseif h[5] == "tsel" then
        state.tSel = h[6]
      elseif h[5] == "tcmd" then
        TT.send(h[6][1], h[6][2], h[6][3])
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
      elseif h[5] == "nhist" then
        state.noteHistory = not state.noteHistory
        state.noteUnread = 0
      elseif h[5] == "nhclose" then
        state.noteHistory = false
      elseif h[5] == "nhclear" then
        state.noteLog = {}
      end
      return h[5] == "page" or h[5] == "act" or h[5] == "mecraft"
    end
  end
  return false
end

