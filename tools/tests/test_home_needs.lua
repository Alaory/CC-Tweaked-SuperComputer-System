-- HOME: NEEDS YOU shows its problems (the owner's screenshot: "1 open" with NO row, only "+2 more - open
-- their pages" - the panel is sized for exactly the problems, the rows were counted one short)
local function screen()
  hits = {}
  draw()
  local out = {}
  for y = 1, H do out[#out + 1] = (win.getLine(y)) end
  return table.concat(out, "\n")
end
local function needsN(n)
  state.diskLow = nil
  droneOrder, drones = {}, {}
  if n >= 1 then state.diskLow = "DISK ALMOST FULL: disk12/test.dat not saved" end
  for i = 1, n - 1 do
    local k = "d" .. i
    droneOrder[#droneOrder + 1] = k
    drones[k] = { label = "Drone " .. i, mission = { state = "failed", title = "Trip " .. i, err = "blocked" }, log = {} }
  end
end
local W0, H0 = W, H
local tooSmall
for _, sz in ipairs({ { 100, 40 }, { 121, 50 }, { 164, 81 }, { 200, 100 } }) do
  W, H = sz[1], sz[2]
  win = window.create(mon, 1, 1, W, H, false)
  applyPalette(win)
  state.page = "home"
  for _, n in ipairs({ 1, 3, 12 }) do
    needsN(n)
    local s = screen()
    if s:find("MONITOR TOO SMALL", 1, true) then tooSmall = true end
    if not tooSmall then
    CHECK(s:find(n .. " open", 1, true), W .. "x" .. H .. ", " .. n .. " problem(s): the header says " .. n .. " open")
    -- (the drone problems come first in the list, the disk one last)
    local first = n > 1 and "Trip 1 failed" or "Disk almost full"
    CHECK(s:find(first, 1, true), W .. "x" .. H .. ", " .. n .. " problem(s): the first problem is SHOWN")
    local seen, shown = {}, 0
    for i in s:gmatch("Trip (%d+) failed") do if not seen[i] then seen[i] = true shown = shown + 1 end end
    if s:find("Disk almost full", 1, true) then shown = shown + 1 end
    local more = tonumber(s:match("%+(%d+) more %- open their pages"))
    CHECK(shown + (more or 0) == n and shown >= 1, W .. "x" .. H .. ": " .. shown .. " shown + " .. tostring(more or 0) ..
          " more = " .. n .. " problems")
    if n <= 3 then CHECK(more == nil, W .. "x" .. H .. ": " .. n .. " problem(s) all shown, no '+more'") end
    end
    tooSmall = nil
  end
end
W, H = W0, H0
win = window.create(mon, 1, 1, W, H, false)
applyPalette(win)
state.diskLow, droneOrder, drones = nil, {}, {}
