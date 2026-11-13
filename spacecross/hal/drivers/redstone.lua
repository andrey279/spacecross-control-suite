-- Generic OC redstone I/O. Channel meaning belongs to its owning model.
return {id = "redstone", types = {"redstone"}, kind = "redstone", new = function()
  local self = {}
  function self:init(proxy)
    assert(type(proxy.setOutput) == "function", "setOutput unavailable")
    self.proxy = proxy; return true
  end
  function self:getEnergyLevel() return nil, "ENOTSUP" end
  function self:turn_off()
    for side = 0, 5 do self:setOutput(side, 0) end
    return true
  end
  function self:isOperational() return type(self.proxy.setOutput) == "function" end
  function self:setOutput(side, value)
    assert(type(side) == "number" and side >= 0 and side <= 5 and side % 1 == 0, "invalid side")
    assert(type(value) == "number" and value >= 0 and value <= 15 and value % 1 == 0, "invalid redstone level")
    local result, err = self.proxy.setOutput(side, value)
    if result == nil or result == false then return nil, err or "OUTPUT_REJECTED" end
    return true
  end
  return self
end}
