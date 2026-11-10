-- Every console command (from the help list, and a few with arguments) runs
-- without an error - a typo or a nil in a rarely used command shows up here.
local skip = { exit = true, report = true, restart = true, reboot = true }
local cmds = {}
for _, line in ipairs(HELP) do
  local w = line:match("^%s*([%a]+)")
  if w and not skip[w] then cmds[w] = true end
end
local list = {}
for w in pairs(cmds) do list[#list + 1] = w end
table.sort(list)
CHECK(#list > 20, "the help lists the commands (" .. #list .. ")")
-- plus some with arguments
local extra = { "turtles", "turtle 7 log", "turtle 7 forget", "mine", "mine forget 99", "factory", "factory chest",
                "factory builder 7", "factory build", "factory stop", "disks", "map", "survey", "events 5", "uptime",
                "away", "store", "theme", "drones", "charger", "dest 10 70 10", "tanks", "me check", "curios check",
                "pocket", "pocket unpair 99", "schem", "schem nothere", "schem delete nothere", "mine drop 99" }
for _, e in ipairs(extra) do list[#list + 1] = e end
local sleep0 = sleep
sleep = function() end                               -- (store waits a few seconds after waking helpers)
for _, c in ipairs(list) do
  local ok, out = pcall(handleCommand, c)
  CHECK(ok, "console '" .. c .. "': " .. tostring(out))
end
sleep = sleep0
-- "disk" (no s) works like "disks"
local outD = handleCommand("disk") or {}
CHECK(not table.concat(outD, "\n"):find("Unknown command", 1, true), "'disk' works like 'disks'")
