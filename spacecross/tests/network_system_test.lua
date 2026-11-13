local Fabric = require("spacecross.network.tests.stubs.fabric")
local App = require("spacecross.app")
local H = require("tests.support")
local function configuration(name)
  return {owners = {"Owner"}, logging = {root = "/logs"}, network = {enabled = true,
    discovery = {host_name = name}, bus = {enabled = true,
      outbound = {forwardLocal = true, whitelist = {ports = {27103}, msg_types = {"event"}}},
      inbound = {whitelist = {ports = {27103}, msg_types = {"event"}}}}}}
end
local function independent_apps_discover_and_exchange_live_controller_events()
  local f = Fabric.new(); local a, b = f:host("power"), f:host("monitor")
  f:card(a, "power-modem", "modem"); f:card(b, "monitor-modem", "modem")
  a.components.buffer = {type = "energy_handler", getEnergyStored = function() return 25 end,
    getMaxEnergyStored = function() return 100 end}
  local config = configuration("Power")
  config.drivers = {"spacecross.hal.drivers.enderio_capacitor"}
  config.power = {enabled = true, buffers = {"buffer"}, sources = {}}
  local source, monitor = App.new(a, config), App.new(b, configuration("Monitor"))
  source:start(); monitor:start()
  local received = 0
  monitor.bus:subscribe(27103, function(message)
    assert(message.src_addr == "power-modem")
    local state = assert(require("spacecross.core.codec").decode(message.payload))
    assert(state.telemetry.fraction == 0.25); received = received + 1
  end)
  f:drain(); f:advance(2)
  assert(received >= 2)
  local view = monitor.model:request("network", "snapshot", "Owner")
  assert(#view.hosts == 1 and view.hosts[1].address == "power-modem" and not view.hosts[1].verified)
  assert(#monitor.discovery:list("power") == 1 and not monitor.model:request("network", "snapshot", "Intruder"))
  source:stop(); f:drain(); assert(#monitor.discovery:list() == 0)
  assert(monitor.running and monitor.bus.running)
  source:start(); f:drain(); assert(#monitor.discovery:list("power") == 1)
  source:stop(); monitor:stop(); f:drain()
  return H.truth(not next(a.timers) and not next(b.timers))
end
local function broken_network_card_leaves_local_ship_services_running()
  local f = Fabric.new(); local p = f:host("headless")
  local card = f:card(p, "broken", "modem"); card.open = function() error("broken hardware") end
  local app = App.new(p, configuration("Headless"))
  assert(app:start())
  f:drain()
  assert(app.running and app.hal.registry.running and app.bus.running and #app.network:listCards() == 0)
  app:stop(); f:drain()
  return H.truth(not next(p.timers))
end
local all_tests = {
  {test_name = "independent_apps_discover_and_exchange_live_controller_events", test = independent_apps_discover_and_exchange_live_controller_events},
  {test_name = "broken_network_card_leaves_local_ship_services_running", test = broken_network_card_leaves_local_ship_services_running},
}
return all_tests
