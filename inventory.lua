--[[
  BASE CONTROL  -  inventory, players, storage, curios, ME, drones, chat, turtles

  This file only starts the program. The code is split into the base_*.lua
  files, which must all be in the SAME folder as this file:

    base_config.lua      <- ALL SETTINGS (key, base, charger, chat, ME ...)
    base_devices.lua        finding peripherals on the network
    base_theme.lua          colours, window, small helpers
    base_state.lua          shared program state
    base_storage.lua        backpacks, curios, durability
    base_me.lua             ME / RS bridge and transfers
    base_players.lua        Player Detector + reading the inventory
    base_drones.lua         drones, missions, saved places, chargers
    base_turtles.lua        talking to turtles (node.lua)
    base_map.lua            map data from turtle scans
    base_console.lua        commands typed on this computer
    base_chat.lua           "$drone" chat commands
    base_ui_core.lua        design pieces, header, footer, buttons
    base_ui_*.lua           one file per page (base_ui_events.lua: EVENTS, base_ui_system.lua: SYSTEM)
    base_input.lua          touch handling
    base_workers.lua        background workers + screen loop

  All files share one namespace and are loaded in this exact order.
]]

local MODULES = {
  "base_config", "base_devices", "base_theme", "base_state", "base_storage",
  "base_me", "base_meplus", "base_curios", "base_players", "base_env", "base_drones", "base_turtles", "base_mining", "base_away", "base_factory", "base_supply", "base_schem", "base_dronework", "base_pocket", "base_store", "base_map", "base_console",
  "base_chat", "base_ui_core", "base_ui_inventory", "base_ui_players", "base_ui_env",
  "base_ui_storage", "base_ui_me", "base_ui_mesys", "base_ui_drone", "base_ui_work", "base_ui_gifts", "base_ui_turtles", "base_ui_mining", "base_ui_drive", "base_ui_home", "base_ui_map",
  "base_ui_chat", "base_ui_events", "base_ui_system", "base_ui_settings", "base_input", "base_workers",
}

local dir = ""
if shell and shell.getRunningProgram then dir = fs.getDir(shell.getRunningProgram()) end
BASE_DIR = dir
local env = _ENV

-- a floppy with its own startup.lua (e.g. the turtle install floppy) would be
-- started INSTEAD of this computer's startup.lua: switch that off here
if settings and settings.get("shell.allow_disk_startup") ~= false then
  settings.set("shell.allow_disk_startup", false)
  pcall(settings.save)
  print("Note: this computer no longer starts programs from floppy disks (the base program starts by itself).")
end

-- every base_* file is either PLAIN (base_x.lua - dragged in by hand) or PACKED (base_x.luz - what `upgrade`
-- writes: about a third of the size; the plain files were ~900 KB of the 1 MB computer). A plain one wins.
-- Packed ones are unpacked into memory by unzip.lua - nothing unpacked is written to the disk.
local function pathOf(name)
  local plain = fs.combine(dir, name .. ".lua")
  if fs.exists(plain) then return plain, false end
  local packed = fs.combine(dir, name .. ".luz")
  if fs.exists(packed) then return packed, true end
end

-- check that every file is there before starting (and name ALL missing ones)
local missing, anyPacked = {}, false
for _, name in ipairs(MODULES) do
  local p, isPacked = pathOf(name)
  if not p then missing[#missing + 1] = name .. ".lua" end
  if isPacked then anyPacked = true end
end
if #missing > 0 then
  error("Missing " .. #missing .. " file(s) in '" .. (dir == "" and "/" or dir) .. "':\n  " ..
        table.concat(missing, "\n  ") .. "\nCopy them next to inventory.lua (or type  upgrade  on the shell).", 0)
end
local inflate
if anyPacked then
  local f, e = loadfile(fs.combine(dir, "unzip.lua"), "t", env)
  inflate = f and f()
  if type(inflate) ~= "function" then
    error("unzip.lua is missing or broken (" .. tostring(e) .. ") - it unpacks the base_*.luz files. Type  upgrade  on the shell.", 0)
  end
end

-- a short pause (unpacking takes a moment; CraftOS stops a program that never pauses for ~7 s).
-- Events that come meanwhile are put back, none lost.
local function breathe()
  os.queueEvent("base_loading")
  local kept = {}
  while true do
    local e = table.pack(os.pullEventRaw())
    if e[1] == "base_loading" then break end
    if e[1] == "terminate" then error("Terminated", 0) end
    kept[#kept + 1] = e
  end
  for _, e in ipairs(kept) do os.queueEvent(table.unpack(e, 1, e.n)) end
end

local said = false
for _, name in ipairs(MODULES) do
  local path, isPacked = pathOf(name)
  local fn, err
  if isPacked then
    if not said then print("Unpacking the program ...") said = true end
    local h = fs.open(path, "rb")
    local bytes = h and h.readAll()
    if h then h.close() end
    local okU, text = pcall(inflate, bytes or "", breathe)
    if not okU then error("Error in " .. name .. ".luz: " .. tostring(text), 0) end
    -- (the same chunk name as the plain file: error messages say base_x.lua:<line> as before)
    fn, err = load(text, "@" .. fs.combine(dir, name .. ".lua"), "t", env)
    breathe()
  else
    fn, err = loadfile(path, "t", env)
  end
  if not fn then error("Error in " .. name .. ".lua: " .. tostring(err), 0) end
  fn()
end

---------------------------------------------------------------------
-- MAIN
---------------------------------------------------------------------
buildWindow()
if baseStartCheck then pcall(baseStartCheck) end      -- was the base off? (base_workers.lua)
if removeOldFiles then pcall(removeOldFiles, dir) end   -- (files of a feature taken out again)
if loadVoiceChain then pcall(loadVoiceChain)                -- optional: the base talks (on data floppies, in order)
elseif loadAddon then pcall(loadAddon, "voice_addon.lua") end

-- every worker restarts itself after an error (keepWorker, base_workers.lua) instead of stopping the base
local K = keepWorker or function(_, f) return f end
local okRun, errRun = pcall(parallel.waitForAny, K("screen", uiLoop), K("inventory worker", invWorker),
                   K("page worker", pageWorker), K("action worker", actionWorker), K("drone worker", droneWorker),
                   K("console", terminalWorker), K("chat worker", chatWorker), K("turtle worker", commsWorker),
                   K("map worker", mapWorker), K("supply worker", supplyWorker), K("add-on worker", addonWorker),
                   K("player worker", playerWorker),
                   K("curios worker", curiosWorker), K("drop worker", dropWorker))

pcall(MAP.save)                     -- map changes of the last minute
if baseExit then
  local crashed = not okRun and tostring(errRun) ~= "Terminated"
  pcall(baseExit, crashed and errRun or nil)
end
restorePalette()
mon.setBackgroundColor(colors.black)
mon.setTextColor(colors.white)
mon.clear()
mon.setCursorPos(1, 1)
if not okRun and tostring(errRun) ~= "Terminated" then
  -- an error (not printed here): startup.lua sees it and starts the program again
  error("Inventory display crashed: " .. tostring(errRun), 0)
else
  print("Inventory display stopped.")
end

