-- node.lua's real build() (the turtle factory's builder) in a tiny fake world.
--   lua5.3 tools/tests/node_build.lua node.lua      (exit 1 when a check fails)
local NODE = arg[1] or "node.lua"
local FAILS = 0
local function CHECK(c, msg) if not c then FAILS = FAILS + 1 print("FAIL: " .. msg) end end
local function runBuild(MODE)
  local src = io.open(NODE):read("a")
  local a = src:find("function invSnapshot", 1, true)
  local b = src:find("function runJob", 1, true)
  local code = src:sub(a, b - 1)
  local DX, DZ = { [0] = 0, 1, 0, -1 }, { [0] = -1, 0, 1, 0 }
  local W = {}                                   -- "x,y,z" -> block {kind, inv, on, id}
  local function k(x, y, z) return x .. "," .. y .. "," .. z end
  local P = { x = 0, y = 0, z = 0, f = 0 }
  local INV = {}
  INV[1] = { name = "computercraft:wireless_modem_advanced", count = 1 }   -- (equipped in reality; here a spare is fine)
  INV[2] = { name = "computercraft:disk_drive", count = 1 }
  INV[3] = { name = "computercraft:disk", count = 1 }
  INV[4] = { name = "minecraft:diamond_pickaxe", count = 1 }
  INV[5] = { name = "minecraft:coal_block", count = 10 }                  -- MY fuel - must stay mine
  -- the parts chest east of the builder (x+1)
  W[k(1, 0, 0)] = { kind = "chest", inv = {
    { name = "computercraft:turtle_advanced", count = 1 }, { name = "computercraft:wireless_modem_advanced", count = 1 },
    { name = "advancedperipherals:geo_scanner", count = 1 }, { name = "advancedperipherals:chunk_controller", count = 1 },
    { name = "minecraft:diamond_pickaxe", count = 1 }, { name = "minecraft:coal_block", count = 16 } } }
  if MODE == "blocked" then W[k(-1, 0, 0)] = { kind = "stone" } end
  if MODE == "full" then for i = 6, 13 do INV[i] = { name = "minecraft:cobblestone", count = 64 } end end   -- 3 slots free
  local sel = 1
  local function front() return P.x + DX[P.f], P.y, P.z + DZ[P.f] end
  local function cellF() return W[k(front())] end
  local function addInv(inv, name, n, maxSlots)
    for i = 1, maxSlots do if inv[i] and inv[i].name == name and not name:find("pickaxe") and not name:find("turtle") and not name:find("disk") then inv[i].count = inv[i].count + n return true end end
    for i = 1, maxSlots do if not inv[i] then inv[i] = { name = name, count = n } return true end end
    return false
  end
  turtle = {
    select = function(i) sel = i return true end, getSelectedSlot = function() return sel end,
    getItemCount = function(i) return INV[i] and INV[i].count or 0 end,
    getItemDetail = function(i) return INV[i] and { name = INV[i].name, count = INV[i].count } or nil end,
    turnRight = function() P.f = (P.f + 1) % 4 return true end, turnLeft = function() P.f = (P.f + 3) % 4 return true end,
    detect = function() return cellF() ~= nil end, detectUp = function() return W[k(P.x, P.y + 1, P.z)] ~= nil end,
    suck = function()
      local c = cellF()
      if not (c and c.inv) then return false end
      for i, it in pairs(c.inv) do
        local slot
        for j = sel, 16 do if not INV[j] then slot = j break end end
        if not slot then for j = 1, 16 do if not INV[j] then slot = j break end end end
        if not slot then return false end
        INV[slot] = it c.inv[i] = nil return true
      end
      return false
    end,
    drop = function(n)
      local c = cellF()
      local it = INV[sel]
      if not (c and c.inv and it) then return false end
      n = math.min(n or it.count, it.count)
      if c.kind == "drive" then if it.name ~= "computercraft:disk" then return false end c.inv[1] = { name = it.name, count = 1 } it.count = it.count - 1
      elseif not addInv(c.inv, it.name, n, 16) then return false
      else it.count = it.count - n end
      if it.count == 0 then INV[sel] = nil end
      return true
    end,
    place = function()
      local it = INV[sel]
      if not it or cellF() then return false end
      local kind = it.name:find("turtle") and "turtle" or (it.name:find("disk_drive") and "drive") or "block"
      W[k(front())] = { kind = kind, inv = {}, id = (kind == "turtle") and 77 or nil }
      it.count = it.count - 1
      if it.count == 0 then INV[sel] = nil end
      return true
    end,
    dig = function()
      local c = cellF()
      if not c then return false end
      W[k(front())] = nil
      addInv(INV, c.kind == "drive" and "computercraft:disk_drive" or "x", 1, 16)
      return true
    end,
  }
  peripheral = {
    hasType = function(side, t)
      local c = (side == "front") and cellF() or nil
      if not c then return false end
      if t == "inventory" then return c.kind == "chest" or c.kind == "turtle" end
      if t == "turtle" then return c.kind == "turtle" end
      return false
    end,
    call = function(side, m)
      local c = cellF()
      if m == "list" then local l = {} for i, it in pairs(c.inv or {}) do l[i] = it end return l end
      if m == "getID" then return c.id end
      if m == "isOn" then return c.on or false end
      if m == "turnOn" or m == "reboot" then
        -- it boots: is my drive (with the floppy) next to it?
        local x, y, z = front()
        local d = W[k(x, y + 1, z)]
        c.on = true
        c.installed = d and d.kind == "drive" and d.inv[1] ~= nil
        return true
      end
    end,
  }
  function right() turtle.turnRight() end
  function left() turtle.turnLeft() end
  function up() if turtle.detectUp() then return false end P.y = P.y + 1 return true end
  function down() if W[k(P.x, P.y - 1, P.z)] then return false end P.y = P.y - 1 return true end
  function slotOf(test) for i = 1, 16 do if INV[i] and test(INV[i].name) then return i end end end
  function isDrive(n) return n == "computercraft:disk_drive" end
  function isFloppy(n) return n == "computercraft:disk" end
  function isPick(n) return n:find("_pickaxe", 1, true) ~= nil end
  function withEquipped(part, fn) return fn() end
  function sleep() end
  task = ""
  assert(load(code, "build", "t", _ENV))()
  local ok, msg = build()
  local nt = W[k(-1, 0, 0)]
    local mine, theirs = {}, {}
    for i = 1, 16 do if INV[i] then mine[INV[i].name] = (mine[INV[i].name] or 0) + INV[i].count end end
    for _, it in pairs(nt and nt.inv or {}) do theirs[it.name] = (theirs[it.name] or 0) + it.count end
    local chestLeft = 0 for _ in pairs(W[k(1, 0, 0)].inv) do chestLeft = chestLeft + 1 end
    return ok, msg, nt, mine, theirs, chestLeft, W[k(-1, 1, 0)], P
  end


local ok, msg, nt, mine, theirs, chestLeft, driveLeft, P = runBuild("ok")
CHECK(ok and msg:find("built turtle 77"), "build: " .. tostring(msg))
CHECK(nt and nt.kind == "turtle" and nt.on and nt.installed, "build: the new turtle is placed, on, and booted from the floppy")
for _, n in ipairs({ "computercraft:wireless_modem_advanced", "advancedperipherals:geo_scanner",
                     "advancedperipherals:chunk_controller", "minecraft:diamond_pickaxe" }) do
  CHECK(theirs[n] == 1, "build: the new turtle got " .. n)
end
CHECK(theirs["minecraft:coal_block"] == 16, "build: the new turtle got the 16 coal blocks (not the builder's own)")
CHECK(mine["minecraft:coal_block"] == 10, "build: the builder keeps its own 10 coal blocks")
CHECK(mine["computercraft:disk_drive"] == 1 and mine["computercraft:disk"] == 1, "build: drive + floppy taken back")
CHECK(mine["computercraft:wireless_modem_advanced"] == 1 and mine["minecraft:diamond_pickaxe"] == 1, "build: the builder keeps its kit")
CHECK(not driveLeft, "build: no drive left behind")
CHECK(chestLeft == 0, "build: the chest is empty")
CHECK(P.y == 0, "build: the builder is back down")

ok, msg, nt, mine, theirs, chestLeft = runBuild("blocked")
CHECK(not ok and msg:find("back in the chest"), "blocked: refused - " .. tostring(msg))
CHECK(chestLeft == 6, "blocked: all 6 parts back in the chest (" .. chestLeft .. ")")
CHECK(mine["minecraft:coal_block"] == 10, "blocked: the builder keeps exactly its own fuel")
ok, msg, nt, mine, theirs, chestLeft = runBuild("full")
CHECK(not ok and msg:find("not enough room"), "full inventory: refused - " .. tostring(msg))
CHECK(not nt, "full inventory: no turtle built")
CHECK(chestLeft == 6, "full inventory: all 6 parts back in the chest (" .. chestLeft .. ")")
CHECK(mine["minecraft:cobblestone"] == 512 and mine["minecraft:coal_block"] == 10, "full inventory: the builder keeps exactly its own items")
if FAILS > 0 then os.exit(1) end
print("PASS")
