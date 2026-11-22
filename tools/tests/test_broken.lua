-- PARTS BROKEN WHILE THE BASE WAS OFF (the owner: "what if a player broke parts of the system when it's offline"):
-- set up by pre_broken.lua - the monitor, me_bridge_4, a chest and data floppy #55 are gone.
CHECK(state ~= nil and draw ~= nil, "the base STARTS without its monitor (it was the one required block = a crash at every start)")
CHECK(mon.blank and monName == nil, "a blank monitor stands in")
local out0 = handleCommand("parts")
CHECK(type(out0) == "table" and table.concat(out0, " "):find("Screen: NONE", 1, true), "console parts: no screen")
for _, pg in ipairs({ "home", "inventory", "me", "turtles", "map", "system", "settings" }) do
  state.page = pg
  CHECK(safeDraw(), pg .. " draws onto the blank monitor: " .. tostring(state.drawErr))
end
-- what is gone is listed
noteNetwork(true)
local gone = {}
for _, g in ipairs(partsGone()) do gone[g.key] = g end
CHECK(gone.right and gone.me_bridge_4 and gone["minecraft:chest_9"] and gone["floppy #55"],
      "missing: the monitor, the ME Bridge, the chest, the data floppy")
CHECK(not gone.turtle_12, "a turtle that stood next to the cable is not a missing part")
CHECK(partText(gone["floppy #55"]):find("NOT saved", 1, true), "the floppy's files are not saved meanwhile: " .. partText(gone["floppy #55"]))
-- a warning only after goneAfter of THIS run (a chunk that loads late is no alarm)
local warns = 0
local oldPush = pushNote
pushNote = function(t, m, ...) if t == "WARNING" and tostring(m):find("MISSING", 1, true) then warns = warns + 1 end return oldPush(t, m, ...) end
CHECK(partsTick() == 0 and warns == 0, "no warning in the first minutes")
CLOCK = CLOCK + 620
CHECK(partsTick() == 4 and warns == 1, "after 10 min: ONE warning for all four (" .. warns .. ")")
CHECK(partsTick() == 0 and warns == 1, "... not again")
-- the monitor is put back: used at the next check
PERIPHS.right = SAVED_MON
netTick()
CHECK(not mon.blank and monName == "right", "a monitor put back is used (" .. tostring(monName) .. ")")
safeDraw()
CHECK(W == ({ SAVED_MON.obj.getSize() })[1], "the screen is rebuilt at the monitor's size")
noteNetwork(true)
CHECK(NET.gone.right == nil, "the monitor is no longer missing")
-- shown: HOME NEEDS YOU, SYSTEM > STATUS, the away report
local function screenHas(page, word)
  state.page = page
  safeDraw()
  for y = 1, H do if win.getLine(y):lower():find(word, 1, true) then return true end end
  return false
end
CHECK(screenHas("home", "part(s) missing"), "HOME: NEEDS YOU lists the missing parts")
CHECK(screenHas("system", "parts missing"), "SYSTEM > STATUS: Parts missing")
local okR, rep = pcall(AWAY.report)
CHECK(okR and table.concat((function() local t = {} for _, l in ipairs(rep or {}) do t[#t + 1] = tostring(l.t) end return t end)(), " "):find("part missing", 1, true),
      "the WHILE YOU WERE AWAY report names them")
local out = handleCommand("parts")
CHECK(type(out) == "table" and table.concat(out, " "):find("me_bridge_4", 1, true) and table.concat(out, " "):find("Screen: right", 1, true),
      "console parts: the list + the screen")
-- broken WHILE the base runs
PERIPHS.right = nil
forgetDetached("right")
CHECK(mon.blank and monName == nil and safeDraw(), "the monitor broken mid-run: the base goes on without it")
PERIPHS.right = SAVED_MON
rescanPeripherals()
CHECK(not mon.blank, "... and it is back the moment it is placed")
-- a NEW ME Bridge (another number) replaces the old one
PERIPHS.me_bridge_7 = { types = { "me_bridge" }, obj = {} }
noteNetwork(true)
noteNetwork(true)
CHECK(NET.gone.me_bridge_4 == nil, "me_bridge_4 replaced by a new ME Bridge: not missing any more")
PERIPHS.me_bridge_7 = nil
bridge = nil
-- the floppy was taken: forget it -> its files are saved again
local ok1 = saveFileSafe("pockets.dat", "{}")
CHECK(not ok1, "pockets.dat not saved while floppy #55 may come back")
handleCommand("parts forget floppy #55")
CHECK(NET.gone["floppy #55"] == nil and DATA_AWAY["pockets.dat"] == nil, "parts forget floppy #55")
CHECK(saveFileSafe("pockets.dat", "{}") == true, "... then pockets.dat is saved again")
-- kept across a restart, forgotten after 60 days
local seen = textutils.unserialize(FILES["net_seen.dat"])
CHECK(seen and seen.g and seen.g["minecraft:chest_9"], "net_seen.dat keeps the missing list")
NET.gone["minecraft:chest_9"].since = os.epoch("utc") - 61 * 86400000
noteNetwork(true)
CHECK(NET.gone["minecraft:chest_9"] == nil, "a part missing 60+ days is dropped")
handleCommand("parts forget all")
CHECK(#partsGone() == 0, "parts forget all")
-- ANOTHER PLAYER'S CARD in the Inventory Manager (they broke it and put theirs back)
refreshInventory()
CHECK(inv ~= nil and OWNER_SAVED == "Alaory", "the owner's card: used")
local im = PERIPHS.inventory_manager_3.obj
local realOwner = im.getOwner
im.getOwner = function() return "Griefer" end
local warned = 0
pushNote = function(t, m, ...) if tostring(m):find("Griefer", 1, true) then warned = warned + 1 end return oldPush(t, m, ...) end
refreshInventory()
CHECK(inv == nil and INV_FOREIGN and state.owner == "Alaory" and warned == 1, "another player's card: NOT used, one warning")
rescanPeripherals()
CHECK(inv == nil, "... and not picked up again by the next scan")
CLOCK = CLOCK + 61
rescanPeripherals()
refreshInventory()
CHECK(inv == nil and warned == 1, "checked again after 60 s: still refused, no second warning")
im.getOwner = realOwner
CLOCK = CLOCK + 61
rescanPeripherals()
refreshInventory()
CHECK(inv ~= nil and INV_FOREIGN == nil, "the owner's card back: used again")
im.getOwner = function() return "NewMe" end
handleCommand("owner new")
refreshInventory()
CHECK(inv ~= nil and OWNER_SAVED == "NewMe", "owner new: the next card is the owner's")
im.getOwner = realOwner
pushNote = oldPush
local src = io.open(SRC_DIR .. "/base_devices.lua"):read("a")
CHECK(not src:find('{ "monitor" }, true, true)', 1, true), "base_devices.lua: the monitor is not required")
