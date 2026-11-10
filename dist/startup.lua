






local function findProgram()
local found = {}
if fs.exists("controller/inventory.lua") then return "controller/inventory.lua" end
for _, pattern in ipairs({ "inventory.lua", "*/inventory.lua", "*/*/inventory.lua" }) do
for _, p in ipairs(fs.find(pattern)) do

local drive = fs.getDrive(p)
if drive == "hdd" then found[#found + 1] = p end
end
end
table.sort(found, function(a, b) return #a < #b end)
return found[1]
end

while true do
local path = findProgram()
if not path then
printError("startup: no inventory.lua found on this computer.")
print("Copy the base program folder onto the computer, then reboot.")
return
end
print("startup: starting " .. path)
local ok = shell.run("/" .. path)
if ok then return end
print("startup: the program stopped with an error - starting it again in 10 s (Ctrl+T cancels)")
sleep(10)
end
