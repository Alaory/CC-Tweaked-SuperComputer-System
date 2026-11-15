-- A turtle whose Geo Scanner / pickaxe disappears: one WARNING with its last job, where
-- it is and its free slots (to find out how survey turtles end up with empty inventories).
local SEQ = 0
local function report(id, m)
  SEQ = SEQ + 1
  m.n = os.epoch("utc") + SEQ
  m.t = m.t or "status"
  m.sig = TT.sign(CONFIG.turtles.key, m.t, m.n)
  TT.receive(id, m)
end
local notes = {}
local push0 = pushNote
pushNote = function(kind, msg) notes[#notes + 1] = tostring(msg) end
state.turtles = {}
report(40, { label = "Scout40", task = "idle", gear = "L=modem R=chunky,pick,fuel,scanner", pos = { x = 1, y = 70, z = 2 }, freeSlots = 12 })
report(40, { label = "Scout40", task = "surveying 3/64", pos = { x = 500, y = 90, z = 2 } })
report(40, { label = "Scout40", task = "idle", gear = "L=modem R=chunky,fuel", pos = { x = 510, y = 90, z = 5 }, freeSlots = 0 })
local all = table.concat(notes, " | ")
CHECK(all:find("LOST its Geo Scanner", 1, true) and all:find("LOST its pickaxe", 1, true), "both lost tools reported (" .. all .. ")")
CHECK(all:find("surveying 3/64", 1, true) and all:find("510 90 5", 1, true) and all:find("0 free slots", 1, true),
      "with the last job, the spot and the free slots")
CHECK(state.turtles[40].freeSlots == 0, "free slots kept for the turtle")
notes = {}
report(40, { label = "Scout40", task = "idle", gear = "L=modem R=chunky,fuel", pos = { x = 510, y = 90, z = 5 } })
CHECK(#notes == 0, "not again while it stays the same")
pushNote = push0
