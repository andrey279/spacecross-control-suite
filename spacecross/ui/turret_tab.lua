local M = {}

local function endpoints(value)
  return value.host and {value} or value
end

function M.new(value)
  local self = {id = "turrets", endpoints = endpoints(value), targets = {}}
  function self.draw(gpu, rows, failures, width, height)
    self.targets = {}
    gpu.set(2, 3, "Turrets")
    local y = 4
    for _, row in ipairs(rows) do
      for _, item in ipairs(row.data.turrets or {}) do
        if y + 1 < height then
          local status = item.status
          local active = status.active == nil and "unknown" or status.active and "on" or "off"
          local mode = status.mode == nil and "?" or tostring(status.mode)
          local energy = status.energy and string.format(" %s/%s", tostring(status.energy.stored), tostring(status.energy.capacity)) or ""
          gpu.set(2, y, (item.address .. ": " .. active .. " mode=" .. mode .. energy):sub(1, width - 2))
          y = y + 1
          local x = 2
          local choices = {{label = "[Toggle]", action = "toggle"}}
          if status.active ~= nil then
            choices[#choices + 1] = {label = "[On]", action = "turn_on"}
            choices[#choices + 1] = {label = "[Off]", action = "turn_off"}
          end
          if status.modes then
            for _, modeValue in ipairs(status.modes) do
              choices[#choices + 1] = {label = "[M" .. tostring(modeValue) .. "]", action = "setMode", mode = modeValue}
            end
          end
          for _, choice in ipairs(choices) do
            local last = x + #choice.label - 1
            if last < width then
              gpu.set(x, y, choice.label)
              self.targets[#self.targets + 1] = {first = x, last = last, y = y, address = item.address,
                endpoint = {host = row.host, model = row.model}, action = choice.action, mode = choice.mode}
              x = last + 2
            end
          end
          y = y + 1
        end
      end
      for _, failure in ipairs(row.data.failures or {}) do
        if y < height then gpu.set(2, y, (failure.address .. ": unavailable"):sub(1, width - 2)); y = y + 1 end
      end
    end
    for _, failure in ipairs(failures) do
      if y < height then gpu.set(2, y, (failure.host .. ": unavailable"):sub(1, width - 2)); y = y + 1 end
    end
    if #rows == 1 and #(rows[1].data.turrets or {}) == 0 and #(rows[1].data.failures or {}) == 0 and y < height then
      gpu.set(2, y, "No turret components detected")
    end
  end
  function self.input(signal, command)
    if signal[1] ~= "touch" then return nil, "ENOTSUP" end
    for _, target in ipairs(self.targets) do
      if signal[4] == target.y and signal[3] >= target.first and signal[3] <= target.last then
        local args = {address = target.address}
        if target.action == "setMode" then args.mode = target.mode end
        return command(target.endpoint, target.action, args)
      end
    end
    return nil, "ENOTSUP"
  end
  return self
end

return M
