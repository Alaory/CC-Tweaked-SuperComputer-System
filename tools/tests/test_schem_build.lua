-- SCHEMATIC BUILD - WHERE + WHICH WAY (the owner: "I have not tested the schematic program at all ... make it intuitive,
-- like if I want to rotate a schematic in a direction"): DW.lookDir / DW.origin (in front of you for every way you look,
-- centred / corner on a place), "facing <dir>" / "turn left|right|around", the turned preview (DW.topAt = what DW.plan
-- builds, every quarter turn), torches & co. after the solid blocks, the console (schem preview / build), chat
-- ($drone build <name> -> turn right -> yes; the spot stays where it was asked for), the BUILD card (preview, TURN LEFT
-- / RIGHT).
state.owner = "Alaory"
DW.notReady = function() return nil end                       -- (no drones here: the plan is what is tested)
DW.save = function() end

-- an L-shaped, NOT symmetric schematic 3 wide (x) x 2 high x 2 deep (z):
--   y0: north row (z0) stone stone stone, south row (z1) planks . torch   y1: one stone above (1, z0)
local s = { size = { x = 3, y = 2, z = 2 }, palette = { { name = "minecraft:stone", props = {} },
            { name = "minecraft:oak_planks", props = {} }, { name = "minecraft:torch", props = {} } },
            blocks = { { 0, 0, 0, 1 }, { 1, 0, 0, 1 }, { 2, 0, 0, 1 }, { 0, 0, 1, 2 }, { 2, 0, 1, 3 }, { 1, 1, 0, 1 } } }
SCHEM.cache["ell"] = { s = s, path = "schematics/ell.nbt" }

-- 1) which way you look
CHECK(DW.lookDir(0) == 2 and DW.lookDir(90) == 3 and DW.lookDir(180) == 0 and DW.lookDir(270) == 1 and DW.lookDir(-90) == 1
      and DW.lookDir(359) == 2 and DW.lookDir(44) == 2 and DW.lookDir(46) == 3, "yaw -> N E S W (0 south, 90 west, 180 north)")

-- 2) the turn words
CHECK(DW.turnWords({ "facing", "east" }, 1, 0) == 90 and DW.turnWords({ "face", "W" }, 1, 0) == 270, "facing east = 90, west = 270")
CHECK(DW.turnWords({ "turn", "right" }, 1, 90) == 180 and DW.turnWords({ "turn", "left" }, 1, 0) == 270 and
      DW.turnWords({ "turn", "around" }, 1, 90) == 270 and DW.turnWords({ "rot", "450" }, 1, 0) == 90, "turn right / left / around / rot")
CHECK(DW.turnWords({ "clear" }, 1, 0) == nil, "other words are no turn")
CHECK(DW.turnText(90):find("turned right", 1, true) and DW.turnText(90):find("faces east", 1, true) and
      DW.turnText(0):find("as saved", 1, true), "turn in words: " .. DW.turnText(90))

-- 3) IN FRONT OF YOU, every way you look: 2 ahead, centred, bottom at your feet
local function stand(x, y, z, yaw)
  state.players = { { name = "Alaory", p = { x = x + 0.5, y = y, z = z + 0.5, yaw = yaw }, dim = DRONE_DIM } }
end
local function box(pl, rot)
  local w, d = DW.footprint(s, rot)
  return pl.ox, pl.oz, pl.ox + w - 1, pl.oz + d - 1
end
stand(100, 64, 100, 0)                                           -- looking SOUTH
local pl = DW.where(s, {}, 1, "Alaory", 0)
local x0, z0, x1, z1 = box(pl, 0)
CHECK(pl and pl.how == "front" and z0 == 102 and x0 == 99 and x1 == 101 and pl.oy == 64, "looking south: 2 ahead, centred, at your feet (" ..
      fmtPos(pl.ox, pl.oy, pl.oz) .. ")")
stand(100, 64, 100, 180)                                         -- NORTH
pl = DW.where(s, {}, 1, "Alaory", 0)
x0, z0, x1, z1 = box(pl, 0)
CHECK(z1 == 98 and x0 == 99, "looking north: its near (south) edge 2 ahead (" .. z1 .. ")")
stand(100, 64, 100, 270)                                         -- EAST
pl = DW.where(s, { "facing", "east" }, 1, "Alaory", 0)
x0, z0, x1, z1 = box(pl, 90)
CHECK(pl.rot == 90 and x0 == 102 and z0 <= 100 and z1 >= 100 and z1 - z0 == 2, "looking east, facing east: 2 ahead, turned 3 deep")
stand(100, 64, 100, 90)                                          -- WEST
pl = DW.where(s, { "here", "turn", "left" }, 1, "Alaory", 0)
x0, z0, x1, z1 = box(pl, 270)
CHECK(pl.rot == 270 and x1 == 98, "looking west: its near (east) edge 2 ahead (" .. x1 .. ")")
CHECK(pl.text:find("in front of you to the west", 1, true) and pl.text:find("turned left", 1, true), "said in words: " .. pl.text)

-- 4) a place / x y z = the GROUND block: it stands on it (corner / centred)
pl = DW.where(s, { "10", "64", "10" }, 1, "Alaory", 0)
CHECK(pl.how == "corner" and pl.ox == 10 and pl.oy == 65 and pl.oz == 10, "x y z = north-west corner, ON the block")
pl = DW.where(s, { "10", "64", "10", "centered", "facing", "south", "clear" }, 1, "Alaory", 0)
CHECK(pl.how == "center" and pl.ox == 9 and pl.oy == 65 and pl.oz == 9 and pl.rot == 180 and pl.clear, "centered + facing south + clear (" ..
      fmtPos(pl.ox, pl.oy, pl.oz) .. ")")

-- 5) the PREVIEW shows what DW.plan builds, every quarter turn (the top block of every column)
DW.select("ell")
CHECK(DW.sel and DW.sel.top, "the top view is read with the schematic")
for rot = 0, 270, 90 do
  local plan = DW.plan(s, 0, 0, 0, rot)
  local top, topY = {}, {}
  for _, p in ipairs(plan.place) do
    local k = p.x .. "," .. p.z
    if not topY[k] or p.y > topY[k] then topY[k], top[k] = p.y, p.item end
  end
  local w, d = DW.footprint(s, rot)
  local same = true
  for x = 0, w - 1 do for z = 0, d - 1 do
    if DW.topAt(DW.sel, rot, x, z) ~= top[x .. "," .. z] then same = false end
  end end
  CHECK(same, "preview = the build, turned " .. rot)
end
-- turned right: the file's NORTH side (the stone row) is on the EAST
local plan = DW.plan(s, 0, 0, 0, 90)
local east = 0
for _, p in ipairs(plan.place) do if p.item == "minecraft:stone" and p.x == 1 then east = east + 1 end end
CHECK(east == 4, "facing east: the north row (stone) ends up on the east side (" .. east .. "/4)")

-- 6) torches & co. after the solid blocks (one placed first had nothing to hang on)
local order = {}
for i, p in ipairs(DW.plan(s, 0, 0, 0, 0).place) do order[p.item] = order[p.item] or i end
local lastSolid = 0
for i, p in ipairs(DW.plan(s, 0, 0, 0, 0).place) do if p.item ~= "minecraft:torch" then lastSolid = i end end
CHECK(order["minecraft:torch"] > lastSolid, "the torch comes after every solid block, also the one a layer up")

-- 7) the console
stand(100, 64, 100, 0)
local out = table.concat(handleCommand("schem preview ell 10 64 10 facing south centered") or {}, "\n")
CHECK(out:find("turned around", 1, true) and out:find(fmtPos(9, 65, 9), 1, true) and out:find("6 blocks", 1, true), "schem preview: " .. out)
CHECK(DW.job == nil, "preview builds nothing")
out = table.concat(handleCommand("schem build ell turn right") or {}, "\n")
CHECK(DW.job and DW.job.rot == 90 and DW.job.z == 102, "schem build <name> turn right = in front of you, turned (" .. out .. ")")
CHECK(out:find("come last", 1, true), "it says what comes last / that blocks face the default way")
DW.job = nil

-- 8) chat: name -> turn -> yes; the spot stays where it was asked for
local told = {}
local tell0 = chatTell
chatTell = function(n, t) told[#told + 1] = t end
local function chat(t) told = {} handleChat({ name = "Alaory", uuid = state.ownerUuid, msg = "$" .. CONFIG.chat.command .. " " .. t }) return table.concat(told, " | ") end
local r = chat("build")
CHECK(r:find("look the way it should go", 1, true), "chat build: how to (" .. r .. ")")
r = chat("build ell")
CHECK(DW.chatPend and DW.chatPend.alaory and r:find("build yes", 1, true) and r:find("in front of you to the south", 1, true), "chat build ell: where + how to start (" .. r .. ")")
CHECK(DW.job == nil, "nothing built before yes")
stand(500, 70, 500, 90)                                          -- walked off and turned
r = chat("build turn right")
CHECK(DW.chatPend.alaory.pl.rot == 90 and r:find("turned right", 1, true), "turn right: " .. r)
r = chat("build facing west")
CHECK(DW.chatPend.alaory.pl.rot == 270, "facing west = 270")
r = chat("build yes")
CHECK(DW.job and DW.job.rot == 270 and DW.job.y == 64 and DW.job.z >= 101 and DW.job.z <= 103 and DW.job.x <= 100,
      "yes: built where it was asked for (not where you went), turned (" .. r .. ")")
CHECK(DW.chatPend.alaory == nil, "the waiting one is gone")
r = chat("build stop")
CHECK(DW.job == nil, "chat build stop")
told = {}
handleChat({ name = "Stranger", uuid = "x", msg = "$" .. CONFIG.chat.command .. " build ell" })
CHECK(DW.chatPend.stranger == nil and table.concat(told, " "):find("Only", 1, true), "only the owner can build")
chatTell = tell0

-- 9) the BUILD card: preview, where, TURN LEFT / RIGHT
DW.view = DW.view or {}
DW.view.schems = { "ell" }
DW.ui.rot, DW.ui.at = 0, 0
stand(100, 64, 100, 0)
state.page = "work"
local function screen()
  hits = {}
  draw()
  local o = {}
  for y = 1, H do o[#o + 1] = (MONITOR.getLine(y)) end
  return table.concat(o, "\n")
end
local scr = screen()
CHECK(scr:find("SEEN FROM ABOVE", 1, true) and scr:find("@", 1, true) and scr:find("IN FRONT OF YOU", 1, true) and
      scr:find("TURN LEFT", 1, true) and scr:find("TURN RIGHT", 1, true) and scr:find("2 ahead", 1, true) == nil, "the card: preview with you, where, turn buttons")
local function tapHit(name)
  for _, h in ipairs(hits) do if h[5] == name then handleTouch(h[1], h[2]) return true end end
end
CHECK(tapHit("dwrotl") and DW.ui.rot == 270, "TURN LEFT = 270")
screen()
CHECK(tapHit("dwrot") and tapHit("dwrot") and DW.ui.rot == 90, "TURN RIGHT twice = 90")
scr = screen()
CHECK(scr:find("turned right", 1, true), "the card says how it is turned")
state.page = "home"
