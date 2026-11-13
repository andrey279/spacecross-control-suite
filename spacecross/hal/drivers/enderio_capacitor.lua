local energy = require("spacecross.hal.drivers.cofh_energy")
local function configure(options)
  options = options or {}
  return {id = "enderio_capacitor", types = {"energy_handler"}, kind = "buffer",
    matches = function(address) return not options.devices or options.devices[address] ~= nil end,
    new = function()
      local self = {}
      function self:init(proxy)
        assert(type(proxy.getEnergyStored) == "function" and type(proxy.getMaxEnergyStored) == "function", "RF telemetry missing")
        self.proxy = proxy; return true
      end
      function self:getEnergyLevel()
        local settings = options.devices and options.devices[self.address] or {}
        return energy.read(self.proxy, settings.side)
      end
      function self:turn_off() return nil, "ENOTSUP" end
      function self:isOperational() return self:getEnergyLevel() ~= nil end
      return self
    end}
end
local definition = configure()
definition.configure = configure
return definition
