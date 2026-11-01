-- base_console.lua  -  part of the base-control program (started by inventory.lua).
-- All base_*.lua files share one namespace and are loaded in a fixed order.
--
--   Commands typed on the base computer's keyboard (type 'help' there):
--   drone control, saved places, turtles, map, ME setup and checks, report, disks.

-- console on the computer's keyboard ---------------------------------------
HELP = {
  "Drone console commands:",
  " drones / drone <n>   list drones / choose one",
  " dest <x> <y> <z>     destination = coordinates",
  " dest <waypoint>      destination = saved place",
  " dest @<player>       destination = where a player is",
  " save <name> [x y z]  save the destination",
  " del <name> / list    delete / show saved places",
  " players              online players and positions",
  " fly / home           fly to destination / to base",
  " pickup [player]      pick a player up",
  " drop                 deliver to the destination",
  " ferry [player]       pickup + deliver",
  " stop / release       stop now / hand the drone back",
  " status               what the drone is doing",
  " allow / deny <name>  who may use '$drone' in chat",
  " allowed              show that list",
  " charger [x y z|off]  show / move the Charging Station",
  " turtles              list connected turtles",
  " turtle <id|name> <cmd> [args]   e.g. goto x y z, home,",
  "      sethome [x y z], setpos x y z north, locate, move up 3, stop",
  " map clear            delete all map scans",
  " exit [clear]         the turtles' exit route out of the base (or delete it)",
  " update               send node.lua to outdated turtles now (normally automatic)",
  " mesetup              find the ME buffer chest (put ONE item in it first) - no settings to edit",
  " me add <item id>     make the ME tab look up an item it does not list (partial view)",
  " me check             does the full ME list work right now? (for finding the broken item)",
  " curios check         can your worn Curios items be read? (the broken item is usually worn)",
  " tanks                your fluid containers: contents and what they offer (for filling from ME)",
  " report [local]       all peripherals + functions -> report.txt, uploaded to pastebin",
  " disks [data|move]    floppy disks; 'disks data' makes empty floppies data disks,",
  "                      'disks move' moves the map, turtle knowledge and logs onto them now",
  " rescue <id> [x y z [radius]]  send a rescue turtle to a lost or stuck turtle",
  " findlost [radius]    search around the base for lost turtles and reinstall them",
  " turtle <id> warps / warp <name> / warpsave <name>   End Automata Core teleports",
  " turtle <id> setting <name> <value>   e.g. turtle 7 setting dig true",
}

-- one command typed on the computer; returns the lines to print
function handleCommand(line)
  local words = {}
  for w in line:gmatch("%S+") do words[#words + 1] = w end
  local cmd = (words[1] or ""):lower()
  local D = state.drone
  local out = {}
  local function say(t) out[#out + 1] = t end
  local function needDrone()
    if D then return true end
    say("No Drone Interface found.")
    return false
  end

  if cmd == "" then
  elseif cmd == "help" or cmd == "?" then
    for _, l in ipairs(HELP) do say(l) end

  elseif cmd == "drones" then
    if #droneOrder == 0 then say("No Drone Interfaces found.") end
    for i, k in ipairs(droneOrder) do
      local dr = drones[k]
      say(string.format(" %d. %s%s - %s, %s", i, dr.label, (dr == D) and " (selected)" or "",
          dr.conn and "connected" or "not connected", dr.busy and "busy" or "idle"))
    end

  elseif cmd == "drone" then
    local a, pick = words[2], nil
    if a then
      local n = tonumber(a)
      if n and droneOrder[n] then pick = drones[droneOrder[n]] end
      if not pick then
        local wanted = table.concat(words, " ", 2):lower()
        for _, k in ipairs(droneOrder) do
          local dr = drones[k]
          if dr.label:lower() == wanted or k:lower() == wanted then pick = dr end
        end
      end
    end
    if pick then
      state.drone = pick
      say("Selected " .. pick.label)
    elseif a then
      say("No drone '" .. a .. "'. Type 'drones' to see them.")
    else
      say("Usage: drone <number|name>   (see 'drones')")
    end

  elseif cmd == "dest" then
    if not needDrone() then return out end
    local n = #words
    if n == 4 and tonumber(words[2]) and tonumber(words[3]) and tonumber(words[4]) then
      if not validCoords(words[2], words[3], words[4]) then
        say("Those coordinates are not valid (y must be -64..320).")
        return out
      end
      D.dest = { kind = "coords", x = math.floor(tonumber(words[2])), y = math.floor(tonumber(words[3])),
                 z = math.floor(tonumber(words[4])) }
      say(D.label .. " destination: " .. fmtPos(D.dest.x, D.dest.y, D.dest.z))
    elseif n == 2 then
      local a = words[2]
      if a:lower() == "me" or a:sub(1, 1) == "@" then
        local nm = canonPlayer(a:lower() == "me" and (state.owner or "") or a:sub(2))
        D.dest = { kind = "player", name = nm }
        say(D.label .. " destination: player " .. nm)
      else
        local w = findWaypoint(a)
        if w then
          D.dest = { kind = "waypoint", name = w.name, x = w.x, y = w.y, z = w.z }
          say(D.label .. " destination: " .. w.name .. " (" .. fmtPos(w.x, w.y, w.z) .. ")")
        else say("No saved place called '" .. a .. "'. Type 'list'.") end
      end
    else say("Usage: dest <x> <y> <z>   |   dest <waypoint>   |   dest @<player>") end

  elseif cmd == "save" then
    local name = words[2]
    if not name then say("Usage: save <name> [x y z]")
    elseif name:lower() == "base" then
      say("'Base' comes from CONFIG.drone.home in base_config.lua - change it there.")
    else
      local x, y, z
      if #words >= 3 then
        if #words ~= 5 or not validCoords(words[3], words[4], words[5]) then
          say("Usage: save <name> <x> <y> <z>   (numbers, y -64..320)")
          return out
        end
        x, y, z = math.floor(tonumber(words[3])), math.floor(tonumber(words[4])), math.floor(tonumber(words[5]))
      else
        x, y, z = resolveDest(D)
      end
      if x and y and z then
        addWaypoint(name, x, y, z)
        say("Saved '" .. name .. "' at " .. fmtPos(x, y, z))
      elseif D and D.dest then say("Cannot save: " .. cleanErr(y))
      else say("No destination chosen yet: give x y z, or choose one first") end
    end

  elseif cmd == "del" then
    if not words[2] then say("Usage: del <name>   (see 'list')")
    elseif words[2]:lower() == "base" then
      say("'Base' comes from CONFIG.drone.home in base_config.lua - it cannot be deleted.")
    else
      say(removeWaypoint(words[2]) and ("Deleted " .. words[2]) or ("No saved place called '" .. words[2] .. "'"))
    end

  elseif cmd == "list" then
    if #state.waypoints == 0 then say("No saved places yet.") end
    for _, w in ipairs(state.waypoints) do say(" " .. w.name .. "  " .. fmtPos(w.x, w.y, w.z)) end

  elseif cmd == "allow" then
    if words[2] then
      allowPlayer(canonPlayer(words[2]))
      say(canonPlayer(words[2]) .. " may now use '$" .. CONFIG.chat.command .. "' in chat")
    else say("Usage: allow <player>") end

  elseif cmd == "deny" then
    if words[2] then
      say(denyPlayer(words[2]) and (words[2] .. " removed from the list") or (words[2] .. " was not on the list"))
    else say("Usage: deny <player>") end

  elseif cmd == "findlost" then
    local radius = tonumber(words[2])
    local x, y, z = tonumber(words[3]), tonumber(words[4]), tonumber(words[5])
    if words[2] and not radius then
      say("Usage: findlost [radius] [x y z]   (default: 96 blocks around the base)")
    elseif x and not (y and z and validCoords(x, y, z)) then
      say("Usage: findlost [radius] [x y z]")
    else
      local ok, msg = TT.findLost(radius and math.max(16, math.min(160, math.floor(radius))),
                                  x and math.floor(x), y and math.floor(y), z and math.floor(z))
      say((ok and "OK: " or "Cannot: ") .. msg)
    end

  elseif cmd == "rescue" then
    local id = tonumber(words[2])
    if not id then
      say("Usage: rescue <turtle id> [x y z [radius]]   (where to look; radius = how far to search, default 24)")
    else
      local x, y, z = tonumber(words[3]), tonumber(words[4]), tonumber(words[5])
      if x and not (y and z and validCoords(x, y, z)) then
        say("Usage: rescue <turtle id> [x y z]")
      else
        local radius = tonumber(words[6])
        local ok, msg = TT.rescue(id, x and math.floor(x), y and math.floor(y), z and math.floor(z),
                                  radius and math.max(16, math.min(128, math.floor(radius))))
        say((ok and "OK: " or "Cannot: ") .. msg)
      end
    end

  elseif cmd == "report" then
    -- every peripheral and all its functions (+ opened storage items), saved to
    -- report.txt and uploaded with ComputerCraft's own pastebin program
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add("Base program report - " .. tostring(os.date and os.date("%Y-%m-%d %H:%M") or ""))
    add("Host: " .. tostring(_HOST))
    local okId, cid = pcall(os.getComputerID)
    local okLb, clabel = pcall(os.getComputerLabel)
    add("Computer id " .. tostring(okId and cid or "?") .. ", label " .. tostring(okLb and clabel or "?"))
    add("")
    -- peripherals, grouped by type (many chests -> one entry)
    local groups, order = {}, {}
    for _, n in ipairs(peripheral.getNames()) do
      local types = { pcall(peripheral.getType, n) }
      table.remove(types, 1)
      if #types == 0 then types = { "?" } end
      local key = table.concat(types, " + ")
      local okM, methods = pcall(peripheral.getMethods, n)
      methods = okM and type(methods) == "table" and methods or {}
      table.sort(methods)
      local sig = key .. "|" .. table.concat(methods, ",")
      if not groups[sig] then
        groups[sig] = { types = key, methods = methods, names = {} }
        order[#order + 1] = sig
      end
      table.insert(groups[sig].names, n)
    end
    add("== PERIPHERALS (" .. #peripheral.getNames() .. ") ==")
    for _, sig in ipairs(order) do
      local g = groups[sig]
      local shown = {}
      for i = 1, math.min(#g.names, 6) do shown[#shown + 1] = g.names[i] end
      add("")
      add("[" .. g.types .. "] " .. table.concat(shown, ", ") .. (#g.names > 6 and (" ... +" .. (#g.names - 6) .. " more") or ""))
      add("  functions: " .. table.concat(g.methods, ", "))
    end
    -- storage items the Inventory Manager can open (scanned right now)
    pcall(refreshStorage)
    add("")
    add("== STORAGE ITEMS (opened by the Inventory Manager) ==")
    for _, st in ipairs(state.storage or {}) do
      local okD, fns = pcall(function() return describeStorageItem and describeStorageItem(st.ref) end)
      fns = okD and fns or ("error: " .. tostring(fns))
      add(tostring(st.display or st.name) .. " (" .. tostring(st.where) .. ")" ..
          (st.isFluid and " [fluids]" or "") .. (st.isItem and " [items]" or ""))
      add("  functions: " .. tostring(fns or "could not be opened"))
    end
    local text = table.concat(lines, "\n") .. "\n"
    local file = "report.txt"
    if not saveFileSafe(file, text) then
      say("Could not save " .. file .. " (disk full?)")
      return out
    end
    say("Saved " .. file .. " (" .. #lines .. " lines)." .. (words[2] ~= "local" and " Uploading with pastebin ..." or ""))
    if shell and http and words[2] ~= "local" then
      local okU = pcall(shell.run, "pastebin", "put", file)
      if okU then
        say("Send the pastebin link shown above. (If the upload failed: run  pastebin put report.txt")
        say("after stopping this program, or type  report local  to only save the file.)")
      else
        say("Upload failed - stop this program and run:  pastebin put report.txt")
      end
    else
      say("Upload it with:  pastebin put report.txt  (after stopping this program)")
    end

  elseif cmd == "tanks" then
    tankReport(say)

  elseif cmd == "curios" and words[2] == "check" then
    -- can the worn Curios items be read right now? (take them off one by one
    -- into a chest and check after each: the broken item is usually worn)
    if not inv or not inv.listCurios then say("This Inventory Manager has no Curios support.") return out end
    local ok, r = pcall(inv.listCurios)
    if ok then
      local n = 0
      if type(r) == "table" then for _ in pairs(r) do n = n + 1 end end
      say("CURIOS READABLE: the broken item is NOT worn right now (" .. n .. " slot groups read).")
      say("If you just took something off: that item is the broken one. Find it in the ME")
      say("terminal, move it into a chest too, then type  me check")
    elseif isDistError(r) then
      say("STILL BROKEN: the broken item is still worn. Take off the next Curios item")
      say("(put it in a chest, not your inventory) and type  curios check  again.")
      local msg = tostring(r)
      for i = 1, math.min(#msg, 300), 48 do say("  " .. msg:sub(i, i + 47)) end
    else
      say("Could not check: " .. tostring(r))
    end

  elseif cmd == "me" and words[2] == "check" then
    -- one full listing right now: for finding the broken item by taking
    -- storage cells out (half at a time) and checking after each step
    if not bridge then say("No ME Bridge found on this computer.") return out end
    local ok, r = callx(bridge, "getItems", {})
    if ok and type(r) == "table" then
      local n = 0
      for _ in pairs(r) do n = n + 1 end
      say("FULL LIST WORKS: " .. n .. " item types. The broken item is NOT in the network right now.")
    elseif not ok and isDistError(r) then
      say("STILL BROKEN: the broken item is still in the network.")
      -- the full server error: the class it names often belongs to the mod of the broken item
      local msg = tostring(r)
      say("Server error:")
      for i = 1, math.min(#msg, 600), 48 do say("  " .. msg:sub(i, i + 47)) end
    else
      say("Could not check: " .. tostring(r))
    end

  elseif cmd == "me" and words[2] == "add" then
    local n = words[3]
    if not n or not n:find(":", 1, true) then
      say("Usage: me add <item id>   e.g.  me add minecraft:slime_block")
    else
      meAddName(n:lower())
      say("Remembered " .. n:lower() .. " - the ME tab looks it up within a minute.")
    end

  elseif cmd == "mesetup" then
    meSetup(say)

  elseif cmd == "disks" then
    local list = mountedDisks()
    if words[2] == "move" then
      -- move the big data files onto the data floppies now (trimmed to fit)
      local hasData = false
      for _, d in ipairs(list) do if d.data then hasData = true end end
      if not hasData then
        say("No data floppy yet: put an EMPTY floppy into a Disk Drive and type  disks data")
        return out
      end
      local before = fs.getFreeSpace("/")
      local chunks0, walls0 = #MAP.order, KNOW.n
      pcall(MAP.save)
      pcall(KNOW.save)
      pcall(saveLogs)
      local function where(p)
        local d = dataFile(p)
        return (fs.exists(d) and (d .. " (" .. math.ceil(fs.getSize(d) / 1024) .. " KB)")) or "not saved"
      end
      say("Map:              " .. where(CONFIG.map.file) ..
          (#MAP.order < chunks0 and ("  - trimmed to the newest " .. #MAP.order .. " chunks") or ""))
      say("Turtle knowledge: " .. where(CONFIG.turtles.knowFile) ..
          (KNOW.n < walls0 and ("  - trimmed to the newest " .. KNOW.n .. " walls") or ""))
      say("Drone logs:       " .. where(CONFIG.drone.logFile))
      local after = fs.getFreeSpace("/")
      say("This computer: " .. math.floor(after / 1024) .. " KB free (gained " ..
          math.max(0, math.floor((after - before) / 1024)) .. " KB)")
      if state.diskLow then say("Note: " .. state.diskLow) end
    elseif words[2] == "data" then
      local n = 0
      for _, d in ipairs(list) do
        if d.empty and not d.installer then
          local h = fs.open(fs.combine(d.mount, "base_data"), "w")
          if h then h.write("data floppy of the base") h.close() end
          pcall(disk.setLabel, d.name, "Base data")
          n = n + 1
        end
      end
      if n == 0 then
        say("No empty floppy found. Put an EMPTY floppy into a Disk Drive on this computer, then try again.")
      else
        say(n .. " floppy disk(s) are now data disks. Moving the map, turtle knowledge and drone logs there ...")
        pcall(MAP.save)
        pcall(KNOW.save)
        pcall(saveLogs)
        say("Done. Free on this computer now: " .. math.floor(fs.getFreeSpace("/") / 1024) .. " KB")
      end
    else
      if #list == 0 then say("No floppy disks found (Disk Drives next to this computer or on the network).") end
      for _, d in ipairs(list) do
        local role = d.data and "DATA" or (d.installer and "INSTALLER" or (d.empty and "empty" or "other"))
        say(string.format(" %-7s %-10s %4d KB free  %s", d.mount, role, math.floor(d.free / 1024), tostring(d.label or "")))
      end
      say("This computer: " .. math.floor(fs.getFreeSpace("/") / 1024) .. " KB free.   'disks data' = use empty floppies for data")
    end

  elseif cmd == "update" then
    pcall(TT.codeLoad)
    if not CODE then
      say("No " .. TT.codePath() .. " on this computer - copy node.lua next to inventory.lua.")
    else
      local n = 0
      for id, t in pairs(state.turtles) do
        if TT.online(t) and TT.outdated(t) then TT.pushCode(id) n = n + 1 end
      end
      say("Turtle program " .. CODE.ver:sub(1, 8) .. ": sent to " .. n .. " outdated turtle(s)." ..
          (n == 0 and " All online turtles are up to date." or ""))
      say(state.installDisk and ("Install disk is up to date (" .. state.installDisk .. ").")
          or "No install disk: put an empty floppy in a Disk Drive on this computer.")
    end

  elseif cmd == "exit" then
    if words[2] == "clear" then
      EXITROUTE = nil
      KNOW.dirty = true
      pcall(KNOW.save)
      say("Exit route deleted. Record a new one on the TURTLES tab.")
    elseif EXITROUTE then
      say("Exit route: " .. EXITROUTE.n .. " corners, saved " ..
          math.floor((os.epoch("utc") - EXITROUTE.t) / 60000) .. " min ago" ..
          (EXITROUTE.by and (" by " .. EXITROUTE.by) or ""))
      say("  " .. EXITROUTE.route:gsub(";", "  >  "))
    else
      say("No exit route yet. Record one on the TURTLES tab (EXIT: START, drive out, SAVE).")
    end
    local nd = 0
    for _ in pairs(KNOW.dead) do nd = nd + 1 end
    say("Shared knowledge: " .. KNOW.n .. " walls, " .. nd .. " dead ends.")

  elseif cmd == "map" then
    if words[2] == "clear" then
      MAP.clear()
      say("Map cleared (all scans deleted).")
    else
      say("Map: " .. #MAP.order .. " chunks.   'map clear' deletes all scans.")
    end

  elseif cmd == "turtles" then
    local list = TT.list()
    if #list == 0 then say("No turtles yet. Run node.lua on a turtle.") end
    for _, t in ipairs(list) do
      say(string.format(" #%d %s - %s, fuel %s, %s", t.id, t.label,
          TT.online(t) and "online" or "offline", tostring(t.fuel or "?"),
          t.pos and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "position unknown"))
    end

  elseif cmd == "turtle" then
    local t = words[2] and TT.find(words[2])
    local tc = words[3] and words[3]:lower()
    if words[2] and not t then
      say("No turtle '" .. words[2] .. "'. Type 'turtles' to see them.")
    elseif not t or not tc then
      say("Usage: turtle <id|name> <command> [args]   (see 'turtles')")
    else
      local args = {}
      for i = 4, #words do args[#args + 1] = tonumber(words[i]) or words[i] end
      TT.send(t.id, tc, args)
      say("Sent '" .. tc .. "' to " .. t.label)
    end

  elseif cmd == "charger" then
    -- charger x y z      = the station of ALL drones (one charges on it, the others park beside it)
    -- charger x y z <n>  = a station for drone n only
    if words[2] == "off" then
      setCharger(nil, nil)
      say("Charging Station removed - drones park at Base")
    elseif #words >= 4 then
      if not validCoords(words[2], words[3], words[4]) then
        say("Usage: charger <x> <y> <z> [drone number]   or   charger off")
        return out
      end
      local x, y, z = math.floor(tonumber(words[2])), math.floor(tonumber(words[3])), math.floor(tonumber(words[4]))
      if words[5] then
        local dr = drones[droneOrder[tonumber(words[5]) or 0]]
        if not dr then say("No drone " .. words[5] .. " (see 'drones')") return out end
        setOwnCharger(dr, x, y, z)
        say(dr.label .. "'s own Charging Station: " .. fmtPos(x, y, z))
      else
        setCharger(nil, x, y, z)
        say("Charging Station of all drones: " .. fmtPos(x, y, z) .. " - one charges on it, the others park beside it")
      end
    elseif #words >= 2 then
      say("Usage: charger <x> <y> <z> [drone number]   or   charger off")
    else
      if chargerNote then say(chargerNote) end
      for i, k in ipairs(droneOrder) do
        local dr = drones[k]
        local x, y, z, on = parkSpot(dr)
        say(" " .. i .. ". " .. dr.label .. ": " .. (x and ((on and "ON the station, parks at " or "beside the station, parks at ")
            .. fmtPos(x, y, z)) or "no station - parks at Base"))
      end
      say("charger <x> <y> <z>  = station of all drones;  add a drone number for its own station")
    end

  elseif cmd == "allowed" then
    local n = allowedNames()
    say("Owner: " .. tostring(state.owner) .. "   Allowed: " .. (#n > 0 and table.concat(n, ", ") or "nobody else"))

  elseif cmd == "players" then
    if not det then say("No Player Detector connected.")
    else
      if #(state.players or {}) == 0 then pcall(refreshPlayers, true) end
      for _, e in ipairs(state.players or {}) do
        say(" " .. e.name .. "  " .. (e.p and fmtPos(e.p.x, e.p.y, e.p.z) or "?"))
      end
      if #(state.players or {}) == 0 then say("No data yet - open the PLAYERS or DRONE tab once.") end
    end

  elseif cmd == "status" then
    if not needDrone() then return out end
    say(D.label .. ": " .. (D.conn and "connected" or "NOT connected"))
    if D.pos then say("Position: " .. fmtPos(D.pos.x, D.pos.y, D.pos.z)) end
    if D.pressure then say(string.format("Pressure: %.1f bar", D.pressure)) end
    say("Destination: " .. destLabel(D))
    if D.mission then say("Mission: " .. D.mission.title .. " (" .. D.mission.state .. ")") end

  elseif cmd == "fly" or cmd == "drop" or cmd == "stop" or cmd == "release"
         or cmd == "pickup" or cmd == "ferry" or cmd == "home" then
    if not needDrone() then return out end
    local who = words[2] and canonPlayer(words[2]) or nil
    if who and #(state.players or {}) > 0 then
      local online = false
      for _, e in ipairs(state.players) do if e.name == who then online = true end end
      if not online then say(who .. " is not online.") return out end
    end
    if D.busy and cmd ~= "stop" and cmd ~= "release" then
      say(D.label .. " is busy" .. (D.mission and (" (" .. D.mission.title .. ")") or "") ..
          " - type 'stop' first.")
      return out
    end
    if who then D.passenger = who end
    if submitDrone(D, { kind = cmd, passenger = who }) then
      say("OK: " .. D.label .. " " .. cmd .. " - see the DRONE tab")
    end

  else
    say("Unknown command '" .. cmd .. "'. Type 'help'.")
  end
  return out
end

