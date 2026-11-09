-- BEDROCK theme: light buttons -> white / gold / grey / status text on a button
-- is drawn DARK (readable); the selected tab is the green slot; other themes
-- keep the blue accent and draw text unchanged.
local was = THEME_NAME
CHECK(setTheme("bedrock"), "bedrock theme exists")
CHECK(C.accent == colors.green, "bedrock: green accent")
local seen
local ow = win.setTextColor
win.setTextColor = function(c) seen = c return ow(c) end
text(1, 1, "x", C.text, C.empty)
CHECK(seen == C.ink, "white text on a light button -> dark")
text(1, 1, "x", C.label, C.empty)
CHECK(seen == C.ink, "title colour on a light button -> dark")
text(1, 1, "x", C.dim, C.empty)
CHECK(seen == C.head, "grey text on a light button -> dark grey")
text(1, 1, "x", C.text, C.accent)
CHECK(seen == C.ink, "text on the green tab -> dark")
text(1, 1, "x", C.text, C.panel)
CHECK(seen == C.text, "text on a box stays white")
CHECK(PALETTE[colors.blue] ~= 0x3C8527, "the map's water colour is not changed")
setTheme("stone")
CHECK(C.accent == colors.blue and LIGHT_FG == nil, "stone: blue accent, text unchanged")
text(1, 1, "x", C.text, C.empty)
CHECK(seen == C.text, "stone: white text on a button")
win.setTextColor = ow
setTheme(was)
