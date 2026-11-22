-- the release number (BASE_VERSION) + the commit `upgrade` installed: console `version`, the SYSTEM page,
-- and the newest CHANGELOG.md entry must be this version (a release with a stale number fails here)
local function out(c) return table.concat(handleCommand(c) or {}, "\n") end
CHECK(type(BASE_VERSION) == "string" and BASE_VERSION:match("^%d+%.%d+%.%d+$"), "BASE_VERSION is x.y.z: " .. tostring(BASE_VERSION))
fs.delete("upgrade.dat")
local o = out("version")
CHECK(o:find("v" .. BASE_VERSION, 1, true) and not o:find("%(%x"), "version without upgrade.dat: " .. o)
local h = fs.open("upgrade.dat", "w") h.write(textutils.serialize({ sha = "abcdef1234567", branch = "main" })) h.close()
o = out("version")
CHECK(o:find("v" .. BASE_VERSION .. " (abcdef1) from main", 1, true), "version with the commit: " .. o)
h = fs.open("upgrade.dat", "w") h.write("not a table {") h.close()
CHECK(out("version"):find("v" .. BASE_VERSION, 1, true), "a broken upgrade.dat: still the version")
h = fs.open("upgrade.dat", "w") h.write(textutils.serialize({ sha = "abcdef1234567" })) h.close()
sysRefresh()
CHECK(state.sys.version == "v" .. BASE_VERSION .. " (abcdef1)", "SYSTEM numbers: " .. tostring(state.sys.version))
state.page = "system"
hits = {}
draw()
local scr = {}
for y = 1, H do scr[#scr + 1] = (MONITOR.getLine(y)) end
scr = table.concat(scr, "\n")
CHECK(scr:find("Program", 1, true) and scr:find("v" .. BASE_VERSION, 1, true), "the SYSTEM page shows the version")
fs.delete("upgrade.dat")
-- CHANGELOG.md: the newest entry is this version
local cl = io.open(SRC_DIR .. "/CHANGELOG.md")
local text = cl and cl:read("a") or ""
if cl then cl:close() end
local first = text:match("\n## %[?v?(%d+%.%d+%.%d+)")
CHECK(first == BASE_VERSION, "CHANGELOG.md's newest entry (" .. tostring(first) .. ") = BASE_VERSION " .. BASE_VERSION)
