-- Fluids "ALL": Advanced Peripherals moves only a part per call. moveFluid used to stop
-- after 64 calls, so ALL of a big amount stopped half way although the storage had room.
-- Now it keeps going while something moves, and a very big move carries on at the end
-- of the action queue (other buttons are not kept waiting) until all of it is moved.
local ME, BUF = { ["minecraft:water"] = 500000 }, 0
bridgeKind = "ME"
local PER = 1000                                  -- (mB per call, like a capped transfer)
bridge = {
  exportFluid = function(f, target)
    CLOCK = CLOCK + 0.05                          -- (each call takes a game tick)
    local n = math.min(f.amount, ME[f.name] or 0, PER)
    ME[f.name] = ME[f.name] - n
    BUF = BUF + n
    return n
  end,
  importFluid = function(f, target)
    CLOCK = CLOCK + 0.05
    local n = math.min(f.amount, BUF, PER)
    BUF = BUF - n
    ME[f.name] = ME[f.name] + n
    return n
  end,
}
PERIPHS["functionalstorage:storage_controller_0"] = { types = { "functionalstorage:storage_controller", "inventory", "fluid_storage" }, obj = {
  list = function() return {} end, tanks = function() return { { name = "minecraft:water", amount = BUF } } end } }
CONFIG.me = CONFIG.me or {}
CONFIG.me.fluidBuffer = "functionalstorage:storage_controller_0"
state.actionQueue = {}
-- 200 B in one go (200 calls): all of it
runAction({ kind = "ftake", name = "minecraft:water", count = 200000 })
CHECK(BUF == 200000, "ALL of 200 B moved in one tap (moved " .. BUF .. " mB; the old 64-call limit stopped at 64 B)")
CHECK(#state.actionQueue == 0, "nothing left over")
-- a much bigger one (300 B in 500 mB calls = 600 calls = 30 s > the 20 s budget): carries on at the end of the queue
PER = 500
runAction({ kind = "ftake", name = "minecraft:water", count = 300000 })
CHECK(#state.actionQueue == 1 and BUF < 500000, "a very big move hands the rest to the queue (" .. #state.actionQueue .. ")")
local rounds = 0
while #state.actionQueue > 0 and rounds < 20 do
  rounds = rounds + 1
  runAction(table.remove(state.actionQueue, 1))
end
CHECK(BUF == 500000 and ME["minecraft:water"] == 0, "...and in the end ALL of it is moved (" .. BUF .. " mB)")
-- and back: STORE IN ME ALL
runAction({ kind = "fstore", name = "minecraft:water", count = 500000 })
while #state.actionQueue > 0 do runAction(table.remove(state.actionQueue, 1)) end
CHECK(BUF == 0 and ME["minecraft:water"] == 500000, "STORE IN ME ALL: everything back (" .. BUF .. " mB left)")
-- an empty source stops at once (no endless loop)
local c0 = CLOCK
runAction({ kind = "ftake", name = "minecraft:lava", count = 1000000 })
CHECK(#state.actionQueue == 0 and CLOCK - c0 < 1, "nothing to move -> stops at once")
