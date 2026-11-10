-- SETTINGS: every setting of every group can be shown, stepped both ways,
-- reset, and every group draws - numbers stay inside their limits.
local n, steps = 0, 0
for gi, g in ipairs(SETTING_GROUPS) do
  for i, def in ipairs(g.list) do
    n = n + 1
    local where = g.name .. " / " .. def.label
    local okV = pcall(function() return def.kind == "custom" and def.get() or getConfigPath(def.path) end)
    CHECK(okV, where .. ": shows its value")
    if def.kind == "num" or def.kind == "cycle" or def.kind == "bool" then
      for _, dir in ipairs({ 1, 1, -1, -1, -1 }) do
        local ok, err = pcall(settingStep, def, dir)
        CHECK(ok, where .. ": step " .. dir .. " - " .. tostring(err))
        steps = steps + 1
      end
      if def.kind == "num" then
        local v = tonumber(getConfigPath(def.path))
        CHECK(v and v >= def.min and v <= def.max, where .. ": stays within " .. def.min .. ".." .. def.max .. " (" .. tostring(v) .. ")")
      end
      local okR, errR = pcall(settingReset, def)
      CHECK(okR, where .. ": RESET - " .. tostring(errR))
    elseif def.kind == "custom" and def.label ~= "Theme" then
      local ok, err = pcall(def.next, 1)
      CHECK(ok, where .. ": tap - " .. tostring(err))
    end
  end
  state.page, state.setGroup = "settings", gi
  local ok, err = pcall(draw)
  CHECK(ok, "group " .. g.name .. " draws: " .. tostring(err))
end
CHECK(n > 40, "all settings looked at (" .. n .. ")")
