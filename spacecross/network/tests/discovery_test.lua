local Fabric = require("spacecross.network.tests.stubs.fabric")
local Transport = require("spacecross.network.transport")
local Discovery = require("spacecross.network.discovery")
local codec = require("spacecross.core.codec")
local H = require("tests.support")
local function fixture()
  local f = Fabric.new(); local a, b = f:host("a"), f:host("b")
  f:card(a, "a", "modem"); f:card(b, "b", "modem")
  a.net, b.net = Transport.new(a), Transport.new(b)
  a.net:start(); b.net:start()
  a.discovery = Discovery.new({event = a.event, clock = a.clock, network = a.net}, {host_name = "Ship", type = {"ui"}})
  b.discovery = Discovery.new({event = b.event, clock = b.clock, network = b.net}, {host_name = "Power", type = {"reactors_controller", "capacitors_controller"}})
  a.discovery:start(); b.discovery:start(); f:drain()
  return f, a, b
end
local function announces_component_address_and_never_grants_trust()
  local f, a, b = fixture()
  local hosts = a.discovery:list("reactors_controller")
  assert(#hosts == 1 and hosts[1].address == "b" and hosts[1].host_name == "Power" and not hosts[1].verified)
  assert(hosts[1].reachable_via[1] == "a")
  hosts[1].type[1] = "mutated"
  assert(a.discovery:list()[1].type[1] == "reactors_controller")
  assert(b.discovery:setProfile({host_name = "Renamed", type = {"shields_controller"}, description = ""}))
  f:drain()
  return H.equal(a.discovery:list("shields_controller")[1].host_name, "Renamed")
end
local function graceful_stop_and_missing_heartbeat_remove_host()
  local f, a, b = fixture()
  b.discovery:stop(); f:drain(); assert(#a.discovery:list() == 0)
  b.discovery:start(); f:drain(); assert(#a.discovery:list() == 1)
  b.net:stop() -- unplug without a goodbye
  a:advance(40); f:drain()
  return H.equal(#a.discovery:list(), 0)
end
local function rejects_forged_profile_and_bounds_host_cache()
  local f, a, b = fixture()
  b.net:broadcast(27014, codec.encode({v = 1, action = "announce", address = "forged", host_name = "Bad"}), "b", "discovery")
  b.net:broadcast(27014, codec.encode({v = 1, action = "announce", address = "b", host_name = "Bad\nName"}), "b", "discovery")
  f:drain()
  assert(a.discovery:list()[1].host_name == "Power")
  local small = Discovery.new({event = a.event, clock = a.clock, network = a.net}, {maxHosts = 2})
  small:start()
  for index = 1, 10 do
    a.event.push("spacecross_network_message", "a", "peer" .. index, "*", 27014, "discovery",
      codec.encode({v = 1, action = "announce", address = "peer" .. index, host_name = "Peer"}))
  end
  a:pump()
  local count = #small:list(); small:stop()
  return H.equal(count, 2)
end
local all_tests = {
  {test_name = "announces_component_address_and_never_grants_trust", test = announces_component_address_and_never_grants_trust},
  {test_name = "graceful_stop_and_missing_heartbeat_remove_host", test = graceful_stop_and_missing_heartbeat_remove_host},
  {test_name = "rejects_forged_profile_and_bounds_host_cache", test = rejects_forged_profile_and_bounds_host_cache},
}
return all_tests
