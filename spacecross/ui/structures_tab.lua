local M = {}
function M.new(endpoint)
  local self = {id = "structures", endpoints = endpoint.host and {endpoint} or endpoint, targets = {}}
  function self.draw(gpu, rows, failures, width, height)
    self.targets = {}; gpu.set(2,3,"Structures"); local y=4
    for _, row in ipairs(rows) do
      gpu.set(2,y,(row.host .. ": " .. tostring(row.data.state) .. " phase=" .. tostring(row.data.phase)):sub(1,width-2)); y=y+1
      local endpoint={host=row.host,model=row.model}
      if y < height then gpu.set(2,y,"[Start]"); self.targets[#self.targets+1]={first=2,last=8,y=y,endpoint=endpoint,action="start"}; y=y+1 end
      if y < height then gpu.set(2,y,"[Stop]"); self.targets[#self.targets+1]={first=2,last=7,y=y,endpoint=endpoint,action="stop"}; y=y+1 end
    end
    for _, failure in ipairs(failures) do if y < height then gpu.set(2,y,(failure.host .. ": unavailable"):sub(1,width-2)); y=y+1 end end
  end
  function self.input(signal, command)
    if signal[1] ~= "touch" then return nil,"ENOTSUP" end
    for _, target in ipairs(self.targets) do if signal[4]==target.y and signal[3]>=target.first and signal[3]<=target.last then return command(target.endpoint,target.action,{}) end end
    return nil,"ENOTSUP"
  end
  return self
end
return M
