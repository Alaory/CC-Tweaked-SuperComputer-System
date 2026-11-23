-- THE UPDATE PROGRAMS (the owner: "check the update programs that update the turtles and other stuff"): a COPY turtle and
-- its twin share ONE disk - the base never sends the update to both at the same moment (they would write the same
-- program file at once); a turtle without its twin still updates.
local function mk(id, ver)
  state.turtles[id] = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 5000, task = "idle", ver = ver,
    pos = { x = 0, y = 70, z = 0 }, lastSeen = os.clock(), seenEpoch = os.epoch("utc") }
end
state.turtles = {}
mk(23, "old") mk(100023, "old") mk(31, "old")
CODE = { ver = "new", pieces = { "a", "b" }, text = "ab" }
TT.sending = {}
TT.updateForce = os.clock() + 600
AWAY = nil
state.tOut = {}
TT.updateTick()
CHECK(TT.sending[31], "a turtle without a twin gets it")
CHECK((TT.sending[23] and 1 or 0) + (TT.sending[100023] and 1 or 0) == 1, "of a copy and its twin only ONE gets it at a time")
-- the first one has it: the other one is next
local first = TT.sending[23] and 23 or 100023
local other = first == 23 and 100023 or 23
state.turtles[first].ver = "new"
CLOCK = CLOCK + 3
TT.updateTick()
CHECK(TT.sending[other], "then the other one")
-- miners: the same in a team
local src = io.open(SRC_DIR .. "/base_mining.lua"):read("a")
CHECK(src:find("busyTwin", 1, true), "mining updates: one of a copy and its twin at a time")
