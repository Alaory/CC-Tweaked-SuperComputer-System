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
  "base_me", "base_curios", "base_players", "base_drones", "base_turtles", "base_mining", "base_away", "base_factory", "base_schem", "base_pocket", "base_store", "base_map", "base_console",
  "base_chat", "base_ui_core", "base_ui_inventory", "base_ui_players",
  "base_ui_storage", "base_ui_me", "base_ui_drone", "base_ui_turtles", "base_ui_mining", "base_ui_drive", "base_ui_home", "base_ui_map",
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

-- check that every file is there before starting (and name ALL missing ones)
local missing = {}
for _, name in ipairs(MODULES) do
  if not fs.exists(fs.combine(dir, name .. ".lua")) then missing[#missing + 1] = name .. ".lua" end
end
if #missing > 0 then
  error("Missing " .. #missing .. " file(s) in '" .. (dir == "" and "/" or dir) .. "':\n  " ..
        table.concat(missing, "\n  ") .. "\nCopy them next to inventory.lua.", 0)
end

for _, name in ipairs(MODULES) do
  local path = fs.combine(dir, name .. ".lua")
  local fn, err = loadfile(path, "t", env)
  if not fn then error("Error in " .. name .. ".lua: " .. tostring(err), 0) end
  fn()
end

---------------------------------------------------------------------
-- MAIN
---------------------------------------------------------------------
buildWindow()
if baseStartCheck then pcall(baseStartCheck) end      -- was the base off? (base_workers.lua)

local okRun, errRun = pcall(parallel.waitForAny, uiLoop, invWorker, pageWorker, actionWorker,
                   droneWorker, terminalWorker, chatWorker, commsWorker, mapWorker)

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

