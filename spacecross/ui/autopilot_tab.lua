return function(endpoint)
  local function text(gpu, width, height, y, value)
    if y < height then gpu.set(2, y, value:sub(1, width - 2)) end
  end
  return {id = "autopilot", endpoints = {endpoint}, draw = function(gpu, rows, failures, width, height)
    text(gpu, width, height, 3, "Autopilot")
    if #rows ~= 1 then text(gpu, width, height, 4, "Unavailable"); return end
    local data = rows[1].data
    text(gpu, width, height, 4, "State: " .. data.state)
    for index, axis in ipairs({"x", "y", "z"}) do
      text(gpu, width, height, index + 4, "[-] [+] " .. axis .. ": " .. tostring(data.draft[axis]))
    end
    text(gpu, width, height, 8, "[Go] [Cancel]")
    text(gpu, width, height, 9, "[Start] [Stop]")
    if data.position then
      text(gpu, width, height, 10, string.format("At: %d %d %d", data.position.x, data.position.y, data.position.z))
    end
    if data.error then text(gpu, width, height, 11, data.error) end
  end, input = function(signal, command)
    if signal[1] ~= "touch" then return nil, "ENOTSUP" end
    local x, y = signal[3], signal[4]
    if y >= 5 and y <= 7 then
      local axis = ({"x", "y", "z"})[y - 4]
      if x >= 2 and x <= 4 then return command(endpoint, "adjustTarget", {axis = axis, delta = -10}) end
      if x >= 6 and x <= 8 then return command(endpoint, "adjustTarget", {axis = axis, delta = 10}) end
    elseif y == 8 then
      if x >= 2 and x <= 5 then return command(endpoint, "go", {}) end
      if x >= 7 and x <= 14 then return command(endpoint, "cancel", {}) end
    elseif y == 9 then
      if x >= 2 and x <= 8 then return command(endpoint, "startAutopilot", {}) end
      if x >= 10 and x <= 15 then return command(endpoint, "stopAutopilot", {}) end
    end
    return nil, "ENOTSUP"
  end}
end
