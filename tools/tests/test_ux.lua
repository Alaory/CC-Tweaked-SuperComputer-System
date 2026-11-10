-- UX: every button / tab on every page is at least 2 rows tall (1-row list
-- rows with a gap are OK: "item"), page descriptions fit the HOME buttons
-- whole, a tap 1 row / 1 column off a button still hits it (snapTouch), the
-- INVENTORY page has no OVERVIEW box and keeps a big DETAILS box.
local PAGES = { "home", "inventory", "players", "storage", "curios", "me", "drone", "access",
                "turtles", "drive", "map", "mining", "system", "events", "settings" }
local ROWS_OK = { item = true, meitem = true, dscroll = true, tsel = true, evitem = true }
local was = state.page
setTheme("bedrock")
for _, p in ipairs(PAGES) do
  state.page = p
  local ok, err = pcall(draw)
  CHECK(ok, p .. " draws (" .. tostring(err) .. ")")
  for _, h in ipairs(hits) do
    local hh = h[4] - h[2] + 1
    if hh < 2 and not ROWS_OK[h[5]] then
      CHECK(false, p .. ": 1-row button '" .. tostring(h[5]) .. "' at " .. h[1] .. "," .. h[2])
    end
  end
end
for k, v in pairs(PAGE_INFO) do CHECK(#v[2] <= 30, "description of " .. k .. " fits the HOME button") end
-- snapTouch: a tap just below a 2-row button hits it; one far away does not
hits = { { 10, 10, 19, 11, "x", 1 } }
local x, y = snapTouch(12, 12)
CHECK(x == 12 and y == 11, "tap 1 row below a button -> the button")
x, y = snapTouch(20, 10)
CHECK(x == 19 and y == 10, "tap 1 column right of a button -> the button")
x, y = snapTouch(12, 14)
CHECK(x == 12 and y == 14, "tap 3 rows away -> nothing")
x, y = snapTouch(15, 10)
CHECK(x == 15 and y == 10, "a tap on a button is never moved")
-- INVENTORY: no OVERVIEW box, DETAILS gets the room
state.page = "inventory"
local titles = {}
local oc = card
card = function(cx, cy, w, h, l) if l then titles[l] = h end return oc(cx, cy, w, h, l) end
draw()
card = oc
CHECK(not titles.OVERVIEW and not titles.EQUIPMENT, "inventory: no OVERVIEW / EQUIPMENT boxes")
CHECK((titles.DETAILS or 0) >= 12, "inventory: DETAILS at least 12 rows (" .. tostring(titles.DETAILS) .. ")")
state.page = was
-- every hit kind is handled ONCE in base_input.lua (the DRIVE page's turtle list
-- and the drone picker were both "dsel": the drone picker never worked)
local src = io.open(SRC_DIR .. "/base_input.lua"):read("a")
local seenKind = {}
for k in src:gmatch('elseif h%[5%] == "([%w_]+)" then') do
  CHECK(not seenKind[k], "hit kind '" .. k .. "' handled twice in base_input.lua")
  seenKind[k] = true
end
-- the drone picker: tapping Drone 2's tab selects it
state.page = "drone"
local keys = {}
for _, k in ipairs(droneOrder) do keys[#keys + 1] = k end
if #keys >= 2 then
  state.drone = drones[keys[1]]
  draw()
  local tab
  for _, h in ipairs(hits) do if h[5] == "dsel" and h[6] == keys[2] then tab = h end end
  CHECK(tab, "drone picker shows Drone 2")
  if tab then handleTouch(tab[1] + 1, tab[2] + 1) end
  CHECK(state.drone == drones[keys[2]], "tapping Drone 2 selects it")
end
state.page = was
