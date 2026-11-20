-- A START WITH ODD SAVED FILES (the owner: "go over every feature and check them"). Every saved table is read
-- while the base files LOAD - outside any pcall: an error there and the base never starts (startup.lua starts it
-- again, into the same error, for ever). A file from an older version, a half-written one, a hand-edited one:
-- every .dat file the base reads is made to hold odd data, ALL base files are loaded again as at a start, then
-- every page draws and every background job runs.
local VARIANTS = {
  { "a number", function() return 42 end },
  { "a word", function() return "text" end },
  { "an empty table", function() return {} end },
  { "a list of odd things", function() return { 1, "x", {}, true } end },
  { "odd fields", function() return { x = "a", y = {}, on = "yes", units = 5, turtles = 7, list = "x", job = {}, cursor = "x",
                                       n = "?", key = 5, pockets = 3, allowed = "all", places = 4, [1] = { x = "a" } } end },
  { "turtles / units with odd fields", function()
      return { [5] = { id = "x", label = {}, pos = 12, home = "h", log = "x", fuel = "lots", task = 3, lastSeen = "x" },
               [6] = 7, turtles = { [5] = { label = 3 } }, units = { [9] = { role = 1, dim = {}, log = 4, queue = "q" } } }
    end },
  { "a list of tables with odd fields", function()
      return { { name = 3, x = "a", y = {}, z = 1 }, { slot = 1, item = {} }, { id = 5, label = {}, pos = 3, seen = "x", task = {} },
               { id = "7", gear = 5, home = { x = "a" } }, { step = 4, name = {}, done = 1 } }
    end },
}
local MODULES = {
  "base_config", "base_devices", "base_theme", "base_state", "base_storage",
  "base_me", "base_meplus", "base_curios", "base_players", "base_env", "base_drones", "base_turtles", "base_mining", "base_away",
  "base_factory", "base_supply", "base_schem", "base_dronework", "base_pocket", "base_store", "base_map", "base_console",
  "base_chat", "base_ui_core", "base_ui_inventory", "base_ui_players", "base_ui_env",
  "base_ui_storage", "base_ui_me", "base_ui_mesys", "base_ui_drone", "base_ui_work", "base_ui_turtles", "base_ui_mining",
  "base_ui_drive", "base_ui_home", "base_ui_map",
  "base_ui_chat", "base_ui_events", "base_ui_system", "base_ui_settings", "base_input", "base_workers",
}
-- (inventory.lua's own list - the test must load the same files in the same order)
local inv = io.open(SRC_DIR .. "/inventory.lua"):read("a")
local listed = 0
for _ in inv:match("local MODULES = (%b{})"):gmatch('"(base_[%w_]+)"') do listed = listed + 1 end
CHECK(listed == #MODULES, "the test loads the same " .. #MODULES .. " files as inventory.lua (" .. listed .. ")")

local errors = {}
local realExists, realOpen, realUnser = fs.exists, fs.open, textutils.unserialize
local realHttp = http
local function isDat(p) return tostring(p):find("%.dat$") ~= nil or tostring(p):find("%.dat%.tmp$") ~= nil end
local function guarded(f, ...)
  local args = table.pack(...)
  debug.sethook(function() error("RUNS TOO LONG (endless loop?)") end, "", 5e7)
  local ok, r = pcall(f, table.unpack(args, 1, args.n))
  debug.sethook()
  return ok, r
end
for _, V in ipairs(VARIANTS) do
  local name, make = V[1], V[2]
  -- every .dat file exists and reads back as this odd thing
  fs.exists = function(p) if isDat(p) then return true end return realExists(p) end
  fs.open = function(p, mode)
    if isDat(p) and (mode == "r" or mode == "rb") and not FILES[p] then
      return { readAll = function() return "odd" end, readLine = function() return nil end, close = function() end }
    end
    return realOpen(p, mode)
  end
  textutils.unserialize = function(s) return make() end
  textutils.unserialise = textutils.unserialize
  local stage = "load"
  for _, mod in ipairs(MODULES) do
    local fn, err = loadfile(SRC_DIR .. "/" .. mod .. ".lua", "t", _ENV)
    if not fn then errors[#errors + 1] = name .. ": " .. mod .. " does not compile: " .. tostring(err) break end
    local ok, e = guarded(fn)
    if not ok then errors[#errors + 1] = name .. ": the base does NOT START - " .. mod .. ".lua: " .. tostring(e) break end
  end
  -- back to real files for the rest of the run
  fs.exists, fs.open, textutils.unserialize = realExists, realOpen, realUnser
  textutils.unserialise = realUnser
  http = realHttp
  -- then: the screen and the background jobs, with what was loaded
  pcall(buildWindow)
  for _, pg in ipairs({ "home", "turtles", "drive", "map", "mining", "drone", "work", "players", "system", "settings", "me", "inventory" }) do
    state.page = pg
    local ok, e = guarded(draw)
    if not ok then errors[#errors + 1] = name .. ": page " .. pg .. ": " .. tostring(e) end
  end
  for _, j in ipairs({ "TT.updateTick", "TT.patrolTick", "TT.homeTick", "TT.avoidTick", "TT.stallTick", "MAP.feedSurvey",
                       "MAP.autoTick", "MINE.updTick", "MINE.silentTick", "FACTORY.tick", "AWAY.tick", "DW.tick", "SUPPLY.tick",
                       "TT.saveList", "MINE.save", "POCKET.status", "TT.partyTick", "CURIOS.autoTick", "parkCheck", "baseAliveTick" }) do
    local f = _ENV
    for part in j:gmatch("[^%.]+") do f = f and f[part] end
    if type(f) == "function" then
      local ok, e = guarded(f)
      if not ok then errors[#errors + 1] = name .. ": job " .. j .. ": " .. tostring(e) end
    end
  end
end
fs.exists, fs.open, textutils.unserialize, textutils.unserialise = realExists, realOpen, realUnser, realUnser
CHECK(#errors == 0, #errors .. " problem(s) with odd saved files:\n  " .. table.concat(errors, "\n  ", 1, math.min(#errors, 50)))
