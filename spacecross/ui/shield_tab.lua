local M = {}
local buttons = {
  {label = "[On]", action = "turn_on"},
  {label = "[Off]", action = "turn_off"},
  {label = "[Form]", action = "compose"},
  {label = "[Break]", action = "decompose"},
}

function M.new(endpoint)
  local endpoints = endpoint.host and {endpoint} or endpoint
  local self = {id = "shields", endpoints = endpoints, targets = {}}
  function self.draw(gpu, rows, failures, width, height)
    self.targets = {}
    gpu.set(2, 3, "Shields")
    local y = 4
    for _, row in ipairs(rows) do
      for _, item in ipairs(row.data.shields or {}) do
        if y + 1 < height then
          local state = item.status.active and "active" or "inactive"
          local formed = item.status.composed and "formed" or "not formed"
          gpu.set(2, y, (item.address .. ": " .. state .. ", " .. formed .. " (" .. tostring(item.status.redstoneMode) .. ")"):sub(1, width - 2))
          y = y + 1
          local x = 2
          for _, button in ipairs(buttons) do
            local last = x + #button.label - 1
            if last < width then
              gpu.set(x, y, button.label)
              self.targets[#self.targets + 1] = {first = x, last = last, y = y, address = item.address,
                endpoint = {host = row.host, model = row.model}, action = button.action}
              x = last + 2
            end
          end
          y = y + 1
        end
      end
      for _, failure in ipairs(row.data.failures or {}) do
        if y < height then gpu.set(2, y, (failure.address .. ": status unavailable"):sub(1, width - 2)); y = y + 1 end
      end
    end
    for _, failure in ipairs(failures) do
      if y < height then gpu.set(2, y, (failure.host .. ": unavailable"):sub(1, width - 2)); y = y + 1 end
    end
    if #rows == 1 and #(rows[1].data.shields or {}) == 0 and #(rows[1].data.failures or {}) == 0 and y < height then
      gpu.set(2, y, "No shield components detected")
    end
  end
  function self.input(signal, command)
    if signal[1] ~= "touch" then return nil, "ENOTSUP" end
    for _, target in ipairs(self.targets) do
      if signal[4] == target.y and signal[3] >= target.first and signal[3] <= target.last then
        return command(target.endpoint, target.action, {address = target.address})
      end
    end
    return nil, "ENOTSUP"
  end
  return self
end

return M
