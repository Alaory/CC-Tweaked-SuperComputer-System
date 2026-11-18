-- REMOTE ACCESS MENU (the owner: the typed console in the browser is "kinda hard to use"): the
-- browser tab opens on the pocket remote's TAP screen - the REAL pocket.lua in "local" mode on
-- the base computer, talking to the base by EVENTS (no modem, no pairing). It must never install
-- itself as the base computer's startup.lua.
local W, H = 51, 19
local SCREEN = {}
local cx, cy = 1, 1
local fakeTerm = {
  getSize = function() return W, H end, clear = function() SCREEN = {} end,
  setCursorPos = function(x, y) cx, cy = x, y end, setTextColor = function() end, setBackgroundColor = function() end,
  isColor = function() return true end,
  write = function(s) local l = SCREEN[cy] or string.rep(" ", W)
    SCREEN[cy] = (l:sub(1, cx - 1) .. s .. l:sub(cx + #s)):sub(1, W) cx = cx + #s end,
}
local function screenText() local t = {} for y = 1, H do t[#t + 1] = SCREEN[y] or "" end return table.concat(t, "\n") end
local EV = {}
local copied = false
local penv = setmetatable({}, { __index = _G })
penv.term = fakeTerm
penv.os = setmetatable({ queueEvent = function(...) EV[#EV + 1] = { ... } end }, { __index = os })
penv.fs = setmetatable({ copy = function() copied = true end, move = function() copied = true end }, { __index = fs })
penv.shell = { getRunningProgram = function() return "remote_tab_program" end }
penv.rednet = { send = function() error("LOCAL mode must not use the radio") end, lookup = function() return nil end }

_G.POCKET_TEST, _G.POCKET_LOCAL = true, true
local chunk = assert(loadfile(SRC_DIR .. "/pocket.lua", "t", penv))
local P = chunk()
_G.POCKET_TEST, _G.POCKET_LOCAL = nil, nil
CHECK(type(P) == "table", "pocket.lua loads in local mode")
CHECK(not copied, "local mode never installs itself as startup.lua (it runs on the BASE computer)")

-- the events go to the base (remoteWorker -> POCKET.receiveLocal) and the answer comes back
local realQ = os.queueEvent
os.queueEvent = function(...) EV[#EV + 1] = { ... } end          -- (the base's replies)
local function pumpAll()
  for _ = 1, 5 do
    local evs = EV
    EV = {}
    if #evs == 0 then return end
    for _, e in ipairs(evs) do
      if e[1] == "pocket_local" then POCKET.receiveLocal(e[2])
      elseif e[1] == "pocket_local_reply" then penv.handle("local", e[2]) end
    end
  end
end
P.key, P.base = "local", "local"
penv.refresh()
pumpAll()
CHECK(type(P.data) == "table" and P.data.turtles and #P.data.turtles >= 1, "status arrives by events (no pairing)")

-- every tab draws on the computer's 51 x 19 screen, with the CMD tab
for _, tab in ipairs({ "home", "ride", "bots", "mine", "msg", "more" }) do
  P.tab = tab
  P.hits = {}
  local ok, err = pcall(penv.draw)
  CHECK(ok, "tab " .. tab .. " draws: " .. tostring(err))
end
CHECK(screenText():find("CMD", 1, true), "a CMD tab (back to typed commands)")
local cmd
for _, h in ipairs(P.hits) do if h.y == 1 and SCREEN[1]:sub(h.x, h.x + 2) == "CMD" then cmd = h end end
CHECK(cmd ~= nil, "CMD can be clicked")
if cmd then penv.click(cmd.x, 1) end
CHECK(P.quit == "cmd", "clicking CMD goes to the typed commands")
P.quit = nil

-- an action from the buttons reaches the base and its answer comes back
local sent0 = #state.tOut
penv.act("turtle", { 7, "home" })
pumpAll()
local got = false
for i = sent0 + 1, #state.tOut do if state.tOut[i].id == 7 and state.tOut[i].msg.cmd == "home" then got = true end end
CHECK(got, "a button (turtle 7 HOME) reaches the turtle")
CHECK(tostring(P.toast):find("^OK", 1) ~= nil, "the answer is shown: " .. tostring(P.toast))

-- the monitor's warnings reach the browser while the remote tab is running
REMOTE.alive = os.clock()
POCKET.note("TEST WARNING", "something to see", C.warn)
pumpAll()
CHECK(P.notes[1] and P.notes[1].title == "TEST WARNING", "warnings arrive on MSG")
os.queueEvent = realQ

-- remote.lua starts on the menu (pocket.lua local) and has 'menu' to come back
local src = io.open(SRC_DIR .. "/remote.lua"):read("a")
CHECK(src:find('local mode = "menu"', 1, true) and src:find('pcall(fn, "local")', 1, true), "remote.lua opens on the buttons")
local man = io.open(SRC_DIR .. "/manifest.txt"):read("a")
CHECK(man:find("\nbase pocket.lua ", 1, true) or man:find("^base pocket.lua "), "pocket.lua is installed on the base computer too (upgrade)")
