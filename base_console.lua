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
  " turtle <id> log [n]  the turtle's last n log lines in full",
  " turtle <id> diag     its disk, files, saved job and gear (answer in its log)",
  " survey               the big survey: progress, what each turtle is waiting for",
  " survey auto [on|off] auto-map: turtles keep surveying from the base outward",
  " theme [name|random]  the monitor's colours (random = a different one each start)",
  " uptime               how long the base runs, and when it was off (and why)",
  " store [find|update]  storage helper computers (store.lua): free space, update them now",
  " events [n] [errors]  the last n saved messages (also after a restart)",
  "      sethome [x y z], setpos x y z north, locate, move up 3, stop",
  " map clear            delete all map scans",
  " exit [clear]         the turtles' exit route out of the base (or delete it)",
  " update               turtle program versions; update outdated turtles now (normally automatic)",
  " mesetup              find the ME buffer chest (put ONE item in it first) - no settings to edit",
  " me add <item id>     make the ME tab look up an item it does not list (partial view)",
  " me tags <item id>    the tags the ME reports for an item (and its Curios slots)",
  " me check             does the full ME list work right now? (for finding the broken item)",
  " curios check         can your worn Curios items be read? (the broken item is usually worn)",
  " curios probe         what the curios move functions want (nothing is moved)",
  " tanks                your fluid containers: contents and what they offer (for filling from ME)",
  " report [local]       all peripherals + functions -> report.txt, uploaded to pastebin",
  " disks [data|move]    floppy disks; 'disks data' makes empty floppies data disks,",
  "                      'disks move' moves the map, turtle knowledge and logs onto them now",
  " rescue <id> [x y z [radius]]  send a rescue turtle to a lost or stuck turtle",
  " findlost [radius]    search around the base for lost turtles and reinstall them",
  " turtle <id> forget   take a turtle that is gone (server crash) off the list",
  " mine [drop|forget] <id>   mining turtles: drop = a lost miner out of its team",
  " factory [chest <name>|builder <id>|build|stop]   build turtles from AE2 parts",
  " schem [<name>|delete <name>]   Create schematics (drag a .nbt onto this screen)",
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

  elseif cmd == "curios" and words[2] == "probe" then
    say("How this Inventory Manager wants the curios functions called (nothing is moved):")
    curiosProbe(say)

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

  elseif cmd == "me" and words[2] == "tags" then
    -- what the ME Bridge says about one item: its tags and the Curios slots
    -- they mean (the CURIOS tab lists ME items by these tags)
    if not bridge then say("No ME Bridge found on this computer.") return out end
    local id = words[3]
    if not id or not id:find(":", 1, true) then say("Usage: me tags <item id>   e.g. me tags artifacts:night_vision_goggles") return out end
    local ok, it = callx(bridge, "getItem", { name = id })
    if not ok or type(it) ~= "table" or not it.name then
      say("The ME network does not report " .. id .. (ok and "" or (": " .. tostring(it))))
      return out
    end
    say(id .. ": " .. tostring(it.count or it.amount or "?") .. " in the network")
    if type(it.tags) ~= "table" then
      say("No tags reported for it (" .. type(it.tags) .. ") - the CURIOS tab cannot tell where it fits.")
    else
      local list = {}
      for k, v in pairs(it.tags) do list[#list + 1] = (type(v) == "string") and v or tostring(k) end
      table.sort(list)
      say("Tags (" .. #list .. "): " .. table.concat(list, ", "))
      local slots = {}
      for s in pairs(curioSlotsOf(it) or {}) do slots[#slots + 1] = s end
      table.sort(slots)
      say("Curios slots from these tags: " .. (#slots > 0 and table.concat(slots, ", ") or "none"))
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
      pcall(MAP.save, true)              -- every region: moves them onto the floppies
      pcall(KNOW.save)
      pcall(saveLogs)
      local function where(p)
        local d = dataFile(p)
        return (fs.exists(d) and (d .. " (" .. math.ceil(fs.getSize(d) / 1024) .. " KB)")) or "not saved"
      end
      local total, onPc, files = MAP.diskUse()
      say("Map:              " .. files .. " files, " .. math.ceil((total - onPc) / 1024) ..
          " KB on floppies, " .. math.ceil(onPc / 1024) .. " KB on the computer" ..
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
        pcall(MAP.save, true)
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
      -- storage helpers (store.lua on computers on the cable): the map goes there after the floppies
      local nh = 0
      for id, h in pairs(STORE and STORE.helpers or {}) do
        nh = nh + 1
        say(string.format(" helper #%-4d %s", id, h.refused and ("NOT USED: " .. tostring(h.refused))
            or (math.floor((h.free or 0) / 1024) .. " KB free, " .. tostring(h.files or 0) .. " files")))
      end
      if nh == 0 then say(" No storage helper computers found (store.lua on a computer on the wired cable).") end
      -- what fills this computer: the biggest files (floppies / rom not counted)
      local files = {}
      local function walk(dir)
        for _, n in ipairs(fs.list(dir)) do
          local p = fs.combine(dir, n)
          if fs.getDrive(p) == "hdd" then
            if fs.isDir(p) then walk(p) else files[#files + 1] = { p, fs.getSize(p) } end
          end
        end
      end
      pcall(walk, "")
      table.sort(files, function(a, b) return a[2] > b[2] end)
      local parts = {}
      for i = 1, math.min(10, #files) do parts[#parts + 1] = files[i][1] .. " " .. math.ceil(files[i][2] / 1024) .. "K" end
      say("Biggest files here: " .. table.concat(parts, ", "))
      if state.diskLow then say("Last warning: " .. state.diskLow) end
    end

  elseif cmd == "update" then
    local okL, errL = pcall(TT.codeLoad, true)       -- always read node.lua again
    if not okL then say("Reading node.lua failed: " .. tostring(errL)) end
    if TT.codeError then say("The new node.lua does NOT compile (not sent): " .. TT.codeError) end
    if CODE then
      say("Program file: " .. tostring(CODE.path or TT.codePath()) .. " (" .. #CODE.text .. " bytes) = " ..
          TT.verName(CODE.ver))
    end
    if not CODE then
      say("No " .. TT.codePath() .. " on this computer - copy node.lua next to inventory.lua.")
    else
      -- the update queue takes them one by one; "update" just retries at once
      local n = 0
      for _, t in ipairs(TT.list()) do
        local mark = (t.ver == CODE.ver) and "up to date" or (t.updReady == CODE.ver and "ready, installs after its job")
                     or (TT.online(t) and "will be updated" or "offline")
        say("  " .. t.label .. " #" .. t.id .. ": " .. TT.verName(t.ver) .. " - " .. mark)
        if TT.online(t) and TT.outdated(t) then t.updRetry = nil n = n + 1 end
      end
      say("Turtle program on the base: " .. TT.verName(CODE.ver) .. ". " ..
          (n == 0 and "All online turtles are up to date." or (n .. " turtle(s) get it, one by one.")))
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

  elseif cmd == "events" then
    -- the saved messages (events.log), newest last; "events 30 errors"
    local n = tonumber(words[2]) or 15
    local only = (words[3] or words[2] or ""):lower()
    local kinds = { errors = "ERROR", error = "ERROR", warnings = "WARNING", warning = "WARNING",
                    done = "DONE", info = "INFO" }
    local want = kinds[only]
    local lines, shown = noteLogLines(), {}
    for i = #lines, 1, -1 do
      local l = lines[i]
      local d, kind, title, msg = l:match("^(%S+ %S+)|(%u+)|([^|]*)|(.*)$")
      if d and (not want or kind == want) then
        local _, mo, da, hm = d:match("^(%d+)-(%d+)-(%d+) (%S+)$")
        table.insert(shown, 1, (da and (da .. "." .. mo .. " " .. hm) or d) .. " " ..
                     (kind == "CLEAR" and "-----" or kind) .. "  " ..
                     (title ~= "" and (title .. ": ") or "") .. msg)
        if #shown >= n then break end
      end
    end
    if #shown == 0 then say("No saved messages" .. (want and (" of that kind") or "") .. " yet.") end
    for _, l in ipairs(shown) do say(l) end
    say("(saved in events.log + events.old.log on this computer, about 32 KB at most)")

  elseif cmd == "store" then
    -- storage helpers (store.lua on other computers on the wired network)
    if words[2] == "find" or words[2] == "update" or not next(STORE.helpers) then
      local okW, nW, list = pcall(STORE.wakeAll)
      if okW and nW > 0 then
        say("Turned on " .. nW .. " helper computer(s) that were OFF (" .. table.concat(list, ", ") .. ") - waiting 4 s ...")
        sleep(4)
      end
      say("Looking for storage helpers (2 s) ...")
      pcall(STORE.find)
      local okK, nK, klist = pcall(STORE.kickSilent)
      if okK and nK > 0 then
        say("Restarted " .. nK .. " helper(s) that were on but not answering (" .. table.concat(klist, ", ") .. ") - waiting 5 s ...")
        sleep(5)
        pcall(STORE.find)
      end
    end
    if words[2] == "update" then
      local okU, n = pcall(STORE.updateAll)
      say(okU and (n .. " helper(s) got the new store.lua") or ("Update failed: " .. tostring(n)))
    end
    local code = STORE.code()
    local n = 0
    for id, h in pairs(STORE.helpers) do
      n = n + 1
      if h.refused then say("  computer " .. id .. ": " .. h.refused)
      else say(string.format("  computer %d %s: %d KB free of %d KB, %d files, %s", id, h.label and ("(" .. h.label .. ")") or "",
                             math.floor((h.free or 0) / 1024), math.floor((h.cap or 0) / 1024), h.files or 0,
                             (code and h.ver == code.ver) and "up to date" or (h.ver and "OLDER store.lua" or "old store.lua (copy by hand once)"))) end
    end
    -- helpers used before that do not answer now
    for id in pairs(STORE.known) do
      local nid = tonumber(id)
      if nid and not STORE.helpers[nid] then
        say("  computer " .. nid .. ": NO ANSWER - is it on? The base turns its helpers on over the cable, but only if")
        say("    the wired modem ON that computer is connected (right-click it: it shows red). Else turn it on by hand.")
      end
    end
    if n == 0 then
      say("No storage helpers. Put store.lua on another computer with a WIRED modem on the base's cable,")
      say("run  store  on it once (it then starts by itself), then type  store find  here.")
    else
      local free = STORE.space()
      say("Together: " .. math.floor(free / 1024) .. " KB free for the map (used after the data floppies).")
    end

  elseif cmd == "factory" then
    -- the turtle factory: setup, part check, status
    local sub = (words[2] or ""):lower()
    if sub == "chest" then
      if words[3] then
        if not peripheral.isPresent(words[3]) then
          say("No '" .. words[3] .. "' on the cable. Type  factory chest  to see the chests.")
        else
          FACTORY.chest = words[3]
          FACTORY.save()
          say("Factory chest: " .. words[3] .. ". It must stay EMPTY - only the factory uses it - and be next to the builder.")
        end
      else
        say("Chests on the cable (the factory chest must be EMPTY and next to the builder turtle):")
        local n = 0
        for _, name in ipairs(peripheral.getNames()) do
          local okI, isI = pcall(peripheral.hasType, name, "inventory")
          if okI and isI and name:find("_") and not name:find("drive", 1, true) then
            local okL, list = pcall(peripheral.call, name, "list")
            local items = 0
            for _ in pairs(okL and list or {}) do items = items + 1 end
            say("  " .. name .. (items == 0 and "   (empty)" or ("   " .. items .. " stacks")))
            n = n + 1
          end
        end
        if n == 0 then say("  none - put a chest on the cable (a wired modem on it, right-clicked)") end
        say("Then:  factory chest <name>")
      end
    elseif sub == "builder" then
      local t = words[3] and TT.find(words[3])
      if not t then say("Usage: factory builder <turtle id>   (it needs a Disk Drive, the install floppy and a pickaxe)")
      else
        FACTORY.builder = t.id
        FACTORY.save()
        say(t.label .. " is the builder. Its HOME must be next to the factory chest, with the block on the other side")
        say("of it, the block above it and the block above the build spot free.")
      end
    elseif sub == "build" then
      FACTORY.fails, FACTORY.waitUntil = 0, nil
      FACTORY.save()
      local why = FACTORY.blocked()
      say(why and ("Not now: " .. why) or "Building one as soon as the parts are there (checked every 10 s).")
    elseif sub == "stop" then
      FACTORY.job, FACTORY.waitUntil = nil, os.clock() + 3600
      FACTORY.save()
      say("Factory stopped for an hour (set the fleet size to 0 in SETTINGS > TURTLES to switch it off).")
    else
      local line = FACTORY.statusLine()
      say("Factory: " .. line .. "   (fleet " .. FACTORY.fleet() .. ", target " .. tostring(FACTORY.cfg("target", 0)) .. ")")
      local b = FACTORY.builderTurtle()
      say("  builder: " .. (b and (b.label .. " #" .. b.id) or "none") .. "   chest: " .. tostring(FACTORY.chest or "none") ..
          "   built so far: " .. tostring(FACTORY.built or 0))
      if FACTORY.last then say("  last: " .. tostring(FACTORY.last.msg)) end
      if bridge then
        say("Parts per turtle (in the ME network / AE2 can craft it):")
        local rows = FACTORY.check()
        for _, r in ipairs(rows) do
          local st = r.have >= r.part.count and "in stock" or (r.craftable and "AE2 crafts it" or "MISSING - no pattern")
          say(string.format("  %-28s %3d x  have %-5d %s", r.part.what, r.part.count, r.have, st))
          if not r.ok then
            local hint = FACTORY.hint(r.part.name)
            say("      " .. r.part.name .. (hint and ("  - recipe: " .. hint) or "  - recipe: see JEI"))
          end
        end
        say("AE2 works out the sub-parts itself (e.g. the computer inside the turtle) - if it has patterns for them.")
      else
        say("No ME Bridge - the factory needs AE2.")
      end
    end

  elseif cmd == "schem" or cmd == "schematics" then
    local sub = words[2]
    if sub == "delete" and words[3] then
      say(SCHEM.delete(words[3]) and ("Deleted " .. words[3]) or ("No schematic '" .. words[3] .. "'"))
    elseif sub then
      local s, err = SCHEM.load(sub)
      if not s then say(err)
      else
        local need, place, air = SCHEM.materials(s)
        say(sub .. ": " .. s.size.x .. " x " .. s.size.y .. " x " .. s.size.z .. " (x y z), " .. place .. " blocks to place, " ..
            air .. " air (cleared), " .. #s.palette .. " kinds of block")
        local list = {}
        for it, n in pairs(need) do list[#list + 1] = { it, n } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i, e in ipairs(list) do
          if i > 24 then say("  ... " .. (#list - 24) .. " more") break end
          say(string.format("  %5d  %s", e[2], e[1]))
        end
      end
    else
      local names = {}
      for name, path in pairs(SCHEM.list()) do names[#names + 1] = name .. "  (" .. path .. ")" end
      table.sort(names)
      if #names == 0 then
        say("No schematics yet. Save one with Create's Schematic and Quill, then drag the .nbt file")
        say("(from .minecraft/schematics on your PC) onto this computer's screen.")
      end
      for _, n in ipairs(names) do say("  " .. n) end
      say("schem <name> = size and materials,  schem delete <name>")
    end

  elseif cmd == "mine" then
    -- mining-dimension turtles: list / take a lost one out of its team / forget one
    local sub, id = (words[2] or ""):lower(), tonumber(words[3])
    local u = id and MINE.units[id]
    if (sub == "drop" or sub == "forget") and not u then
      say("No mining turtle #" .. tostring(words[3]) .. ". Type  mine  to see them.")
    elseif sub == "drop" then
      if u.role ~= "miner" then
        say("#" .. id .. " is not a miner (only miners can be dropped from a team).")
      else
        local team = MINE.teams()[u.dim or "?"]
        local l = team and team.loader
        if not l then
          say("No loader for " .. tostring(u.dim) .. " - nothing to drop it from.")
        else
          MINE.cmd(l.id, "drop", { id })
          MINE.units[id] = nil
          pcall(MINE.save)
          say("Told the loader #" .. l.id .. " to take miner #" .. id .. " out of the team (its layer goes to the others).")
          if not MINE.online(l) then say("The loader is offline - it gets this when it reports again.") end
        end
      end
    elseif sub == "forget" then
      MINE.units[id] = nil
      pcall(MINE.save)
      say("#" .. id .. " forgotten on the base (a miner still in a team: use  mine drop " .. id .. "  instead).")
    else
      local any = false
      for uid, x in pairs(MINE.units) do
        any = true
        say(string.format(" #%-4d %-7s %-10s %s", uid, tostring(x.role), tostring(x.dim), MINE.online(x) and "online"
            or ("OFFLINE, last seen " .. (x.seenEpoch and TT.ago(x.seenEpoch) or "never"))))
      end
      if not any then say("No mining turtles yet.") end
      say("mine drop <id> = a lost miner out of its team,  mine forget <id> = off the base's list")
    end

  elseif cmd == "away" then
    -- the last WHILE YOU WERE AWAY report (or the live one while away)
    if AWAY.on then
      say("Away mode is ON since " .. fmtSpan((os.epoch("utc") - (AWAY.since or 0)) / 1000) .. " - so far:")
      for _, l in ipairs(AWAY.report()) do say("  " .. l.t) end
    elseif AWAY.last then
      local okD, d = pcall(os.date, "%d.%m %H:%M", math.floor(AWAY.last.t / 1000))
      say("Last time you came back (" .. (okD and d or "?") .. "):")
      for _, l in ipairs(AWAY.last.lines or {}) do say("  " .. l.t) end
    else
      say("No away report yet. Away mode starts " .. math.floor((tonumber(AWAY.cfg("after", 300)) or 300) / 60) ..
          " min after you leave the server.")
    end
    local on = AWAY.ownerOnline()
    say("You are " .. (on == true and "online" or (on == false and "offline" or "unknown (no Player Detector?)")))

  elseif cmd == "uptime" then
    local a = BASE_ALIVE or {}
    local now = os.epoch("utc")
    say("Running for " .. fmtSpan((now - (a.since or now)) / 1000) .. " (start #" .. tostring(a.starts or "?") .. ")")
    if not a.offs or #a.offs == 0 then say("No time off noted yet.") end
    for _, o in ipairs(a.offs or {}) do
      local okF, f = pcall(os.date, "%d.%m %H:%M", math.floor(o.from / 1000))
      say("  off " .. (okF and f or "?") .. " for " .. fmtSpan((o.to - o.from) / 1000) .. " - " .. tostring(o.why))
    end

  elseif cmd == "theme" then
    local want = (words[2] or ""):lower()
    if want == "" then
      say("Theme now: " .. tostring(THEME_NAME) .. "   (mode: " .. tostring(THEME_MODE) .. ")")
      say("Themes: " .. table.concat(THEME_ORDER, ", ") .. ", random")
      say("theme <name> = keep that one;  theme random = a different one on every start")
    elseif want == "random" then
      THEME_MODE = "random"
      saveTheme(nil)
      local pick
      repeat pick = THEME_ORDER[math.random(#THEME_ORDER)] until pick ~= THEME_NAME or #THEME_ORDER < 2
      setTheme(pick)
      saveTheme(nil)
      os.queueEvent("inv_update")
      say("Random theme on every start. Now: " .. pick)
    elseif THEMES[want] then
      setTheme(want)
      THEME_MODE = want
      saveTheme(want)
      os.queueEvent("inv_update")
      say("Theme: " .. want .. " (kept after restarts)")
    else
      say("No theme '" .. want .. "'. Themes: " .. table.concat(THEME_ORDER, ", ") .. ", random")
    end

  elseif cmd == "survey" and words[2] == "auto" then
    local w = (words[3] or ""):lower()
    if w == "on" or w == "off" then MAP.setAuto(w == "on") end
    say("Auto-map: " .. (MAP.auto.on and "ON" or "OFF") .. (MAP.auto.done and " (done: whole world)" or "") ..
        (MAP.full and " - PAUSED, map floppies full" or "") ..
        " - surveyed around the base: " .. math.floor(MAP.autoRadius()) .. " blocks")
    say("survey auto on | off")

  elseif cmd == "survey" then
    -- the big survey: progress and what the base sees for every turtle
    local q = MAP.queue
    if not q then
      say("No big survey running.")
    else
      local frac, total = MAP.surveyProgress()
      say(string.format("Big survey %d %d -> %d %d: %d of %d spots checked, %d sent, %d already mapped",
          q.x1, q.z1, q.x2, q.z2, q.cursor, total, q.sent, q.skipped))
      local busyN = 0
      for _ in pairs(q.out or {}) do busyN = busyN + 1 end
      say("Batches out now: " .. busyN .. "   spots to redo (a turtle did not finish them): " .. #(q.redo or {}))
      say("Turtles: " .. (q.ids and "chosen ones" or "all free ones") .. " - free now: " .. #TT.available())
      for _, t in ipairs(TT.list()) do
        local fuel = tonumber(t.fuel)
        say(string.format("  %s #%d: %s, task %s, pos %s, fuel %s%s%s%s%s%s",
            t.label, t.id, TT.online(t) and "online" or "OFFLINE", tostring(t.task),
            (t.pos and t.pos.x) and "ok" or "UNKNOWN", tostring(t.fuel),
            t.held and ", HELD (stopped)" or "", (q.excluded and q.excluded[t.id]) and ", EXCLUDED" or "",
            t.anchor and ", anchor" or "", t.rescuerRole and ", rescuer" or "",
            (t.queueAt and os.clock() - t.queueAt < 15) and ", just got a batch" or ""))
      end
      local n0 = #state.tOut
      local okF, errF = pcall(MAP.feedSurvey)
      if not okF then say("Handing out FAILED: " .. tostring(errF))
      else say("Handing out now: " .. (#state.tOut - n0) .. " batch(es) sent.") end
    end

  elseif cmd == "map" then
    if words[2] == "clear" then
      if MAP.clear() then say("Map cleared (all scans deleted).")
      else say("The map is still loading - try again in a moment.") end
    else
      pcall(MAP.save)
      local total, onPc, files = MAP.diskUse()
      say("Map: overview " .. MAP.ovN .. " chunks, detail " .. #MAP.order .. " chunks, in " .. files .. " files, " ..
          math.ceil(total / 1024) .. " KB (" .. math.ceil((total - onPc) / 1024) .. " KB on data floppies, " ..
          math.ceil(onPc / 1024) .. " KB on this computer).")
      say("'map clear' deletes all scans. 'disks data' makes empty floppies data disks for the map.")
    end

  elseif cmd == "turtles" then
    local list = TT.list()
    if #list == 0 then say("No turtles yet. Run node.lua on a turtle.") end
    for _, t in ipairs(list) do
      local _, lab, _, why = TT.status(t)
      say(string.format(" #%d %s - %s: %s, fuel %s, %s", t.id, t.label, lab, why, tostring(t.fuel or "?"),
          t.pos and fmtPos(t.pos.x, t.pos.y, t.pos.z) or "position unknown"))
      if t.gear and t.gear ~= "" then say("     gear: " .. t.gear) end
    end

  elseif cmd == "turtle" then
    local t = words[2] and TT.find(words[2])
    local tc = words[3] and words[3]:lower()
    if words[2] and not t then
      say("No turtle '" .. words[2] .. "'. Type 'turtles' to see them.")
    elseif not t or not tc then
      say("Usage: turtle <id|name> <command> [args]   (see 'turtles')")
    elseif tc == "forget" then
      if TT.online(t) then
        say(t.label .. " is online - not forgotten.")
      else
        local label = t.label
        TT.forget(t.id)
        say(label .. " forgotten: off the list, its survey spots go to the other turtles.")
      end
    elseif tc == "log" then
      -- the turtle's log in full (the monitor cuts long lines), oldest first
      local n = math.min(tonumber(words[4]) or 10, #t.log)
      if n == 0 then say(t.label .. ": nothing in the log yet") end
      for i = n, 1, -1 do say(t.log[i].t .. "  " .. t.log[i].msg) end
    else
      local args = {}
      for i = 4, #words do args[#args + 1] = tonumber(words[i]) or words[i] end
      TT.send(t.id, tc, args)
      say("Sent '" .. tc .. "' to " .. t.label .. (TT.online(t) and "" or " - but it is OFFLINE: it will not get it, send it again when it is back"))
      say("Its answer goes to its log: turtle " .. t.id .. " log 5   (or the LOG on the TURTLES tab)")
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

