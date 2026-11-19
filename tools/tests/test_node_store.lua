-- NODE.LUA OFF THE COMPUTER (the owner: "move node.lua to external storage - it is just an update and has no
-- purpose" - 117 KB of a 1 MB computer). The base keeps the turtle program in memory and one stored copy on a
-- STORAGE HELPER (else a data floppy); `upgrade` fetches it straight there (manifest group "node").
CODE_SIZE = 800000
local REMOTE, DOWN, CALLS = {}, {}, 0
STORE.call = function(id, req)
  CALLS = CALLS + 1
  local h = REMOTE[id]
  if not h or DOWN[id] then return nil, "no answer" end
  if req.op == "put" then h[req.name] = req.data return { ok = true, free = 900000 }
  elseif req.op == "get" then local o = {} for _, n in ipairs(req.names) do o[n] = h[n] end return { ok = true, files = o }
  elseif req.op == "del" then h[req.name] = nil return { ok = true }
  elseif req.op == "list" then return { ok = true, files = {} } end
  return nil, "bad op"
end
REMOTE[120] = {}
STORE.helpers = { [120] = { id = 120, free = 900000, cap = 1000000 } }
local name = "nodex.lua"
CONFIG.turtles.codeFile = name
local here = fs.combine(BASE_DIR or "", name)
local src = io.open(SRC_DIR .. "/node.lua"):read("a")
FILES[here] = src
pcall(fs.delete, TT.WHERE_FILE)
CODE = nil
-- 1) left by an older upgrade: loaded, then moved off the computer
TT.codeLoad(false, true)
CHECK(CODE and CODE.text and #CODE.text > 1000, "the turtle program is loaded from the computer first")
local ver1 = CODE.ver
local freeBefore = fs.getFreeSpace("/")
local okO, where = TT.codeOffload()
CHECK(okO and where == "store:120/" .. name, "moved onto the storage helper: " .. tostring(where))
CHECK(not FILES[here], "... and deleted from the computer")
CHECK(fs.getFreeSpace("/") - freeBefore > 100000, "the computer has ~" .. math.floor((fs.getFreeSpace("/") - freeBefore) / 1024) .. " KB more free")
local w = TT.codeWhere()
CHECK(w and w.from == "old" and #REMOTE[120][name] < #src, "the record says: an old leftover (fetch the newest), stored SHRUNK (" ..
      #REMOTE[120][name] .. " of " .. #src .. " bytes)")
-- 2) the next start: read back from the helper (only where the base may wait for an answer)
CODE = nil
CALLS = 0
TT.codeLoad()
CHECK(CODE == nil and CALLS == 0, "without canWait (the comms worker) the helper is NOT asked")
TT.codeLoad(false, true)
CHECK(CODE and CODE.ver == ver1, "the map worker reads it back from the helper - the same program (" .. tostring(CODE and TT.verName(CODE.ver)) .. ")")
CALLS = 0
TT.codeLoad()
TT.codeLoad(false, true)
CHECK(CALLS == 0, "loaded once: no more helper calls every 30 s")
-- the install floppy still gets it
CHECK(type(CODE.text) == "string" and CODE.pieces and #CODE.pieces > 0, "the program is in memory for updates / the install floppy")
-- 3) a node.lua dropped onto the computer by hand: the new one is used and moved off too
FILES[here] = src .. "\n-- a newer version\nlocal NEWER = 1\n"
TT.codeLoad(false, true)
CHECK(CODE.ver ~= ver1, "a dropped node.lua is used")
local ver2 = CODE.ver
TT.codeOffload()
w = TT.codeWhere()
CHECK(not FILES[here] and w.from == "dropped" and REMOTE[120][name], "... moved off the computer as well (" .. tostring(w.from) .. ")")
CODE = nil
TT.codeLoad(false, true)
CHECK(CODE and CODE.ver == ver2, "... and that one comes back from the helper")
-- 4) upgrade: the newest from GitHub goes straight to the helper, never onto the computer
local realLoadfile = loadfile
local gh = src .. "\n-- from github\n"
FILES[fs.combine(BASE_DIR or "", "upgrade.lua")] = FILES[fs.combine(BASE_DIR or "", "upgrade.lua")] or "-- stub"
loadfile = function(p, ...)
  if tostring(p):find("upgrade.lua", 1, true) then
    return function(o)
      CHECK(o.fetch == name and o.group == "node", "fetched from the manifest group 'node'")
      return true, gh, "abc1234"
    end
  end
  return realLoadfile(p, ...)
end
local realHttp = http
http = http or {}
local okF, msgF = TT.fetchCode()
CHECK(okF and tostring(msgF):find("store:120", 1, true) and TT.codeWhere().from == "github" and not FILES[here],
      "upgrade: node.lua from GitHub stored on the helper (" .. tostring(msgF) .. ")")
CHECK(CODE and CODE.ver ~= ver2, "... and the turtles get that one")
local okF2, msgF2 = TT.fetchCode()
CHECK(okF2 and tostring(msgF2):find("up to date", 1, true), "the same again: up to date")
loadfile = realLoadfile
http = realHttp
-- 5) no storage helper: a data floppy (never the install floppy)
STORE.helpers = {}
addDrive("drive_5", "disk5")
fs.open("disk5/base_data", "w").close()
local okD, whereD = TT.codeStore(src, "dropped")
CHECK(okD and whereD == "disk5/" .. name, "no helper: on a data floppy (" .. tostring(whereD) .. ")")
CHECK(REMOTE[120][name] == nil, "... the old copy on the helper is deleted")
CODE = nil
TT.codeLoad(false, true)
CHECK(CODE ~= nil, "read back from the floppy")
-- the manifest: node.lua is NOT in the base computer's files any more
local man = io.open(SRC_DIR .. "/manifest.txt"):read("a")
CHECK(not man:find("\nbase node.lua", 1, true) and not man:find("\nslim:base node.lua", 1, true) and man:find("\nnode node.lua", 1, true),
      "manifest: node.lua is in group 'node', not 'base' (upgrade never puts it on the computer)")
CONFIG.turtles.codeFile = nil
