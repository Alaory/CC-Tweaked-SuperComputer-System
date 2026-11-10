-- upgrade.lua against a fake disk + a fake GitHub (lua5.3 tools/tests/upgrade_sim.lua <repo root>)
local ROOT = arg[1] or "."
local FAILS, N = 0, 0
local function CHECK(c, m) N = N + 1 if not c then FAILS = FAILS + 1 print("FAIL: " .. m) end end
local function readReal(p) local h = io.open(ROOT .. "/" .. p, "rb") if not h then return nil end local s = h:read("a") h:close() return s end

local DISK, CAP
local function used() local n = 0 for _, v in pairs(DISK) do n = n + #v end return n end
fs = {
  exists = function(p) return DISK[p] ~= nil end, isDir = function() return false end,
  getDir = function(p) return p:match("^(.*)/") or "" end,
  combine = function(a, b) return (a == "" and b) or (a .. "/" .. b) end,
  getFreeSpace = function() return CAP - used() end,
  delete = function(p) DISK[p] = nil end,
  move = function(a, b) DISK[b] = DISK[a] DISK[a] = nil end,
  open = function(p, mode)
    if mode:sub(1, 1) == "r" then
      if not DISK[p] then return nil end
      local s = DISK[p]
      return { readAll = function() return s end, close = function() end }
    end
    local buf = {}
    return { write = function(s) buf[#buf + 1] = s end,
             close = function()
               local s = table.concat(buf)
               if used() - #(DISK[p] or "") + #s > CAP then error("Out of space") end
               DISK[p] = s end }
  end,
}
local function ser(t) local o = {} for k, v in pairs(t) do o[#o + 1] = string.format("[%q]=%q", k, tostring(v)) end return "{" .. table.concat(o, ",") .. "}" end
textutils = { serialize = ser, unserialize = function(s) local f = load("return " .. s) return f and f() end,
              urlEncode = function(s) return s end }
os.queueEvent = function() end
os.pullEvent = function() end
local SHA = "abcdef1234567"
local BROKEN
-- main and the work branch are two versions; MAIN_EMPTY = main has no file list yet (before the merge)
local SHA_MAIN = "1111111aaaaaaa"
local MAIN_EMPTY, ASKED, FROM = false, {}, {}
http = { get = function(o)
  local url = type(o) == "table" and o.url or o
  if url:find("api.github.com", 1, true) then
    local br = url:match("/commits/(.+)$")
    ASKED[#ASKED + 1] = br
    return { readAll = function() return ((br == "main") and SHA_MAIN or SHA) .. "\n" end, close = function() end }
  end
  local sha = url:match("githubusercontent%.com/[^/]+/[^/]+/(%x+)/")
  CHECK(sha == SHA or sha == SHA_MAIN, "files come from an exact version: " .. url)
  FROM[sha or "?"] = (FROM[sha or "?"] or 0) + 1
  if sha == SHA_MAIN and MAIN_EMPTY then return nil, "404" end
  local name = url:match("/" .. sha .. "/(.+)$")
  local s = readReal(name)
  if not s then return nil, "404" end
  if name == BROKEN then s = s:sub(1, #s - 10) end
  return { readAll = function() return s end, close = function() end }
end }
pocket = nil

local src = readReal("upgrade.lua")
local function upgrade(args)
  local log = {}
  local fn = assert(load(src, "=upgrade.lua", "t", _ENV))
  local ok, n = fn({ args = args, dir = "base", log = function(s) log[#log + 1] = s end })
  return ok, n, table.concat(log, "\n")
end
-- what upgrade installs by default: the SLIM copy (dist/)
local function slimOf(p) return readReal("dist/" .. p) end
local function fresh(cap, full)
  DISK, CAP = {}, cap or 1048576
  -- an older install: every file, two changed, the owner's config
  for line in readReal("manifest.txt"):gmatch("[^\n]+") do
    local g, p = line:match("^(%S+) (%S+)")
    if g == "base" then DISK[(p == "startup.lua") and p or ("base/" .. p)] = full and readReal(p) or slimOf(p) end
  end
  DISK["base/base_ui_core.lua"] = "-- old\n" .. DISK["base/base_ui_core.lua"]:sub(1, 30000)
  DISK["base/base_me.lua"] = nil                              -- (a missing file = new)
  DISK["base/base_config.lua"] = "CONFIG = { mine = true }"
end

fresh()
local ok, n, log = upgrade({ "check" })
CHECK(not ok and DISK["base/base_me.lua"] == nil, "check: nothing written\n" .. log)
CHECK(log:find("base_ui_core.lua") and log:find("base_me.lua (new)", 1, true), "check lists the changed files\n" .. log)
ok, n, log = upgrade({})
CHECK(ok and n == 2, "2 files updated\n" .. log)
CHECK(DISK["base/base_me.lua"] == slimOf("base_me.lua") and DISK["base/base_ui_core.lua"] == slimOf("base_ui_core.lua"),
      "the new files are the exact SLIM copies")
CHECK(#DISK["base/base_me.lua"] < #readReal("base_me.lua") * 0.85, "slim = clearly smaller")
CHECK(DISK["base/base_config.lua"] == "CONFIG = { mine = true }", "base_config.lua not touched")
CHECK(DISK["base/base_ui_core.lua.new"] == nil, "no temp file left")
ok, n, log = upgrade({})
CHECK(not ok and log:find("up to date"), "second run: up to date\n" .. log)

-- a cut download: NOTHING written
fresh()
BROKEN = "dist/base_me.lua"
local before = DISK["base/base_ui_core.lua"]
ok, n, log = upgrade({})
CHECK(not ok and DISK["base/base_ui_core.lua"] == before and DISK["base/base_me.lua"] == nil, "broken download: nothing changed\n" .. log)
BROKEN = nil

-- not enough room: refused, nothing written
fresh()
CAP = used() + 20000
ok, n, log = upgrade({})
CHECK(not ok and log:find("Not enough room"), "too little space: refused\n" .. log)
CHECK(DISK["base/base_me.lua"] == nil, "too little space: nothing written")

-- tight: room for the growth but not for a temp copy -> old out, new in
fresh()
local need = #slimOf("base_me.lua") + (#slimOf("base_ui_core.lua") - #DISK["base/base_ui_core.lua"])
CAP = used() + need + 9000
ok, n, log = upgrade({})
CHECK(ok and DISK["base/base_ui_core.lua"] == slimOf("base_ui_core.lua"), "tight space: still updated\n" .. log)

-- a computer with the FULL files (installed by hand / an older upgrade): made slim
fresh(nil, true)
local before = used()
ok, n, log = upgrade({})
CHECK(ok and n >= 38 and used() < before - 150000, "full files -> slim: " .. tostring(n) .. " files, " ..
      math.floor((before - used()) / 1024) .. " KB freed")
-- upgrade full: the commented files (and it stays so); upgrade slim: back
ok, n, log = upgrade({ "full" })
CHECK(ok and DISK["base/base_me.lua"] == readReal("base_me.lua"), "upgrade full: the commented files\n" .. log)
ok, n, log = upgrade({})
CHECK(not ok and log:find("up to date"), "...and it stays full\n" .. log)
ok, n, log = upgrade({ "slim" })
CHECK(ok and DISK["base/base_me.lua"] == slimOf("base_me.lua"), "upgrade slim: back to slim")

-- the pocket: only pocket.lua (+ upgrade.lua)
DISK, CAP = {}, 1048576
pocket = {}
local fnP = assert(load(src, "=upgrade.lua", "t", _ENV))
ok, n = fnP({ args = {}, dir = "", log = function() end })
local names = {}
for k in pairs(DISK) do names[#names + 1] = k end
table.sort(names)
CHECK(ok and table.concat(names, ",") == "pocket.lua,upgrade.dat,upgrade.lua", "pocket gets pocket.lua + upgrade.lua: " .. table.concat(names, ","))
CHECK(DISK["pocket.lua"] == slimOf("pocket.lua"), "the pocket gets the slim pocket.lua")
pocket = nil

-- WHICH BRANCH: main first; while main has no file list yet (before the merge) the work
-- branch; a branch you chose (upgrade branch <name>) is the only one asked
do
  fresh()
  ASKED, FROM, MAIN_EMPTY = {}, {}, false
  local okM = upgrade({})
  CHECK(okM and ASKED[1] == "main" and #ASKED == 1 and (FROM[SHA] or 0) == 0, "after the merge: everything comes from main (" .. table.concat(ASKED, ",") .. ")")
  fresh()
  ASKED, FROM, MAIN_EMPTY = {}, {}, true
  local okF, _, logF = upgrade({})
  CHECK(okF and ASKED[1] == "main" and ASKED[2] and ASKED[2]:find("claude/", 1, true),
        "before the merge (main has no file list): the work branch is used (" .. table.concat(ASKED, ",") .. ")")
  CHECK(DISK["base/base_map.lua"] == slimOf("base_map.lua"), "... and the files are installed from it")
  fresh()
  upgrade({ "branch", "mybranch" })
  ASKED, FROM, MAIN_EMPTY = {}, {}, false
  upgrade({})
  CHECK(#ASKED == 1 and ASKED[1] == "mybranch", "a branch you chose is the only one asked (" .. table.concat(ASKED, ",") .. ")")
  MAIN_EMPTY = false
end

print((FAILS == 0 and "PASS" or "FAIL") .. " (" .. N .. " checks, " .. FAILS .. " failed)")
os.exit(FAILS == 0 and 0 or 1)
