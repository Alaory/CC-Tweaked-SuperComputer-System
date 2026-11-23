-- odd peripheral answers that stopped the base (draw() is not pcall'd); found by test_fuzz_periph with other seeds
-- 1) a position with a part that is not a number: no position at all (the drone page / the MAP did arithmetic on it)
local x, y, z = parsePos({ 1, "high", 3 })
CHECK(x == nil and y == nil and z == nil, "parsePos {1, 'high', 3}: no position")
x, y, z = parsePos({ x = "10", y = 64, z = -5 })
CHECK(x == 10 and y == 64 and z == -5, "parsePos with number-like strings: still read")
-- a drone whose interface answers a half position: the drone page and the MAP draw
local fakeDrone = {
  isConnectedToDrone = function() return true end, getDronePressure = function() return 5 end,
  getDronePosition = function() return { x = 1, y = true, z = 3 } end, getAction = function() return nil end,
  isActionDone = function() return true end,
}
local dr = { name = "drone_interface_9", periph = fakeDrone, log = {} }
refreshDrone(dr)
CHECK(dr.pos == nil, "a half drone position is no position: " .. tostring(dr.pos and dr.pos.y))
-- 2) AE2 numbers that are not numbers: the AE2 page compares / divides them
dofile(SRC_DIR .. "/tools/tests/lib/fake_ae2.lua")
bridge.getUsedItemStorage = function() return true end
bridge.getTotalItemStorage = function() return { 1, 2 } end
bridge.getStoredEnergy = function() return "lots" end
bridge.getUsedFluidStorage = function() return false end
local me = fetchME()
state.me = me
CHECK(me.storage.used == nil and me.storage.max == nil and me.energy.stored == nil and me.fstorage.used == nil,
      "odd AE2 numbers are dropped (" .. tostring(me.storage.used) .. ", " .. tostring(me.storage.max) .. ")")
CHECK(me.energy.cap == 2000, "... the good ones stay")
for _, pg in ipairs({ "me", "drone", "map" }) do
  state.page = pg
  hits = {}
  local okD, errD = pcall(draw)
  CHECK(okD, "page " .. pg .. " draws with the odd answers: " .. tostring(errD))
end
