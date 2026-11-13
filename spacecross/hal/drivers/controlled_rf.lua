local energy = require("spacecross.hal.drivers.cofh_energy")
local util = require("spacecross.core.util")
local M = {}
-- Composite driver for legacy generators with RF telemetry and a wired redstone input.
-- The energy component is the instance's identity; the configured output uses HAL too.
function M.definition(id, types, options)
  local devices = util.copy((options or {}).devices or {})
  for _, device in pairs(devices) do
    assert(type(device.controlAddress) == "string" and type(device.side) == "number"
      and device.side % 1 == 0 and device.side >= 0 and device.side <= 5, "generator control channel required")
    device.onValue, device.offValue = device.onValue or 15, device.offValue or 0
    assert(device.onValue ~= device.offValue, "generator on/off levels must differ")
  end
  return {id = id, types = types, kind = "power",
    matches = function(address) return devices[address] ~= nil end,
    new = function(context)
      local self = {}
      function self:init(proxy)
        self.proxy, self.settings = proxy, assert(devices[self.address])
        assert(energy.read(proxy, self.settings.energySide))
        return true
      end
      function self:getEnergyLevel() return energy.read(self.proxy, self.settings.energySide) end
      local function output(value)
        return context.registry:call(self.settings.controlAddress, "setOutput", self.settings.side, value)
      end
      function self:turn_on() return output(self.settings.onValue) end
      function self:turn_off() return output(self.settings.offValue) end
      function self:isOperational()
        return self:getEnergyLevel() ~= nil and context.registry.instances[self.settings.controlAddress] ~= nil
      end
      return self
    end}
end
return M
