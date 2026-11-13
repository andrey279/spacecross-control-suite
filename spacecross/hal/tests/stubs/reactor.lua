-- A fake contract implementation, never shipped as a real hardware driver.
return {id = "stub_reactor", types = {"stub_reactor"}, kind = "power", new = function()
  local self = {}
  function self:init(proxy) self.proxy = proxy; return true end
  function self:getEnergyLevel() return {stored = self.proxy.energy, capacity = 100} end
  function self:turn_off()
    if self.proxy.broken then error("component disconnected") end
    self.proxy.on = false
    return true
  end
  function self:isOperational() return not self.proxy.broken end
  return self
end}
