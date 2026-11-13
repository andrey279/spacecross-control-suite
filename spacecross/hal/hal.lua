local Registry = require("spacecross.hal.drivers")
local M = {}
function M.new(deps, definitions)
  local registry = Registry.new(deps)
  for _, definition in ipairs(definitions or {}) do registry:register(definition) end
  local self = {registry = registry, power = {}}
  function self.power.turnOffAll() return registry:all("power", "turn_off") end
  function self.power.getEnergyLevels() return registry:all("power", "getEnergyLevel") end
  function self:call(address, method, ...) return registry:call(address, method, ...) end
  function self:all(kind, method, ...) return registry:all(kind, method, ...) end
  function self:start() return registry:start() end
  function self:stop() return registry:stop() end
  return self
end
return M
