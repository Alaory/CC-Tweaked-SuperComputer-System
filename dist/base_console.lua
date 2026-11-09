






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
" upgrade [check]      get the newest BASE program files from GitHub (no dragging), then restart",
" upgrade branch <b>   take the files from another branch",
" mesetup              find the ME buffer chest (put ONE item in it first) - no settings to edit",
" me add <item id>     make the ME tab look up an item it does not list (partial view)",
" me tags <item id>    the tags the ME reports for an item (and its Curios slots)",
" me check             does the full ME list work right now? (for finding the broken item)",
" curios check         can your worn Curios items be read? (the broken item is usually worn)",
" curios probe         what the curios move functions want (nothing is moved)",
" curios auto [clear]  the AUTO-EQUIP rules (keep a totem ... on) / remove them all",
" tanks                your fluid containers: contents and what they offer (for filling from ME)",
" report [local]       all peripherals + functions -> report.txt, uploaded to pastebin",
" disks [data|move]    floppy disks; 'disks data' makes empty floppies data disks,",
"                      'disks move' moves the map, logs, turtle + mining data onto them now",
" rescue <id> [x y z [radius]]  send a rescue turtle to a lost or stuck turtle",
" findlost [radius]    search around the base for lost turtles and reinstall them",
" turtle <id> forget   take a turtle that is gone (server crash) off the list",
" drive <id>   steer a turtle with the keyboard: W A S D, SPACE up, SHIFT down",
" mine [drop|forget] <id>   mining turtles: drop = a lost miner out of its team",
" factory [chest <name>|builder <id>|build|stop]   build turtles from AE2 parts",
" factory recipes|learn|forget <item>|crafter <id>   recipes TAUGHT to a crafting turtle",
" factory fuel [<item> [count]|reset]   the fuel a new turtle gets (default 16 coal blocks)",
" factory items [<item>]   every version of an item in AE2 (default: the turtle) - plain or yours",
" party [stop]          SEARCH PARTY: all free turtles look for the lost ones together; the rescuer fetches them",
" schem [<name>|delete <name>]   Create schematics (drag a .nbt onto this screen)",
" pocket [unpair <id>]   the paired pocket computers (run pocket.lua on one to pair)",
" turtle <id> warps / warp <name> / warpsave <name>   End Automata Core teleports",
" turtle <id> setting <name> <value>   e.g. turtle 7 setting dig true",
}





function baseUpgrade(args, log)
local path = fs.combine(BASE_DIR or "", "upgrade.lua")
if not fs.exists(path) then
log("upgrade.lua is missing. Get it once on the computer's shell (Ctrl+T stops the base):")
log("  wget https://raw.githubusercontent.com/Alaory/CC-Tweaked-SuperComputer-System/" ..
"claude/computercraft-base-review-ihjtqw/upgrade.lua " .. path)
return false
end
local fn, err = loadfile(path, "t", _ENV)
if not fn then log("upgrade.lua is broken: " .. tostring(err)) return false end
local okR, done, n = pcall(fn, { args = args or {}, dir = BASE_DIR or "", log = log })
if not okR then log("Upgrade stopped by an error: " .. tostring(done)) return false end
if done then
if sysLog then sysLog("Program upgraded from GitHub (" .. tostring(n) .. " files) - restarting", "INFO") end
log("Saving the map and restarting in 3 s ...")
pcall(MAP.save)
if baseExit then pcall(baseExit, nil) end
sleep(3)
os.reboot()
end
return done
end

function handleCommand(line)
local words = {}
for w in line:gmatch("%S+") do words[#words + 1] = w end
local cmd = (words[1] or ""):lower()

local ALIAS = { disk = "disks", floppy = "disks", floppies = "disks" }
if ALIAS[cmd] then cmd = ALIAS[cmd] end
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

elseif cmd == "party" then

if words[2] == "stop" then
local ok, msg = TT.partyStop("called back")
say(ok and msg or "No search party is out.")
elseif TT.party then
say(TT.partyLine())
say("party stop  calls it back (everyone goes home)")
else
local lost = TT.lostList()
say(#lost .. " lost turtle(s) (offline, last spot known):")
for _, t in ipairs(lost) do say("  " .. t.label .. " #" .. t.id .. " at " .. fmtPos(t.pos.x, t.pos.y, t.pos.z)) end
local ok, msg = TT.partyStart()
say(msg)
end
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


local lines = {}
local function add(s) lines[#lines + 1] = s end
add("Base program report - " .. tostring(os.date and os.date("%Y-%m-%d %H:%M") or ""))
add("Host: " .. tostring(_HOST))
local okId, cid = pcall(os.getComputerID)
local okLb, clabel = pcall(os.getComputerLabel)
add("Computer id " .. tostring(okId and cid or "?") .. ", label " .. tostring(okLb and clabel or "?"))
add("")

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

elseif cmd == "curios" and words[2] == "auto" then
if words[3] == "clear" then
CURIOS.auto = {}
CURIOS.save()
say("All AUTO-EQUIP rules removed.")
elseif #CURIOS.auto == 0 then
say("No AUTO-EQUIP rules. CURIOS tab: tap a slot, then AUTO next to an item.")
else
for _, r in ipairs(CURIOS.auto) do
say(" " .. r.slot .. ": " .. (r.display or r.item) .. " - " .. (r.why or "kept on"))
end
if not CONFIG.me.curiosChest then say("NOTE: putting on needs CONFIG.me.curiosChest (an empty barrel).") end
end
elseif cmd == "curios" and words[2] == "probe" then
say("How this Inventory Manager wants the curios functions called (nothing is moved):")
curiosProbe(say)

elseif cmd == "curios" and words[2] == "check" then


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


if not bridge then say("No ME Bridge found on this computer.") return out end
local ok, r = callx(bridge, "getItems", {})
if ok and type(r) == "table" then
local n = 0
for _ in pairs(r) do n = n + 1 end
say("FULL LIST WORKS: " .. n .. " item types. The broken item is NOT in the network right now.")
elseif not ok and isDistError(r) then
say("STILL BROKEN: the broken item is still in the network.")

local msg = tostring(r)
say("Server error:")
for i = 1, math.min(#msg, 600), 48 do say("  " .. msg:sub(i, i + 47)) end
else
say("Could not check: " .. tostring(r))
end

elseif cmd == "me" and words[2] == "tags" then


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

local hasData = false
for _, d in ipairs(list) do if d.data then hasData = true end end
local _, helpers = STORE.space()
if not hasData and helpers == 0 then
say("No data floppy and no storage helper yet: put an EMPTY floppy into a Disk Drive and type  disks data")
return out
end
local before = fs.getFreeSpace("/")
local chunks0, walls0 = #MAP.order, KNOW.n

dataPathReset()
if hasData then
local cur1 = logPaths("events.log", "events.old.log")
local cur2 = logPaths("system.log", "system.old.log")
for _, f in ipairs({ "mining.dat", "me_names.dat", CONFIG.turtles.listFile }) do dataPath(f) end
say("Logs:             " .. fs.getDir(cur1) .. "/  (events, system" ..
(fs.getDir(cur2) ~= fs.getDir(cur1) and (" -> " .. fs.getDir(cur2)) or "") .. ", mining, turtles, AE2 names)")
end
local movedMap = 0
local okO, nO = pcall(MAP.offload)
if okO then movedMap = nO or 0 end
if hasData then pcall(MAP.save, true) end
pcall(KNOW.save)
pcall(saveLogs)
local function where(p)
local d = dataFile(p)
return (fs.exists(d) and (d .. " (" .. math.ceil(fs.getSize(d) / 1024) .. " KB)")) or "not saved"
end
local total, onPc, files = MAP.diskUse()
if movedMap > 0 then say("Map:              moved " .. movedMap .. " file(s) off this computer") end
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

local nh = 0
for id, h in pairs(STORE and STORE.helpers or {}) do
nh = nh + 1
say(string.format(" helper #%-4d %s", id, h.refused and ("NOT USED: " .. tostring(h.refused))
or (math.floor((h.free or 0) / 1024) .. " KB free, " .. tostring(h.files or 0) .. " files")))
end
if nh == 0 then say(" No storage helper computers found (store.lua on a computer on the wired cable).") end

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

elseif cmd == "upgrade" then
local a = {}
for i = 2, #words do a[#a + 1] = words[i] end
baseUpgrade(a, say)

elseif cmd == "update" then
local okL, errL = pcall(TT.codeLoad, true)
if not okL then say("Reading node.lua failed: " .. tostring(errL)) end
if TT.codeError then say("The new node.lua does NOT compile (not sent): " .. TT.codeError) end
if CODE then
say("Program file: " .. tostring(CODE.path or TT.codePath()) .. " (" .. #CODE.text .. " bytes) = " ..
TT.verName(CODE.ver))
end
if not CODE then
say("No " .. TT.codePath() .. " on this computer - copy node.lua next to inventory.lua.")
else

local n = 0
for _, t in ipairs(TT.list()) do
local mark = (t.ver == CODE.ver) and "up to date" or (t.updReady == CODE.ver and "ready, installs after its job")
or (TT.online(t) and "will be updated" or "offline")
say("  " .. t.label .. " #" .. t.id .. ": " .. TT.verName(t.ver) .. " - " .. mark)
if TT.online(t) and TT.outdated(t) then n = n + 1 end
end
TT.forceUpdate()
say("Turtle program on the base: " .. TT.verName(CODE.ver) .. ". " ..
(n == 0 and "All online turtles are up to date."
or (n .. " turtle(s) get it now, 3 at a time (busy ones stop their job to install it).")))
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

local sub = (words[2] or ""):lower()
if sub == "items" then


local name = words[3] or FACTORY.cfg("turtle", "computercraft:turtle_advanced")
local list
if bridge and type(bridge.getItems) == "function" then
local ok, r = pcall(bridge.getItems, { name = name })
if ok and type(r) == "table" then list = r end
end
if not list then
local ok, it = callx(bridge, "getItem", { name = name })
list = (ok and type(it) == "table") and { it } or {}
end
say(#list .. " version(s) of " .. name .. " in AE2:")
for i, it in ipairs(list) do
if i > 8 then say("  ...") break end
local keys = {}
for _, key in ipairs({ "components", "nbt" }) do
if type(it[key]) == "table" then
for k, v in pairs(it[key]) do
local vs = type(v) == "table" and "{..}" or tostring(v)
keys[#keys + 1] = tostring(k):gsub("^minecraft:", "") .. "=" .. vs:sub(1, 12)
end
end
end
say(string.format("  %d x %s  %s", tonumber(it.amount or it.count) or 0,
FACTORY.special(it) and "YOURS (never taken)" or "plain",
(#keys > 0) and table.concat(keys, " ") or "(no details given)"))
end
elseif sub == "fuel" then

local item, n = words[3], tonumber(words[4])
if item == "reset" then
resetSetting("factory.fuel")
resetSetting("factory.fuelCount")
say("Fuel back to the default: " .. FACTORY.cfg("fuelCount", 16) .. " x " .. FACTORY.cfg("fuel", "minecraft:coal_block"))
elseif item then
if not item:find(":", 1, true) then
say("Give the full item name, e.g.  factory fuel minecraft:coal_block 16   (see the AE2 tab for names)")
else
setSetting("factory.fuel", item)
if n then setSetting("factory.fuelCount", math.max(1, math.min(64, math.floor(n)))) end
local plain = FACTORY.variants(item)
say("New turtles get " .. FACTORY.cfg("fuelCount", 16) .. " x " .. item .. " (" .. plain .. " in AE2" ..
((plain == 0) and " - none yet: put some in or give AE2 a pattern" or "") .. ").")
end
else
say("Fuel for new turtles: " .. FACTORY.cfg("fuelCount", 16) .. " x " .. FACTORY.cfg("fuel", "minecraft:coal_block"))
say("Change:  factory fuel <item> [count]   e.g.  factory fuel minecraft:coal_block 16   - back:  factory fuel reset")
end
elseif sub == "recipes" then
local any = false
for name, r in pairs(FACTORY.recipes) do
any = true
local ing = {}
for n, c in pairs(FACTORY.ingredients(r)) do ing[#ing + 1] = c .. " " .. prettify(n) end
say(" " .. prettify(name) .. " (" .. name .. ") x" .. r.count .. " <- " .. table.concat(ing, ", "))
end
if not any then say("No taught recipes. SETTINGS > FACTORY: Teach a recipe (or  factory learn ).") end
elseif sub == "learn" then
local c = FACTORY.crafterTurtle()
if not c or not TT.online(c) then say("No crafter turtle online (a turtle with a crafting table equipped).")
else
TT.send(c.id, "learnrecipe", {})
say(c.label .. " crafts the items in its 3x3 grid once and learns what they make.")
end
elseif sub == "forget" and words[3] then
local name = words[3]
if not FACTORY.recipes[name] then
for n in pairs(FACTORY.recipes) do if prettify(n):lower() == table.concat(words, " ", 3):lower() then name = n end end
end
say(FACTORY.forget(name) and ("Recipe forgotten: " .. name) or ("No recipe for '" .. words[3] .. "' (see  factory recipes )"))
elseif sub == "crafter" then
local t = words[3] and TT.find(words[3])
if not t then say("Usage: factory crafter <turtle id>   (a turtle with a crafting table, home next to the factory chest)")
else
FACTORY.crafter = t.id
FACTORY.save()
say("Crafter: " .. t.label .. ". Its home must be next to the factory chest.")
end
elseif sub == "chest" then
if words[3] then
if not peripheral.isPresent(words[3]) then
say("No '" .. words[3] .. "' on the cable. Type  factory chest  to see the chests.")
elseif FACTORY.reserved(words[3]) then
say(words[3] .. " is already used by the base (" .. FACTORY.reserved(words[3]) .. ") - pick another empty chest / barrel.")
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
local used = FACTORY.reserved(name)
say("  " .. name .. (used and ("   (in use: " .. used .. " - not this one)") or
(items == 0 and "   (empty)" or ("   " .. items .. " stacks"))))
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
say("Factory stopped for an hour (set the fleet size to 0 in SETTINGS > FACTORY to switch it off).")
else

if bridge then
say("Parts per turtle (plain ones in AE2 - yours are never taken):")
local rows = FACTORY.check()
for _, r in ipairs(rows) do
local st = r.have >= r.part.count and "ok" or (r.craftable and "AE2 crafts it" or
((r.own or 0) > 0 and "only YOURS (used/enchanted)" or "MISSING"))
say(string.format(" %-20s %2d x have %-6d %s", r.part.what:sub(1, 20), r.part.count, r.have, st))
if not r.ok then
local hint = FACTORY.hint(r.part.name)
say("    " .. r.part.name .. (hint and (" - recipe: " .. hint) or " - give AE2 a pattern"))
end
end
else
say("No ME Bridge - the factory needs AE2.")
end
local b = FACTORY.builderTurtle()
say("Builder: " .. (b and (b.label .. " #" .. b.id) or "none") .. "   chest: " .. tostring(FACTORY.chest or "none") ..
"   built: " .. tostring(FACTORY.built or 0))
if FACTORY.last then say("Last try: " .. tostring(FACTORY.last.msg)) end
local line = FACTORY.statusLine()
say("FACTORY: " .. line .. "   (fleet " .. FACTORY.fleet() .. ", target " .. tostring(FACTORY.cfg("target", 0)) .. ")")
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

elseif cmd == "pocket" then
if words[2] == "unpair" and tonumber(words[3]) then
say(POCKET.unpair(tonumber(words[3])) and ("Pocket #" .. words[3] .. " unpaired.") or "No such pocket.")
else
local any = false
for id, p in pairs(POCKET.pockets) do
any = true
say(string.format("  #%-4d %-16s last seen %s", id, tostring(p.name), p.seen and TT.ago(p.seen) or "never"))
end
if not any then say("No pocket paired. Copy pocket.lua onto your pocket computer (with a modem), run  pocket  on it.") end
say("pocket unpair <id> = it can no longer control the base")
end

elseif cmd == "mine" then

local sub, id = (words[2] or ""):lower(), tonumber(words[3])
local u = id and MINE.units[id]
if (sub == "drop" or sub == "forget") and not u then
say("No mining turtle #" .. tostring(words[3]) .. ". Type  mine  to see them.")
elseif sub == "drop" then
local _, msg = MINE.drop(id)
say(msg)
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

elseif cmd == "drive" then
say("drive <id> - steer that turtle with this computer's keyboard (W A S D, SPACE, SHIFT, Q quits).")
say("Turtle ids: type  turtles")
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

