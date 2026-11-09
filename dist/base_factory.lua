


















FACTORY = { job = nil, builder = nil, chest = nil, fails = 0, last = nil }
local FILE = "factory.dat"

local function cfg(k, default)
local f = CONFIG.factory
local v
if type(f) == "table" then v = f[k] end
if v == nil then return default end
return v
end
FACTORY.cfg = cfg

local function save()
saveFileSafe(FILE, serialSmall({ job = FACTORY.job, builder = FACTORY.builder, chest = FACTORY.chest,
fails = FACTORY.fails, last = FACTORY.last, built = FACTORY.built }))
end
FACTORY.save = save
do
if fs.exists(FILE) then
local h = fs.open(FILE, "r")
local t = h and textutils.unserialize(h.readAll() or "")
if h then h.close() end
if type(t) == "table" then
FACTORY.job, FACTORY.builder, FACTORY.chest = t.job, t.builder, t.chest
FACTORY.fails, FACTORY.last, FACTORY.built = t.fails or 0, t.last, t.built
end
end
end


function FACTORY.parts()
return {
{ name = cfg("turtle", "computercraft:turtle_advanced"), count = 1, what = "Advanced Turtle" },
{ name = cfg("modem", "computercraft:wireless_modem_advanced"), count = 1, what = "Ender Modem" },
{ name = cfg("geo", "advancedperipherals:geo_scanner"), count = 1, what = "Geo Scanner" },
{ name = cfg("chunky", "advancedperipherals:chunk_controller"), count = 1, what = "Chunky upgrade (Chunk Controller)" },
{ name = cfg("pick", "minecraft:diamond_pickaxe"), count = 1, what = "diamond pickaxe" },
{ name = cfg("fuel", "minecraft:coal_block"), count = tonumber(cfg("fuelCount", 16)) or 16, what = "fuel" },
}
end


local HINT = {
["computercraft:turtle_advanced"] = "7 gold ingots around an Advanced Computer, a chest below it",
["computercraft:computer_advanced"] = "7 gold ingots around redstone, a glass pane below it",
["computercraft:wireless_modem_advanced"] = "8 gold ingots around an Eye of Ender",
["minecraft:diamond_pickaxe"] = "3 diamonds on top, 2 sticks below the middle",
["minecraft:coal_block"] = "9 coal",
}

function FACTORY.hint(name) return HINT[name] end





local function filled(v)
if type(v) == "table" then
for _, x in pairs(v) do if filled(x) then return true end end
return false
end
if type(v) == "number" then return v ~= 0 end
if type(v) == "string" then return v ~= "" end
return v == true
end
local function special(it)
if type(it) ~= "table" then return false end
if filled(it.enchantments) then return true end
for _, key in ipairs({ "nbt", "components" }) do
local t = it[key]
if type(t) == "table" then
for k, v in pairs(t) do
local kk = tostring(k):lower()
local mine = kk:find("enchant", 1, true) or kk:find("custom_name", 1, true) or kk:find("display", 1, true)
or kk:find("computer", 1, true) or kk:find("upgrade", 1, true) or kk:find("label", 1, true)
or (kk:find("damage", 1, true) and not kk:find("max", 1, true))
if mine and filled(v) then return true end
end
end
end
return false
end
FACTORY.special = special


local function meCount(name)
if not bridge then return 0 end
local ok, it = callx(bridge, "getItem", { name = name })
if ok and type(it) == "table" then return tonumber(it.amount or it.count) or 0 end
return 0
end
local function meCraftable(name)
if not bridge then return false end
for _, fn in ipairs({ "isItemCraftable", "isCraftable" }) do
if type(bridge[fn]) == "function" then
local ok, r = pcall(bridge[fn], { name = name })
if ok then return r and true or false end
end
end
local ok, it = callx(bridge, "getItem", { name = name })
return ok and type(it) == "table" and it.isCraftable and true or false
end


function FACTORY.check()
local rows, missing = {}, {}
for _, p in ipairs(FACTORY.parts()) do
local have = meCount(p.name)
local craftable = have < p.count and meCraftable(p.name)
local ok = have >= p.count or craftable
rows[#rows + 1] = { part = p, have = have, craftable = craftable, ok = ok }
if not ok then missing[#missing + 1] = p end
end
return rows, missing
end


function FACTORY.fleet()
local n = 0
for _, t in pairs(state.turtles) do if not t.missing then n = n + 1 end end
return n
end

local function builderTurtle()
local id = tonumber(FACTORY.builder)
if not id then
for _, t in pairs(state.turtles) do if t.rescuerRole then id = t.id end end
end
return id and state.turtles[id]
end
FACTORY.builderTurtle = builderTurtle


local function chestList()
if not FACTORY.chest or not peripheral.isPresent(FACTORY.chest) then return nil end
local ok, list = pcall(peripheral.call, FACTORY.chest, "list")
if ok and type(list) == "table" then return list end
end

local function setStep(step, note)
local j = FACTORY.job
if not j then return end
j.step, j.t = step, os.epoch("utc")
if note then j.note = note end
save()
os.queueEvent("inv_update")
end
local function fail(why)

local j = FACTORY.job
if j and j.exported and FACTORY.chest and bridge then
for name, n in pairs(j.exported) do
if n > 0 then pcall(transfer, bridge, { "importItem" }, FACTORY.chest, { name = name, count = n }) end
end
end
FACTORY.fails = (FACTORY.fails or 0) + 1
FACTORY.last = { t = os.epoch("utc"), ok = false, msg = why }
FACTORY.job = nil
FACTORY.waitUntil = os.clock() + 1800
save()
if sysLog then sysLog("Factory: " .. why, "WARNING") end
pushNote("WARNING", "Turtle factory: " .. why, C.warn)
end


function FACTORY.blocked()
local target = tonumber(cfg("target", 0)) or 0
if target <= 0 then return "off (SETTINGS > FACTORY: keep this many turtles)" end
if FACTORY.fleet() >= target then return "fleet complete (" .. FACTORY.fleet() .. "/" .. target .. ")" end
if not bridge then return "no ME Bridge" end
if not FACTORY.chest then return "no factory chest set - type  factory chest" end
if not peripheral.isPresent(FACTORY.chest) then return "the factory chest " .. FACTORY.chest .. " is not on the cable" end
local b = builderTurtle()
if not b then return "no builder turtle - type  factory builder <id>  (or give a turtle the RESCUER role)" end
if not TT.online(b) then return b.label .. " (builder) is offline" end
if (FACTORY.fails or 0) >= 3 then return "stopped after 3 failed builds - type  factory build  to try again" end
if not b.home then return b.label .. " (builder) has no home - its home must be next to the factory chest" end
return nil
end


local lastTick = -100
function FACTORY.tick()
if os.clock() - lastTick < 10 then return end
lastTick = os.clock()
local j = FACTORY.job
if not j then
if FACTORY.waitUntil and os.clock() < FACTORY.waitUntil then return end
if FACTORY.blocked() then return end
local b = builderTurtle()
if b.task and b.task ~= "idle" then return end

if not (b.home and b.pos and b.pos.x and b.pos.x == b.home.x and b.pos.y == b.home.y and b.pos.z == b.home.z) then
if not b.home then FACTORY.homeless = true return end
if not FACTORY.sentHome or os.clock() - FACTORY.sentHome > 120 then
FACTORY.sentHome = os.clock()
TT.send(b.id, "home", {}, true)
end
return
end
FACTORY.homeless = nil
FACTORY.job = { step = "parts", t = os.epoch("utc"), builder = b.id }
save()
j = FACTORY.job
end
if j.step == "parts" then
local rows, missing = FACTORY.check()
if #missing > 0 then
local names = {}
for _, p in ipairs(missing) do names[#names + 1] = p.what end
FACTORY.job = nil
FACTORY.waitUntil = os.clock() + 1800
FACTORY.lastMissing = missing
save()
if not FACTORY.toldMissing or os.clock() - FACTORY.toldMissing > 3600 then
FACTORY.toldMissing = os.clock()
pushNote("WARNING", "Turtle factory: AE2 has no pattern (and none in stock) for: " .. table.concat(names, ", ") ..
" - type  factory  on the computer for the list", C.warn)
end
return
end
FACTORY.lastMissing = nil

for _, r in ipairs(rows) do
if r.have < r.part.count then
local ok, err = craftME(r.part.name, r.part.count - r.have)
if not ok then return fail("AE2 could not start crafting " .. r.part.what .. ": " .. tostring(err)) end
end
end
setStep("crafting", "AE2 is crafting the parts")
elseif j.step == "crafting" then
local ready = true
for _, p in ipairs(FACTORY.parts()) do
if meCount(p.name) < p.count then ready = false end
end
if ready then
setStep("export")
elseif os.epoch("utc") - (j.t or 0) > 1800000 then
fail("the parts were not crafted within 30 minutes (resources missing? crafting CPU busy?)")
end
elseif j.step == "export" then
local list = chestList()
if not list then return fail("cannot read the factory chest " .. tostring(FACTORY.chest)) end
if next(list) then

local hasTurtle = false
for _, it in pairs(list) do if tostring(it.name):find("computercraft:turtle", 1, true) then hasTurtle = true end end
if not hasTurtle then return fail("the factory chest is not empty - it must only be used by the factory") end
else
j.exported = {}
for _, p in ipairs(FACTORY.parts()) do


local okI, it = callx(bridge, "getItem", { name = p.name })
if okI and special(it) then
save()
return fail("the " .. p.what .. " in your ME system looks like your OWN one (enchanted, renamed or used) - " ..
"not taken. Keep a plain one in stock (or let AE2 craft one) and take yours out of the network")
end
local filter = { name = p.name, count = p.count }
if okI and type(it) == "table" and it.fingerprint then filter.fingerprint = it.fingerprint end
local ok, r = transfer(bridge, { "exportItem" }, FACTORY.chest, filter)
local moved = ok and numOf(r) or 0
j.exported[p.name] = moved
if moved < p.count then
save()
return fail("could not put " .. p.what .. " into the factory chest (" .. tostring(moved) .. "/" .. p.count .. ")")
end
end
end
local b = state.turtles[j.builder]
if not (b and TT.online(b)) then return fail("the builder turtle is offline") end
TT.send(b.id, "build", {})
setStep("building", "the builder is putting the turtle together")
elseif j.step == "building" then
if os.epoch("utc") - (j.t or 0) > 600000 then
fail("the builder did not finish within 10 minutes - look at it (its log on the TURTLES tab)")
end
end
end


function FACTORY.result(id, ok, msg)
local j = FACTORY.job
if not j or j.builder ~= id then return end
if not ok then return fail("the builder: " .. tostring(msg)) end
local newId = tonumber(tostring(msg):match("built turtle (%d+)"))
FACTORY.job = nil
FACTORY.fails = 0
FACTORY.built = (FACTORY.built or 0) + 1
FACTORY.last = { t = os.epoch("utc"), ok = true, msg = msg, id = newId }
FACTORY.waitUntil = os.clock() + 120
save()
if sysLog then sysLog("Factory: " .. tostring(msg), "DONE") end
pushNote("DONE", "Turtle factory: " .. tostring(msg) .. " - it installs itself and reports in a moment", C.good)
end


function FACTORY.statusLine()
local j = FACTORY.job
if j then
local what = { parts = "checking the parts", crafting = "AE2 is crafting the parts",
export = "putting the parts into the chest", building = "the builder is at work" }
return "building turtle " .. (FACTORY.fleet() + 1) .. ": " .. (what[j.step] or j.step), C.good
end
local why = FACTORY.blocked()
if why then return why, (why:find("^off") or why:find("^fleet complete")) and C.dim or C.warn end
if FACTORY.lastMissing then return "waiting for AE2 patterns - type  factory", C.warn end
if FACTORY.waitUntil and os.clock() < FACTORY.waitUntil then return "next try in a moment", C.dim end
return "ready", C.good
end
