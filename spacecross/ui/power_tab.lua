return function(endpoints)
  return {id = "power", endpoints = endpoints, draw = function(gpu, rows, failures, width, height)
    local y = 3
    local function line(value)
      if y < height then gpu.set(2, y, value:sub(1, width - 2)); y = y + 1 end
    end
    line("Power")
    for _, row in ipairs(rows) do
      local data, disabled = row.data, 0
      for _ in pairs(data.disabled or {}) do disabled = disabled + 1 end
      local percent = data.telemetry.fraction and string.format("%.1f%%", data.telemetry.fraction * 100) or "?"
      line(row.host .. ": " .. percent .. (data.telemetry.complete and "" or " incomplete"))
      line("Generation: " .. tostring(data.generating) .. " Shed: " .. disabled)
      line("Faults: " .. #(data.faults or {}))
    end
    for _, row in ipairs(failures) do line(row.host .. ": unavailable") end
  end}
end
