local common = require("spacecross.hal.drivers.controlled_rf")
local function configure(options)
  return common.definition("thermal_generator", {"energy_handler", "energy_info"}, options)
end
local definition = configure()
definition.configure = configure
return definition
