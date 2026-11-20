-- THE MAP SHOWS WHAT EACH TURTLE IS DOING (the owner: "should the turtles be this scattered around?" - every
-- turtle ever known was the same green T at its LAST spot: offline / lost ones looked like working ones)
local function T(f)
  local t = { id = 1, pos = { x = 0, y = 70, z = 0 }, task = "idle", lastSeen = os.clock() }
  for k, v in pairs(f or {}) do t[k] = v end
  return t
end
local mapping, cm = mapMarker(T({ task = "survey: spot 3/9" }))
local busy, cb = mapMarker(T({ task = "going home" }))
local idle, ci = mapMarker(T({ task = "idle" }))
local off, co = mapMarker(T({ lastSeen = os.clock() - 99999, task = "survey: spot 3/9" }))
local stuck, cs = mapMarker(T({ stuck = "blocked" }))
CHECK(mapping == "T" and cm == C.good, "mapping = green T")
CHECK(busy == "T" and cb ~= cm and cb ~= ci, "another job (going home, fuel, a trip) = its own colour")
CHECK(idle == "T" and ci ~= cm, "idle = its own colour")
CHECK(off == "x" and co ~= cm, "OFFLINE = x (its last known spot), even if its last task was mapping")
CHECK(stuck == "!" and cs == C.bad, "stuck = red !")
-- the theme's grey slots are repainted: never used for a marker
for _, c in ipairs({ cm, cb, ci, co, cs }) do
  CHECK(c ~= colors.gray and c ~= colors.lightGray and c ~= C.panel and c ~= C.bg, "marker colour is not a theme slot")
end
-- lost ones (MISSING) are not drawn; the others are
local HM = CONFIG.drone.home or { x = 0, y = 64, z = 0 }
state.turtles = { [1] = T({ id = 1, task = "survey: a", pos = { x = HM.x + 20, y = 70, z = HM.z } }),
                  [2] = T({ id = 2, task = "survey: b", missing = os.epoch("utc"), pos = { x = HM.x - 20, y = 70, z = HM.z } }) }
state.page = "map"
state.tSel = nil
local text0, greens = text, 0
text = function(x, y, s, fg, bg) if s == "T" and bg == C.good then greens = greens + 1 end return text0(x, y, s, fg, bg) end
draw()
text = text0
CHECK(greens == 2, "the mapping turtle is drawn, the MISSING one is not (green T: " .. greens .. " - 1 on the map + 1 in the legend)")
