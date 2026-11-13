local Fabric = require("spacecross.network.tests.stubs.fabric")
local Transport = require("spacecross.network.transport")
local Bus = require("spacecross.bus.local_bus")
local Bridge = require("spacecross.bus.network_bridge")
local codec = require("spacecross.core.codec")
local H = require("tests.support")
local function fixture(aPolicy, bPolicy, maximum)
  local f = Fabric.new(); local a, b = f:host("a"), f:host("b")
  f:card(a, "a-one", "modem", "lan", maximum); f:card(a, "a-two", "modem", "lan", maximum)
  f:card(b, "b-one", "modem", "lan", maximum); f:card(b, "b-two", "modem", "lan", maximum)
  for _, p in ipairs({a, b}) do
    p.network = Transport.new(p); p.bus = Bus.new(p)
    p.bus:start(); p.network:start()
  end
  a.bridge = Bridge.new(a, aPolicy); b.bridge = Bridge.new(b, bPolicy)
  a.bridge:start(); b.bridge:start(); f:drain()
  return f, a, b
end
local function eventMessage(destination, port, body)
  return {proto_version = 1, msg_type = "event", dst_addr = destination, port = port or 123, payload = body or "payload"}
end
local function network_messages_deliver_once_without_echo_loops()
  local f, a, b = fixture()
  local localCount, remoteCount = 0, 0
  a.bus:subscribe(123, function() localCount = localCount + 1 end)
  b.bus:subscribe(123, function(message)
    assert(message.src_addr == "a-one" or message.src_addr == "a-two")
    assert(message.dst_addr == "*" and message.payload == "payload"); remoteCount = remoteCount + 1
  end)
  assert(a.bus:publish(eventMessage("*"))); f:drain()
  assert(localCount == 1 and remoteCount == 1 and #f.sent == 2)
  assert(a.bridge.stats.sent == 1 and b.bridge.stats.received == 1 and b.bridge.stats.sent == 0)
  return H.success()
end
local function localhost_requires_explicit_forwarding_and_blacklist_wins()
  local f, a, b = fixture({outbound = {forwardLocal = true,
    whitelist = {ports = {123, 124}, msg_types = {"event"}}, blacklist = {ports = {124}}}})
  local ports = {}
  b.bus:subscribe(nil, function(message) ports[#ports + 1] = message.port end)
  a.bus:publish(eventMessage(nil, 123)); a.bus:publish(eventMessage("*", 124)); a.bus:publish(eventMessage("*", 125))
  a.bus:publish({proto_version = 1, msg_type = "cmd", dst_addr = "*", port = 123, payload = "blocked"})
  f:drain()
  assert(#ports == 1 and ports[1] == 123)
  b.bus:publish(eventMessage(nil, 123)); f:drain()
  return H.equal(b.bridge.stats.sent, 0)
end
local function receiving_interface_policy_is_checked_before_deduplication()
  local f, a, b = fixture(nil, {cards = {["b-one"] = false, ["b-two"] = {inbound = {whitelist = {peers = {"a-one"}}}}}})
  local received = 0
  b.bus:subscribe(123, function(message) assert(message.src_addr == "a-one"); received = received + 1 end)
  a.bus:publish(eventMessage("*")); f:drain()
  assert(b.bridge.stats.dropped > 0 and received == 1)
  return H.equal(b.bridge.stats.received, 1)
end
local function per_card_outbound_and_directed_delivery()
  local f, a, b = fixture({cards = {["a-two"] = false}})
  local received = 0
  b.bus:subscribe(123, function(message)
    assert(message.src_addr == "a-one" and message.dst_addr == "b-two"); received = received + 1
  end)
  a.bus:publish(eventMessage("b-two")); f:drain()
  assert(received == 1 and #f.sent == 1)
  return H.success()
end
local function rejects_envelope_source_port_destination_forgery()
  local f, a, b = fixture()
  local received = 0
  b.bus:subscribe(123, function() received = received + 1 end)
  local forged = eventMessage("b-one"); forged.src_addr = "owner"
  a.network:send("b-one", 123, codec.encode(forged), "a-one", "bus")
  forged.src_addr, forged.port = nil, 999
  a.network:send("b-one", 123, codec.encode(forged), "a-one", "bus")
  forged.port, forged.dst_addr = 123, "b-two"
  a.network:send("b-one", 123, codec.encode(forged), "a-one", "bus")
  f:drain()
  return H.truth(received == 0 and b.bridge.stats.dropped == 3)
end
local function stop_detaches_bridge_and_preserves_local_bus()
  local f, a, b = fixture()
  local localCount = 0
  a.bus:subscribe(123, function() localCount = localCount + 1 end)
  a.bridge:stop(); a.bus:publish(eventMessage("*")); f:drain()
  assert(localCount == 1 and #f.sent == 0 and a.bus.running)
  a.bridge:start(); a.bus:publish(eventMessage("*")); f:drain()
  return H.truth(a.bridge.stats.sent == 1 and a.bus.running and b.bus.running)
end
local function fragmented_copy_on_blocked_interface_does_not_poison_allowed_copy()
  local f, a, b = fixture(nil, {cards = {["b-one"] = false}}, 512)
  local payload, received = string.rep("fragmented", 800), 0
  b.bus:subscribe(123, function(message) assert(message.payload == payload); received = received + 1 end)
  a.bus:publish(eventMessage("*", 123, payload)); f:drain()
  assert(received == 1 and b.network.buffered == 0 and b.bridge.stats.dropped > 0)
  return H.success()
end
local all_tests = {
  {test_name = "network_messages_deliver_once_without_echo_loops", test = network_messages_deliver_once_without_echo_loops},
  {test_name = "localhost_requires_explicit_forwarding_and_blacklist_wins", test = localhost_requires_explicit_forwarding_and_blacklist_wins},
  {test_name = "receiving_interface_policy_is_checked_before_deduplication", test = receiving_interface_policy_is_checked_before_deduplication},
  {test_name = "per_card_outbound_and_directed_delivery", test = per_card_outbound_and_directed_delivery},
  {test_name = "rejects_envelope_source_port_destination_forgery", test = rejects_envelope_source_port_destination_forgery},
  {test_name = "stop_detaches_bridge_and_preserves_local_bus", test = stop_detaches_bridge_and_preserves_local_bus},
  {test_name = "fragmented_copy_on_blocked_interface_does_not_poison_allowed_copy", test = fragmented_copy_on_blocked_interface_does_not_poison_allowed_copy},
}
return all_tests
