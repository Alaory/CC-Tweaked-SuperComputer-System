-- usage: lua run.lua <srcdir> <out.txt> <page> [scenario]
SRC_DIR, OUT, PAGE, SCEN = arg[1], arg[2], arg[3] or "inventory", arg[4]
local getenv, popen = os.getenv, io.popen
REALCLOCK, LABEL = os.clock, getenv("LABEL") or ""
local here = arg[0]:match("^(.*)/") or "."
dofile(here .. "/world.lua")
local W0 = PERIPHS
dofile(here .. "/cc_stub.lua")
PERIPHS = W0
PERIPHS.right.obj = MONITOR
-- the program's own files take room on the computer (what is copied into the game)
for _, f in ipairs({ "inventory.lua", "node.lua" }) do
  local h = io.open(SRC_DIR .. "/" .. f) if h then CODE_SIZE = CODE_SIZE + #h:read("a") h:close() end
end
local ls = popen('ls "' .. SRC_DIR .. '"/base_*.lua')
for f in ls:lines() do local h = io.open(f) CODE_SIZE = CODE_SIZE + #h:read("a") h:close() end
ls:close()
if getenv("PRE") then dofile(getenv("PRE")) end   -- set-up before the program loads
local env = _ENV
local MODULES = {
  "base_config", "base_devices", "base_theme", "base_state", "base_storage",
  "base_me", "base_players", "base_drones", "base_turtles", "base_map", "base_console",
  "base_chat", "base_ui_core", "base_ui_inventory", "base_ui_players",
  "base_ui_storage", "base_ui_me", "base_ui_drone", "base_ui_turtles", "base_ui_map",
  "base_ui_chat", "base_ui_events", "base_input", "base_workers",
}
for _, name in ipairs(MODULES) do
  local fn, err = loadfile(SRC_DIR .. "/" .. name .. ".lua", "t", env)
  if not fn then error(err) end
  fn()
end
buildWindow()
refreshInventory()
refreshPlayers(true)
refreshDrones()
state.status = state.status == "loading" and "ok" or state.status
state.page = PAGE
-- sample turtles
state.turtles[7] = { id = 7, label = "Scout1", log = {}, lastN = 0, fuel = 4210, pos = { x = -5280, y = 60, z = 10830, f = "north" }, task = "idle", lastSeen = CLOCK - 2 }
state.turtles[9] = { id = 9, label = "Miner2", log = {}, lastN = 0, fuel = 120, pos = { x = -5100, y = 12, z = 10700, f = "east" }, task = "survey", lastSeen = CLOCK - 90 }
if SCEN and SCEN ~= "" then dofile(SCEN) end
draw()
local f = io.open(OUT, "w")
for y = 1, H do local t, fg, bg = MONITOR.getLine(y) f:write(t, "\n", fg, "\n", bg, "\n") end
f:close()
-- palette as set by applyPalette
local pf = io.open(OUT .. ".pal", "w")
for c, rgb in pairs(PALETTE) do pf:write(string.format("%x %06x\n", math.floor(math.log(c, 2) + 0.5), rgb)) end
pf:close()
