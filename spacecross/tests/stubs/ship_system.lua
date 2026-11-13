local P = require("tests.stubs.platform")
local Ship = require("spacecross.autopilot.tests.stubs.ship")
return function()
  local p = P.new(); p.fs.mkdir("/tmp")
  p.components.ship = Ship(p, "ship")
  p.components.buffer = {type = "energy_handler", getEnergyStored = function() return 10 end,
    getMaxEnergyStored = function() return 100 end}
  p.components.switch = {type = "redstone", setOutput = function() return 0 end}
  return p, {owners = {"Owner"}, logging = {root = "/logs"}, drivers = {
    "spacecross.hal.drivers.warpdrive_ship", "spacecross.hal.drivers.redstone",
    {module = "spacecross.hal.drivers.enderio_capacitor", options = {devices = {buffer = {}}}},
  }, coreDaemon = {controllers = {"ship"}},
    autopilot = {enabled = true, controller = "ship", lockPath = "/tmp/app-autopilot.lock"},
    power = {enabled = true, buffers = {"buffer"}, sources = {}, loads = {
      {id = "expensive", group = 1, address = "switch",
        on = {method = "setOutput", args = {1, 15}}, off = {method = "setOutput", args = {1, 0}}},
    }}}
end
