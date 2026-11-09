-- SEARCH PARTY: all free turtles meet at the base, travel together to each lost
-- turtle, look around (Geo Scanner); a switched-off one they SEE -> the rescuer is
-- sent to its exact block; one that wakes up (its area loaded) = found; one that
-- is gone (deleted by a crash) -> MISSING; then everyone home.
local HOME = { x = 0, y = 64, z = 0 }
CONFIG.drone.home = HOME
state.turtles, state.tOut = {}, {}
TT.party = nil
local function T(id, f)
  local t = { id = id, label = "T" .. id, log = {}, lastN = 0, fuel = 50000, pos = { x = 0, y = 64, z = 0 }, task = "idle",
              lastSeen = CLOCK, seenEpoch = os.epoch("utc"), home = { x = id, y = 64, z = 0 } }
  for k, v in pairs(f or {}) do t[k] = v end
  state.turtles[id] = t
  return t
end
T(1) T(2) T(3)
T(9, { rescuerRole = true, gear = "L=x R=y,drive,floppy,pick,fuel,scanner" })
local A = T(21, { lastSeen = CLOCK - 9999, pos = { x = 1300, y = 40, z = 0 } })      -- switched off, still there
local B = T(22, { lastSeen = CLOCK - 9999, pos = { x = 1300, y = 64, z = 200 } })    -- wakes up when the area loads
local C = T(23, { lastSeen = CLOCK - 9999, pos = { x = -1400, y = 64, z = 50 } })    -- deleted
local OFF = { [21] = true, [22] = true, [23] = true }
local rescues, goals, homes = {}, {}, {}
local send0 = TT.send
TT.send = function(id, cmd, args, ...)
  local t = state.turtles[id]
  if cmd == "goto" and t then
    goals[#goals + 1] = { id = id, x = args[1], z = args[3] }
    t.pos = { x = args[1], y = args[2], z = args[3] }               -- (gets there at once)
    t.task = "idle"
  elseif cmd == "findturtles" and t then
    local seen = {}
    if math.abs(t.pos.x - 1300) + math.abs(t.pos.z - 0) <= 40 then seen[1] = { x = 1300, y = 40, z = 0 } end
    TT.partySeen(id, seen)
  elseif cmd == "rescue" then
    rescues[#rescues + 1] = { by = id, target = args[1], x = args[2], y = args[3], z = args[4] }
  elseif cmd == "home" then
    homes[id] = true
  end
  return send0(id, cmd, args, ...)
end
local ok, msg = TT.partyStart()
CHECK(ok, "party starts: " .. tostring(msg))
CHECK(TT.party and #TT.party.members == 3, "3 members (not the rescuer)")
CHECK(TT.available()[1] == nil, "members get no survey work while in the party")
local spread = false
for step = 1, 400 do
  CLOCK = CLOCK + 2
  for id, t in pairs(state.turtles) do if not OFF[id] then t.lastSeen = CLOCK end end
  -- B wakes up once a party member is near its spot
  if OFF[22] then
    for _, id in ipairs((TT.party or {}).members or {}) do
      local p = state.turtles[id].pos
      if math.abs(p.x - 1300) + math.abs(p.z - 200) <= 60 then OFF[22] = nil B.lastSeen = CLOCK end
    end
  end
  -- side by side while travelling: two goals of one hop 24 blocks apart
  if TT.party and TT.party.stage == "travel" and TT.party.goals then
    local g1, g2 = TT.party.goals[1], TT.party.goals[2]
    if g1 and g2 and math.abs(math.sqrt((g1.x - g2.x) ^ 2 + (g1.z - g2.z) ^ 2) - 24) < 1 then spread = true end
  end
  TT.partyTick()
  if not TT.party then break end
end
TT.send = send0
CHECK(TT.party == nil, "the party finished")
CHECK(spread, "they travel side by side, 24 blocks apart")
local r = rescues[1]
CHECK(r and r.by == 9 and r.target == 21 and r.x == 1300 and r.y == 40 and r.z == 0,
      "A seen switched off: the RESCUER is sent to its exact block")
local foundB = false
for _, l in ipairs(B.log) do if tostring(l.msg or l):find("is back", 1, true) then foundB = true end end
CHECK(foundB or TT.online(B), "B woke up when the party came: found")
CHECK(C.missing, "C was deleted: MISSING after the search")
CHECK(not A.missing and not B.missing, "A and B are not marked missing")
CHECK(homes[1] and homes[2] and homes[3], "everyone is sent home at the end")
CHECK(not state.turtles[1].party, "members are free again")
-- nobody lost: refused
local ok2, msg2 = TT.partyStart()
CHECK(not ok2 or #TT.lostList() > 0, "no lost turtle: no party (" .. tostring(msg2) .. ")")
TT.party = nil

-- TWO finds while the rescuer is busy: the second WAITS for it (before: "no
-- rescuer could go - get it yourself"), then the rescuer is sent there; a find
-- that is gone by then (broken / deleted) is dropped
do
  state.turtles, state.tOut, TT.rescueQ = {}, {}, {}
  T(9, { rescuerRole = true, gear = "L=x R=y,drive,floppy,pick,fuel,scanner" })
  local X = T(31, { lastSeen = CLOCK - 9999, pos = { x = 1100, y = 40, z = 0 } })
  local Y = T(32, { lastSeen = CLOCK - 9999, pos = { x = 1500, y = 40, z = 0 } })
  local Z = T(33, { lastSeen = CLOCK - 9999, pos = { x = 1900, y = 40, z = 0 } })
  local sent = {}
  local s0 = TT.send
  TT.send = function(id, cmd, args, ...) if cmd == "rescue" then sent[#sent + 1] = args[1] end return s0(id, cmd, args, ...) end
  TT.party = { targets = { 31, 32, 33 }, ti = 1, members = {}, goals = {}, seenAt = {}, located = {}, found = {},
               foundSet = {}, missing = {}, done = {} }
  TT.partySeen(1, { { x = 1100, y = 40, z = 0 } })
  CHECK(sent[1] == 31, "first find: the rescuer goes at once")
  state.turtles[9].task = "rescue"                       -- busy with it
  TT.partySeen(1, { { x = 1500, y = 40, z = 0 } })
  TT.partySeen(1, { { x = 1900, y = 40, z = 0 } })
  CHECK(#sent == 1 and #TT.rescueQ == 2, "busy rescuer: the other finds wait in line (" .. #TT.rescueQ .. ")")
  TT.party = nil
  state.turtles[9].task = "idle"
  X.missing = os.epoch("utc")                            -- the first one turned out to be gone
  Y.missing = os.epoch("utc")                            -- (and this one broken by a player meanwhile)
  for _ = 1, 3 do CLOCK = CLOCK + 2 TT.partyTick() end
  CHECK(sent[2] == 33, "rescuer free: the next one in line (a gone one skipped) (" .. tostring(sent[2]) .. ")")
  CHECK(#TT.rescueQ == 0, "the line is empty")
  TT.send = s0
  -- the HOME quick action and the pocket start / call back the party
  state.turtles[9].task = "idle"
  T(1)
  Z.missing = nil
  local okA, msgA = POCKET.act("party", {})
  CHECK(okA and TT.party, "FIND LOST (HOME / pocket) starts the search party: " .. tostring(msgA))
  local okB = POCKET.act("party", {})
  CHECK(okB and TT.party == nil, "tapped again: the party is called back")
  local st = POCKET.status()
  CHECK(st.lost == 1, "the pocket is told how many are lost (" .. tostring(st.lost) .. ")")
  TT.party, TT.rescueQ = nil, {}
end

-- turtles that went silent AT the base (you picked them up while testing): no
-- rescue, no search party, listed on the FLEET card, FORGET THEM forgets them
do
  state.turtles, state.tOut, TT.rescueQ, TT.party = {}, {}, {}, nil
  CONFIG.drone.home = { x = 0, y = 64, z = 0 }
  T(9, { rescuerRole = true, gear = "L=x R=y,drive,floppy,pick,fuel,scanner" })
  T(1)
  local atB = T(41, { lastSeen = CLOCK - 99999, seenEpoch = os.epoch("utc") - 9999999, pos = { x = 10, y = 64, z = -20 } })
  local far = T(42, { lastSeen = CLOCK - 99999, seenEpoch = os.epoch("utc") - 9999999, pos = { x = 1900, y = 64, z = 0 } })
  local lost = {}
  for _, t in ipairs(TT.lostList()) do lost[#lost + 1] = t.id end
  CHECK(#lost == 1 and lost[1] == 42, "the search party only looks for the far one (" .. table.concat(lost, ",") .. ")")
  local sent = {}
  local s0 = TT.send
  TT.send = function(id, cmd, args, ...) if cmd == "rescue" then sent[#sent + 1] = args[1] end return s0(id, cmd, args, ...) end
  TT.startedAt = (TT.startedAt or 0) - 99999
  for _ = 1, 5 do CLOCK = CLOCK + 2 state.turtles[9].lastSeen = CLOCK state.turtles[1].lastSeen = CLOCK TT.patrolTick() end
  TT.send = s0
  local toAtB = false
  for _, id in ipairs(sent) do if id == 41 then toAtB = true end end
  CHECK(not toAtB, "no rescue sent to the one silent at the base")
  CHECK(sent[1] == 42, "(the rescuer does go to the far lost one: " .. table.concat(sent, ",") .. ")")
  local _, _, _, why = TT.status(atB)
  CHECK(tostring(why):find("at the base", 1, true), "its card says it is at the base (" .. tostring(why) .. ")")
  CHECK(#TT.lostAtBase() == 1, "listed as silent at the base")
  CHECK(TT.forgetAtBase() == 1 and state.turtles[41] == nil and state.turtles[42] ~= nil, "FORGET THEM: only that one forgotten")
end

-- the owner's range: lost within 1024 blocks of the base are ignored, further out not
do
  state.turtles, TT.party = {}, nil
  CONFIG.drone.home = { x = 0, y = 64, z = 0 }
  CONFIG.turtles.atBaseRange = nil                    -- (the default)
  local n1 = T(51, { lastSeen = CLOCK - 99999, pos = { x = 1000, y = 64, z = -800 } })
  local n2 = T(52, { lastSeen = CLOCK - 99999, pos = { x = 1100, y = 64, z = 0 } })
  CHECK(TT.atBase(n1) and not TT.atBase(n2), "default: within 1024 blocks = ignored, 1100 away = looked for")
  local l = TT.lostList()
  CHECK(#l == 1 and l[1].id == 52, "rescue / search list: only the far one")
end

-- the lost turtle is UNDER GROUND: the members never go down to it (they tried,
-- could not - no digging - and every trip failed); they stand on the surface
do
  state.turtles, state.tOut, TT.party, TT.rescueQ = {}, {}, nil, {}
  CONFIG.drone.home = { x = 0, y = 40, z = 0 }           -- (the drone home is down inside the base)
  T(9, { rescuerRole = true }) T(1, { pos = { x = 0, y = 70, z = 0 } }) T(2, { pos = { x = 1, y = 70, z = 0 } })
  local U = T(61, { lastSeen = CLOCK - 99999, pos = { x = 1500, y = 12, z = 0 } })
  local get0 = MAP.get
  MAP.get = function(x, z) return 66, "minecraft:grass_block" end
  local lowest = 999
  local s0 = TT.send
  TT.send = function(id, cmd, args, ...)
    if cmd == "goto" then lowest = math.min(lowest, args[2]) end
    return s0(id, cmd, args, ...)
  end
  TT.partyStart()
  for _ = 1, 40 do
    CLOCK = CLOCK + 25
    for _, id in ipairs({ 1, 2, 9 }) do state.turtles[id].lastSeen = CLOCK end
    TT.partyTick()
    if not TT.party then break end
  end
  TT.send = s0
  CHECK(lowest >= 69, "members stay above the ground (lowest goal Y " .. lowest .. ", ground 66) - not down at Y 12 / 40")
  -- the members could not move at all (every trip failed): the lost turtle is NOT marked missing
  CHECK(not U.missing, "nobody got there: NOT marked missing")
  CHECK(TT.party == nil, "the party ended (could not get there) instead of hanging on")
  MAP.get = get0
end

-- goal heights: ground UNKNOWN (a hillside nobody mapped) -> up in the air, never
-- at the members' own height (they sat pressed against the slope); a cliff 4 blocks
-- away -> above the cliff, not against it
do
  local get0, ov0 = MAP.get, MAP.getOverview
  MAP.get = function() return nil end
  MAP.getOverview = function() return nil end
  CHECK(TT.partyY(500, 500, 70) >= 140, "unknown ground: up in the air (" .. TT.partyY(500, 500, 70) .. ")")
  MAP.getOverview = function() return 110 end
  CHECK(TT.partyY(500, 500, 70) >= 120, "only the rough chunk height (110): well above it (" .. TT.partyY(500, 500, 70) .. ")")
  MAP.get = function(x, z) if x == 504 then return 130 end return 70 end
  CHECK(TT.partyY(500, 500, 70) >= 133, "a cliff 4 blocks away (130): above the cliff (" .. TT.partyY(500, 500, 70) .. ")")
  MAP.get, MAP.getOverview = get0, ov0
end
