local P = require("tests.stubs.platform")
local Bus = require("spacecross.bus.local_bus")
local H = require("tests.support")
local function async_local_delivery_and_isolation()
  local p = P.new(); local bus = Bus.new(p); bus:start()
  local called = 0
  bus:subscribe(27015, function(m) m.payload = "mutated"; error("subscriber failed") end)
  bus:subscribe(27015, function(m) assert(m.payload == "original"); called = called + 1 end)
  local id = bus:subscribe(10, function() error("wrong port") end)
  assert(bus:publish({proto_version = 1, msg_type = "event", port = 27015, payload = "original"}))
  assert(called == 0)
  p:pump()
  assert(#p.errors == 1 and p.errors[1].code == "ERR_BUS_CALLBACK")
  bus:unsubscribe(id)
  return H.equal(called, 1)
end
local function envelope_validation_and_stop()
  local p = P.new(); local bus = Bus.new(p)
  local ok, err = bus:publish({proto_version = 1, msg_type = "cmd", port = 1, payload = ""})
  assert(not ok and err == "ENOTRUNNING")
  bus:start(); bus:stop()
  for _, message in ipairs({{}, {proto_version = 1, msg_type = "cmd", port = -1, payload = "x"},
      {proto_version = 1, msg_type = "cmd", port = 1, payload = {}},
      {proto_version = 1, msg_type = "cmd", port = 1.5, payload = ""}}) do
    assert(not Bus.validate(message))
  end
  return H.equal(#p.listeners.spacecross_message, 0)
end
local all_tests = {
  {test_name = "async_local_delivery_and_isolation", test = async_local_delivery_and_isolation},
  {test_name = "envelope_validation_and_stop", test = envelope_validation_and_stop},
}
return all_tests
