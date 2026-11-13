local Fabric = require("spacecross.network.tests.stubs.fabric")
local Transport = require("spacecross.network.transport")
local Protocol = require("spacecross.network.protocol")
local H = require("tests.support")
local function fixture(maximum)
  local f = Fabric.new(); local a, b, c = f:host("a"), f:host("b"), f:host("c")
  f:card(a, "a-modem", "modem", "lan", maximum)
  f:card(a, "a-tunnel", "tunnel", "linked", maximum)
  f:card(b, "b-modem", "modem", "lan", maximum)
  f:card(b, "b-tunnel", "tunnel", "linked", maximum)
  f:card(c, "c-modem", "modem", "lan", maximum)
  a.net, b.net, c.net = Transport.new(a), Transport.new(b), Transport.new(c)
  a.net:start(); b.net:start(); c.net:start(); f:drain()
  return f, a, b, c
end
local function broadcast_all_or_one_and_directed_recipient_filter()
  local f, a, b, c = fixture()
  local bMessages, cMessages = {}, {}
  b.event.listen("spacecross_network_message", function(_, receiver, source, destination, port, service, payload)
    bMessages[#bMessages + 1] = {receiver, source, destination, port, service, payload}
  end)
  c.event.listen("spacecross_network_message", function() cMessages[#cMessages + 1] = true end)
  assert(a.net:broadcast(123, "all").sent == 2); f:drain()
  assert(#bMessages == 2 and #cMessages == 1)
  assert(a.net:broadcast(123, "one", "a-tunnel").sent == 1); f:drain()
  assert(#bMessages == 3 and #cMessages == 1 and bMessages[3][1] == "b-tunnel")
  assert(a.net:send("b-modem", 456, "private", nil, "test")); f:drain()
  assert(#bMessages == 4 and #cMessages == 1)
  return H.truth(bMessages[4][1] == "b-modem" and bMessages[4][2] == "a-modem"
    and bMessages[4][4] == 456 and bMessages[4][6] == "private")
end
local function fragments_reassemble_out_of_order_once_per_interface()
  local f, a, b = fixture(512)
  local payload = string.rep("\0\255text", 2000)
  local received, calls = nil, 0
  b.event.listen("spacecross_network_message", function(_, _, _, _, _, _, body) received = body; calls = calls + 1 end)
  f.paused = true
  local report = assert(a.net:send("b-modem", 123, payload, "a-modem"))
  assert(report.cards["a-modem"].fragments > 1)
  local packets = f:flush(true); f:drain()
  assert(received == payload and calls == 1 and b.net.buffered == 0)
  for _, packet in ipairs(packets) do f:deliver(packet) end
  f:drain()
  return H.equal(calls, 1)
end
local function malformed_spoofed_wrong_port_and_oversize_are_dropped()
  local f, a, b = fixture()
  local calls = 0
  b.event.listen("spacecross_network_message", function() calls = calls + 1 end)
  local packet = {v = 1, id = "x:1", src = "a-modem", dst = "b-modem", port = 123,
    service = "data", part = 1, total = 1, body = "x"}
  local function inject(source, rawPort, wire) b.event.push("modem_message", "b-modem", source, rawPort, 0, wire) end
  inject("spoofed", 27015, Protocol.encode(packet))
  inject("a-modem", 5, Protocol.encode(packet))
  inject("a-modem", 27015, "return os.execute('bad')")
  inject("a-modem", 27015, string.rep("x", 9000))
  packet.total = 1000000; inject("a-modem", 27015, Protocol.encode(packet))
  f:drain()
  assert(calls == 0 and b.net.stats.dropped == 5 and not next(b.net.pending))
  return H.truth(not a.net:broadcast(123, string.rep("x", 131073)))
end
local function incomplete_fragments_expire_and_limits_bound_memory()
  local f, _, b = fixture(512)
  local function inject(id, source, body)
    b.event.push("modem_message", "b-modem", source, 27015, 0, Protocol.encode({v = 1, id = id,
      src = source, dst = "b-modem", port = 123, service = "data", part = 1, total = 2, body = body}))
  end
  for index = 1, 30 do inject("partial:" .. index, "attacker", "abc") end
  f:drain()
  local count = 0; for _ in pairs(b.net.pending) do count = count + 1 end
  assert(count == 4 and b.net.buffered == 12)
  b:advance(6)
  return H.truth(not next(b.net.pending) and b.net.buffered == 0 and b.net.stats.expired == 4)
end
local function broken_card_does_not_prevent_linked_delivery_and_hotplug()
  local f, a, b = fixture()
  a.components["a-modem"].broken = true
  local received = 0
  b.event.listen("spacecross_network_message", function() received = received + 1 end)
  local report = assert(a.net:broadcast(123, "survives")); f:drain()
  assert(not report.cards["a-modem"].ok and report.cards["a-tunnel"].ok and received == 1)
  f:card(a, "a-new", "modem", "lan")
  a.event.push("component_added", "a-new", "modem"); f:drain()
  assert(a.net.cards["a-new"])
  a.components["a-tunnel"] = nil; a.event.push("component_removed", "a-tunnel"); f:drain()
  return H.truth(not a.net.cards["a-tunnel"] and a.net.cards["a-new"] ~= nil)
end
local function port_ownership_and_wireless_strength_are_restored()
  local f = Fabric.new(); local p = f:host("ports")
  local owned, shared = f:card(p, "owned", "modem"), f:card(p, "shared", "modem")
  shared.open(27015); shared.strength = 8
  local net = Transport.new(p, {cards = {owned = {}, shared = {strength = 16}}})
  net:start(); assert(shared.strength == 16)
  net:stop()
  assert(not owned.isOpen(27015) and shared.isOpen(27015) and shared.strength == 8)
  net:start(); net:stop()
  return H.equal(#p.listeners.modem_message, 0)
end
local function conflicting_fragments_and_global_memory_limit_discard_assembly()
  local f = Fabric.new(); local p = f:host("bounded")
  f:card(p, "receiver", "modem")
  local net = Transport.new(p, {maxBuffered = 5, maxMessage = 8})
  net:start()
  local received = 0; p.event.listen("spacecross_network_message", function() received = received + 1 end)
  local function inject(id, part, body)
    p.event.push("modem_message", "receiver", "source", 27015, 0, Protocol.encode({v = 1, id = id,
      src = "source", dst = "receiver", port = 123, service = "data", part = part, total = 2, body = body}))
  end
  inject("memory", 1, "1234"); p:pump(); assert(net.buffered == 4)
  inject("memory", 2, "5678"); p:pump(); assert(net.buffered == 0 and not next(net.pending))
  inject("conflict", 1, "one"); inject("conflict", 1, "two"); p:pump()
  return H.truth(received == 0 and net.buffered == 0 and not next(net.pending))
end
local all_tests = {
  {test_name = "broadcast_all_or_one_and_directed_recipient_filter", test = broadcast_all_or_one_and_directed_recipient_filter},
  {test_name = "fragments_reassemble_out_of_order_once_per_interface", test = fragments_reassemble_out_of_order_once_per_interface},
  {test_name = "malformed_spoofed_wrong_port_and_oversize_are_dropped", test = malformed_spoofed_wrong_port_and_oversize_are_dropped},
  {test_name = "incomplete_fragments_expire_and_limits_bound_memory", test = incomplete_fragments_expire_and_limits_bound_memory},
  {test_name = "broken_card_does_not_prevent_linked_delivery_and_hotplug", test = broken_card_does_not_prevent_linked_delivery_and_hotplug},
  {test_name = "port_ownership_and_wireless_strength_are_restored", test = port_ownership_and_wireless_strength_are_restored},
  {test_name = "conflicting_fragments_and_global_memory_limit_discard_assembly", test = conflicting_fragments_and_global_memory_limit_discard_assembly},
}
return all_tests
