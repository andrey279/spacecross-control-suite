-- View plugin: aggregates snapshots from every selected target of one component.
return function(id, endpoints)
  return {id = id, endpoints = endpoints, draw = function(gpu, rows, failures, width, height)
    gpu.set(2, 3, ("SpaceCross: " .. id):sub(1, width - 2))
    local y = 4
    for _, row in ipairs(rows) do
      if y < height then
        local count = row.data.count or 0
        gpu.set(2, y, (row.host .. ": " .. tostring(count) .. " components"):sub(1, width - 2))
        y = y + 1
        if row.data.entities then
          for _, entity in ipairs(row.data.entities) do
            if y < height then
              gpu.set(3, y, entity.name:sub(1, width - 3)); y = y + 1
            end
          end
        end
      end
    end
    for _, row in ipairs(failures) do
      if y < height then
        gpu.set(2, y, (row.host .. ": unavailable"):sub(1, width - 2)); y = y + 1
      end
    end
  end}
end
