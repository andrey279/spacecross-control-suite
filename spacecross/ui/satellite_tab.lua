local M = {}
function M.new(endpoint)
  local self = {id = "satellite", endpoints = endpoint.host and {endpoint} or endpoint, targets = {}}
  function self.draw(gpu, rows, failures, width, height)
    self.targets = {}; gpu.set(2, 3, "Satellite")
    local y = 4
    for _, row in ipairs(rows) do
      local d = row.data
      gpu.set(2, y, (row.host .. ": " .. tostring(d.state) .. " mode=" .. tostring(d.mode)):sub(1, width - 2)); y = y + 1
      local endpoint = {host=row.host,model=row.model}
      if y < height then gpu.set(2,y,"[Scan]"); self.targets[#self.targets+1]={first=2,last=7,y=y,endpoint=endpoint,action="scan"}; y=y+1 end
      for _, mode in ipairs({"jump", "charges"}) do
        local label="["..mode.."]"; local last=2+#label-1
        if y<height then gpu.set(2,y,label); self.targets[#self.targets+1]={first=2,last=last,y=y,endpoint=endpoint,action="setMode",mode=mode}; y=y+1 end
      end
      for _, target in ipairs(row.data.targets or {}) do
        local name=tostring(target.id or target.name or "target")
        local label="[Attack "..name.."]"; local last=2+#label-1
        if y<height and last<width then gpu.set(2,y,label); self.targets[#self.targets+1]={first=2,last=last,y=y,endpoint=endpoint,action="attack",target=target}; y=y+1 end
      end
    end
    for _, failure in ipairs(failures) do if y < height then gpu.set(2,y,(failure.host .. ": unavailable"):sub(1,width-2)); y=y+1 end end
  end
  function self.input(signal, command)
    if signal[1] ~= "touch" then return nil, "ENOTSUP" end
    for _, target in ipairs(self.targets) do
      if signal[4] == target.y and signal[3] >= target.first and signal[3] <= target.last then
        local args={}; if target.mode then args.mode=target.mode end; if target.target then args.target=target.target end
        return command(target.endpoint,target.action,args)
      end
    end
    return nil, "ENOTSUP"
  end
  return self
end
return M
