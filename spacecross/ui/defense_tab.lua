return function(endpoint)
  return {id = "defense", endpoints = {endpoint}, draw = function(gpu, rows, failures, width, height)
    gpu.set(2, 3, "Defense")
    if height > 5 and #rows == 1 then
      local data = rows[1].data
      gpu.set(2, 4, ("Armed: " .. tostring(data.armed) .. " Fired: " .. tostring(data.fired)):sub(1, width - 2))
      gpu.set(2, 5, "[Arm] [Disarm]")
    elseif #failures > 0 then gpu.set(2, 4, "Unavailable") end
  end, input = function(signal, command)
    if signal[1] == "touch" and signal[4] == 5 then
      if signal[3] >= 2 and signal[3] <= 6 then return command(endpoint, "arm") end
      if signal[3] >= 8 and signal[3] <= 15 then return command(endpoint, "disarm") end
    end
    return nil, "ENOTSUP"
  end}
end
