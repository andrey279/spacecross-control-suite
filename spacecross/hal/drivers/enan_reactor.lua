return {id = "enan_reactor", types = {"warpdriveEnanReactorCore"}, kind = "power", new = function()
  local self = {}
  function self:init(proxy)
    for _, method in ipairs({"enable", "energy", "instability", "release", "state"}) do
      assert(type(proxy[method]) == "function", "reactor API missing " .. method)
    end
    self.proxy = proxy; return true
  end
  function self:getEnergyLevel()
    -- instability() releases the legacy startup hold and runs the built-in laser loop.
    local instability = {self.proxy.instability()}
    if #instability == 0 then return nil, "INSTABILITY_UNAVAILABLE" end
    for _, value in ipairs(instability) do
      if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return nil, "INVALID_INSTABILITY" end
    end
    local stored, capacity, rate = self.proxy.energy()
    if type(stored) ~= "number" or type(capacity) ~= "number" or stored ~= stored or capacity ~= capacity
        or capacity <= 0 or capacity == math.huge or stored < 0 or stored > capacity then return nil, "INVALID_ENERGY" end
    return {stored = stored, capacity = capacity, rate = rate, instability = instability}
  end
  function self:turn_on()
    local level, err = self:getEnergyLevel()
    if not level then return nil, err end
    if self.proxy.release(true) ~= true then return nil, "OUTPUT_REJECTED" end
    if self.proxy.enable(true) ~= true then return nil, "ENABLE_REJECTED" end
    return true
  end
  function self:turn_off()
    if self.proxy.enable(false) ~= false then return nil, "DISABLE_REJECTED" end
    return true
  end
  function self:isOperational()
    local _, enabled = self.proxy.state()
    return type(enabled) == "boolean"
  end
  return self
end}
