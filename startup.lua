-- startup.lua  -  goes in the TOP LEVEL of the base computer (not in a folder).
-- ComputerCraft runs it by itself whenever the computer starts (server
-- restart, chunk reload, reboot). It finds inventory.lua - in the top level or
-- in any folder on the computer (not on floppies) - and starts it.
-- If the program crashes it is started again after 10 seconds; if you stop it
-- yourself (Ctrl+T) it stays stopped. Hold Ctrl+T during the 10 seconds to cancel.

local function findProgram()
  local found = {}
  if fs.exists("controller/inventory.lua") then return "controller/inventory.lua" end   -- the usual place
  for _, pattern in ipairs({ "inventory.lua", "*/inventory.lua", "*/*/inventory.lua" }) do
    for _, p in ipairs(fs.find(pattern)) do
      -- only the computer's own files: not a floppy disk, not the ROM
      local drive = fs.getDrive(p)
      if drive == "hdd" then found[#found + 1] = p end
    end
  end
  table.sort(found, function(a, b) return #a < #b end)    -- the top level first
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
  if ok then return end                    -- stopped on purpose (Ctrl+T): stay stopped
  print("startup: the program stopped with an error - starting it again in 10 s (Ctrl+T cancels)")
  sleep(10)
end
