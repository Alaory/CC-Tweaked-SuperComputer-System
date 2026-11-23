-- PACKED VOICE FILES (the owner: "if this is a compression why not use it on the voice add-on too"): the voice files
-- (823 KB slim) are installed PACKED - on a data floppy as <name>.luz (the bytes), on a storage helper as
-- <name>.luz.b64 (store.lua keeps text) - and unpacked when they load. A plain copy left from before goes; a plain
-- copy alone still loads; a broken packed copy says so.
CONFIG.voice = CONFIG.voice or {}
local realExists = fs.exists
local HIDE = {}
for _, f in ipairs(VOICE_FILES) do HIDE[f] = true end
fs.exists = function(p) if HIDE[tostring(p):gsub("^/", "")] then return false end return realExists(p) end
local function put(p, t) local h = fs.open(p, "wb") h.write(t) h.close() end
local function get(p) local h = fs.open(p, "rb") if not h then return nil end local s = h.readAll() h.close() return s end
local function real(p) local h = io.open(SRC_DIR .. "/" .. p, "rb") local s = h:read("a") h:close() return s end
addDrive("drive_7", "disk7") put("disk7/base_data", "data")
addDrive("drive_8", "disk8") put("disk8/base_data", "data")
addDrive("drive_9", "disk9") put("disk9/base_data", "data")
addDrive("drive_10", "disk10") put("disk10/base_data", "data")
if dataPathReset then dataPathReset() end
-- no storage helpers first
local S0 = { helpers = STORE.helpers, find = STORE.find, write = STORE.write, read = STORE.read, delete = STORE.delete, usable = STORE.usable }
STORE.helpers = {}
STORE.find = function() return STORE.helpers end
-- the download (upgrade.lua fetch mode): the real files from dist/ - packed when the base asks for it (o.inflate)
local lf0 = loadfile
local unpackOK = true
loadfile = function(path, ...)
  if tostring(path):find("upgrade.lua", 1, true) then
    return function(o)
      local slim = real("dist/" .. o.fetch)
      if o.inflate then
        local z = real("dist/z/" .. o.fetch:gsub("%.lua$", ".luz"))
        local okU, text = pcall(o.inflate, z)
        if not okU or text ~= slim then unpackOK = false end
        return true, slim, "test", z
      end
      return true, slim, "test"
    end
  end
  return lf0(path, ...)
end

-- 1) onto a data floppy, packed: a plain copy there from before goes
put("disk8/voice_talk3.lua", real("dist/voice_talk3.lua"))
local said = {}
local okU, msg = voiceUpdate(function(l) said[#said + 1] = l end)
CHECK(okU and unpackOK, "voice update with packed files: works (" .. tostring(msg) .. ")\n" .. table.concat(said, "\n"))
local packedN, plainN, bytes, slimBytes = 0, 0, 0, 0
for _, f in ipairs(VOICE_FILES) do
  local p, packed = addonPath(f)
  if p and packed then packedN = packedN + 1 bytes = bytes + #get(p) end
  if p and not packed then plainN = plainN + 1 end
  slimBytes = slimBytes + #real("dist/" .. f)
end
CHECK(packedN == #VOICE_FILES and plainN == 0, "every voice file is on a floppy PACKED (" .. packedN .. " packed, " .. plainN .. " plain)")
CHECK(not realExists("disk8/voice_talk3.lua"), "the plain copy from before is gone")
CHECK(bytes < slimBytes * 0.45, "a third of the space: " .. math.floor(bytes / 1024) .. " KB instead of " .. math.floor(slimBytes / 1024) .. " KB")
local p3 = addonPath("voice_talk3.lua")
CHECK(get(p3) == real("dist/z/voice_talk3.luz"), "the floppy holds the packed bytes as they are (" .. tostring(p3) .. ")")
CHECK(VOICE and VOICE.loop and VOICE.packs and VOICE.packs["voice_lonely.lua"], "the whole chain loads from the packed files")
local ans = tostring(VOICE.converse(knownOwner and knownOwner() or "Alaory", "tell me a joke", true))
CHECK(#ans > 10, "... and it talks: " .. ans)
-- the same version again: nothing written
local okS, _, same = installAddon("voice_talk3.lua", "voice", function() end, true)
CHECK(okS and same == "same", "the same packed version again: up to date")

-- 2) a broken packed copy: a clear reason, nothing else breaks
local keep = get(p3)
put(p3, keep:sub(1, 300))
VOICE = nil
loadVoiceChain()
local okB, whyB = loadAddon("voice_talk3.lua")
CHECK(not okB and tostring(whyB):find("broken", 1, true) and tostring(whyB):find("voice update", 1, true),
      "a broken packed copy: says so (" .. tostring(whyB) .. ")")
put(p3, keep)

-- 3) a plain copy alone (installed by an older base) still loads
fs.delete(p3)
put("disk7/voice_talk3.lua", real("dist/voice_talk3.lua"))
VOICE = nil
local okP = loadVoiceChain()
CHECK(okP and VOICE.packs["voice_talk3.lua"], "a plain copy still loads")
-- ... and the next update packs it
installAddon("voice_talk3.lua", "voice", function() end, true)
local pz, pk = addonPath("voice_talk3.lua")
CHECK(pk and not realExists("disk7/voice_talk3.lua"), "the next update packs it (" .. tostring(pz) .. ")")

-- 4) on a STORAGE HELPER: base64 text (store.lua keeps text), the floppy copy goes, read back and loaded
local MEM = {}
STORE.helpers = { [7] = { id = 7, free = 900000 } }
STORE.usable = function(h) return h ~= nil end
STORE.write = function(path, text) MEM[path] = text return true end
STORE.read = function(path) return MEM[path] end
STORE.delete = function(path) MEM[path] = nil return true end
-- (an older plain copy on the floppy: an update goes to the helper - an up-to-date floppy copy is left alone)
local zp = addonPath("voice_talk3.lua")
fs.delete(zp)
put("disk7/voice_talk3.lua", real("dist/voice_talk3.lua") .. "\n-- older\n")
local okH, whereH = installAddon("voice_talk3.lua", "voice", function() end, true)
CHECK(okH and whereH == "store:7/voice/voice_talk3.luz.b64" and MEM[whereH] and not MEM[whereH]:find("[^%w%+/=]"),
      "on a helper: packed + base64 text (" .. tostring(whereH) .. ")")
CHECK(MEM[whereH] and #MEM[whereH] < #real("dist/voice_talk3.lua") * 0.5, "... still about half the plain size or less")
CHECK(not addonPath("voice_talk3.lua"), "... the floppy copy is gone")
VOICE = nil
local okR = loadVoiceChain(nil, true)
CHECK(okR and VOICE.packs["voice_talk3.lua"], "... and it loads from the helper")
local okH2, _, sameH = installAddon("voice_talk3.lua", "voice", function() end, true)
CHECK(okH2 and sameH == "same", "the same version on the helper: up to date")
removeAddon("voice_talk3.lua")
CHECK(next(MEM) == nil and not VOICE_WHERE["voice_talk3.lua"], "voice remove deletes the packed helper copy")

for k, v in pairs(S0) do STORE[k] = v end
loadfile = lf0
fs.exists = realExists
