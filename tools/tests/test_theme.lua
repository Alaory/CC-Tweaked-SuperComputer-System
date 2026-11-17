-- CONTROL ROOM look: every theme only changes the FRAME (page, panel, lines, dim text,
-- titles) - the map / status colours stay the same; an old saved theme name falls back to
-- teal; drawing is CLIPPED (the owner: "fix text going out of bound"): nothing leaves the
-- screen or the panel it belongs to, cut text ends in "~".
local was = THEME_NAME
CHECK(#THEME_ORDER >= 5, "several themes")
local fixedSlots = { colors.white, colors.brown, colors.blue, colors.cyan, colors.green, colors.yellow,
                     colors.orange, colors.red, colors.pink, colors.purple, colors.lime }
local ref
for _, name in ipairs(THEME_ORDER) do
  CHECK(setTheme(name), name .. " exists")
  if not ref then
    ref = {}
    for _, c in ipairs(fixedSlots) do ref[c] = PALETTE[c] end
  else
    for _, c in ipairs(fixedSlots) do
      CHECK(PALETTE[c] == ref[c], name .. ": the map / status colour " .. c .. " is the same in every theme")
    end
  end
  CHECK(PALETTE[colors.black] ~= PALETTE[colors.gray], name .. ": a panel differs from the page")
end
CHECK(C.accent == colors.cyan and C.label == colors.lightBlue and C.line == colors.magenta, "colour jobs")
CHECK(not setTheme("bedrock"), "the old themes are gone (a saved one falls back to teal at start)")
-- clipping
local writes = {}
local ow, osp = win.write, win.setCursorPos
local cx, cy = 1, 1
win.setCursorPos = function(x, y) cx, cy = x, y return osp(x, y) end
win.write = function(s) writes[#writes + 1] = { cx, cy, s } return ow(s) end
CLIP = nil
text(W - 3, 1, "ABCDEFGH", C.text, C.bg)
local last = writes[#writes]
CHECK(last and last[1] + #last[3] - 1 <= W, "text never goes past the right edge (" .. tostring(last and last[3]) .. ")")
CHECK(last and last[3]:sub(-1) == "~", "cut text ends in ~")
writes = {}
local ix, iy, iw = panel(10, 10, 20, 6, "BOX")
text(ix, iy, ("x"):rep(60), C.text, C.panel)
for _, w in ipairs(writes) do
  CHECK(w[1] >= 10 and w[1] + #w[3] - 1 <= 29, "nothing is drawn outside the panel (" .. w[1] .. "+" .. #w[3] .. ")")
end
writes = {}
text(ix, 40, "outside", C.text, C.panel)
CHECK(#writes == 0, "a row outside the panel is not drawn")
CLIP = nil
fill(W - 2, 1, 50, 1, C.bg)
local f = writes[#writes]
CHECK(f and f[1] + #f[3] - 1 <= W, "fill never goes past the edge")
win.write, win.setCursorPos = ow, osp
CLIP = nil
-- kv: a long value never pushes the key off / out
writes = {}
win.write = function(s) writes[#writes + 1] = s return ow(s) end
kv(1, 1, 30, "Turtle factory", "off (SETTINGS > FACTORY: keep this many turtles)")
local total = 0
for _, s in ipairs(writes) do total = total + #s end
CHECK(writes[1] and writes[1]:find("Turtl", 1, true) and total <= 30, "kv keeps the key and fits the width (" .. total .. ")")
win.write = ow
setTheme(was)
-- button labels are shortened by words, not cut
CHECK(fitLabel("DRONE: FLY ME THERE", 14) == "FLY ME THERE", "a prefix goes first (" .. fitLabel("DRONE: FLY ME THERE", 14) .. ")")
CHECK(fitLabel("FIND LOST NEAR BASE", 16) == "FIND LOST NEAR", "then words from the end (" .. fitLabel("FIND LOST NEAR BASE", 16) .. ")")
CHECK(fitLabel("STOP", 10) == "STOP", "a short label stays")
-- cut text ends in "~" (a "." looked like the end of a sentence); a value loses its
-- "(hint)" / " - note" before anything is cut
CHECK(trunc("Cobblestone", 6) == "Cobbl~", "trunc ends in ~ (" .. trunc("Cobblestone", 6) .. ")")
CHECK(shorten("off (SETTINGS > FACTORY: keep this many turtles)", 10) == "off", "shorten drops the (hint)")
CHECK(shorten("none - the base stops when you leave", 10) == "none", "shorten drops the - note")
CHECK(shorten("short", 10) == "short", "shorten leaves what fits")
writes = {}
win.write = function(s) writes[#writes + 1] = s return ow(s) end
kv(1, 1, 30, "Factory", "off (SETTINGS > FACTORY: keep this many turtles)")
win.write = ow
CHECK(writes[1] == "Factory" and writes[#writes] == "off", "kv: short key whole, value without its hint (" ..
      tostring(writes[1]) .. " / " .. tostring(writes[#writes]) .. ")")
-- big letters: M N W are 5 pixels wide (3 cells); every width bigW says is what big() draws
CHECK(bigW("N") == 3 and bigW("M") == 3 and bigW("W") == 3 and bigW("I") == 2, "M N W are 3 cells wide, I 2")
for _, s in ipairs({ "INVENTORY", "12:59", "BASE", "1.2M" }) do
  CHECK(big(1, 1, s, C.text, C.bg) == bigW(s), "big() and bigW() agree for " .. s)
end
-- message boxes: every line of the message is ON the screen (a line drawn one row too low
-- landed under the timer bar - one-line warnings showed as empty boxes in game)
do
  state.notes = {}
  local ua = USER_ACTION
  USER_ACTION = true
  pushNote("WARNING", "Turtle 12 is out of fuel", C.warn, 60)
  pushNote("WARNING", "Supply entangled:tile_3: justdirethings:xp_fluid_source - AE2 has no xp_fluid_source or the tank takes none", C.warn, 60)
  USER_ACTION = ua
  state.page = "home"
  hits = {}
  draw()
  local all = {}
  for y = 1, H do all[#all + 1] = (MONITOR.getLine(y)) end
  local s = table.concat(all, "\n")
  CHECK(s:find("Turtle 12 is out of fuel", 1, true), "a one-line message is shown in its box")
  CHECK(s:find("takes none", 1, true), "the LAST line of a longer message is shown too")
  state.notes = {}
end
