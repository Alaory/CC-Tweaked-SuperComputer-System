

























local MODULES = {
"base_config", "base_devices", "base_theme", "base_state", "base_storage",
"base_me", "base_curios", "base_players", "base_drones", "base_turtles", "base_mining", "base_away", "base_factory", "base_supply", "base_schem", "base_pocket", "base_store", "base_map", "base_console",
"base_chat", "base_ui_core", "base_ui_inventory", "base_ui_players",
"base_ui_storage", "base_ui_me", "base_ui_drone", "base_ui_turtles", "base_ui_mining", "base_ui_drive", "base_ui_home", "base_ui_map",
"base_ui_chat", "base_ui_events", "base_ui_system", "base_ui_settings", "base_input", "base_workers",
}

local dir = ""
if shell and shell.getRunningProgram then dir = fs.getDir(shell.getRunningProgram()) end
BASE_DIR = dir
local env = _ENV



if settings and settings.get("shell.allow_disk_startup") ~= false then
settings.set("shell.allow_disk_startup", false)
pcall(settings.save)
print("Note: this computer no longer starts programs from floppy disks (the base program starts by itself).")
end


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




buildWindow()
if baseStartCheck then pcall(baseStartCheck) end

local okRun, errRun = pcall(parallel.waitForAny, uiLoop, invWorker, pageWorker, actionWorker,
droneWorker, terminalWorker, chatWorker, commsWorker, mapWorker, supplyWorker)

pcall(MAP.save)
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

error("Inventory display crashed: " .. tostring(errRun), 0)
else
print("Inventory display stopped.")
end

