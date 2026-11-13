return function(endpoint)
  return {id = "update", endpoints = {endpoint}, draw = function(gpu, rows, failures, width, height)
    local function line(y, text) if y < height then gpu.set(2, y, tostring(text):sub(1, width - 2)) end end
    line(3, "Updates")
    if #rows == 1 then
      local value = rows[1].data
      line(4, "Phase: " .. tostring(value.phase)); line(5, "[Check main + LAN]")
      line(6, "Files sent: " .. tostring(value.filesSent or 0))
      if value.error then line(7, value.error) end
    elseif #failures > 0 then line(4, "Unavailable") end
  end, input = function(signal, command)
    if signal[1] == "touch" and signal[4] == 5 and signal[3] >= 2 and signal[3] <= 19 then return command(endpoint, "check") end
    return nil, "ENOTSUP"
  end}
end
