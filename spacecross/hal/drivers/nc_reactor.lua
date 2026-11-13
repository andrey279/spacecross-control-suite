local common = require("spacecross.hal.drivers.controlled_rf")
local function configure(options)
  return common.definition("nc_reactor", {"energy_handler"}, options)
end
local definition = configure()
definition.configure = configure
return definition
