local System = require("spacecross.rpc.tests.stubs.system")
local Fake = require("spacecross.rpc.tests.stubs.crypto")
local Protocol = require("spacecross.rpc.protocol")
local RPC = require("spacecross.rpc.service")
local H = require("tests.support")
local function authenticated_request_uses_certificate_subject_and_preserves_false()
  local _, a, b = System.new()
  local value = assert(a.rpc:request("server", "power", "snapshot", "Owner", {value = 25}))
  assert(value.value == 25 and b.executed == 1)
  assert(a.rpc:request("server", "power", "false", "Owner", {}) == false)
  local denied, err = a.rpc:request("server", "power", "fail", "Owner", {})
  assert(not denied and err == "EACCES")
  return H.equal(b.executed, 3)
end
local function retries_and_captured_replays_never_repeat_action()
  local f, a, b = System.new()
  local id = assert(a.rpc:begin("server", "power", "set", "Owner", {value = 10}))
  f:drain(); assert(a.rpc:take(id).value == 10 and b.executed == 1)
  local recorded = {}; for _, packet in ipairs(f.sent) do recorded[#recorded + 1] = packet end
  for _ = 1, 3 do for _, packet in ipairs(recorded) do f:deliver(packet) end; f:drain() end
  assert(b.executed == 1)
  b.rpc:stop(); b.rpc = RPC.new(b, {certificate = b.certificate}); b.rpc:start()
  for _, packet in ipairs(recorded) do f:deliver(packet) end
  f:drain()
  return H.equal(b.executed, 1)
end
local function forged_frames_and_wrong_nick_never_reach_dispatch()
  local f, a, b = System.new()
  local id, err = a.rpc:begin("server", "defense", "arm", "Admin", {})
  assert(not id and err == "NO_CLIENT_IDENTITY")
  local cert = System.certificate("evil", "Owner", {"other-card"}, {"client"}, {["*"] = {"*"}})
  local fake = Fake.new("evil")
  local body = {v = 1, kind = "hello", id = string.rep("a", 64), client_nonce = string.rep("b", 64), src = "client", dst = "server", port = 27016, request = "payload"}
  a.network:send("server", 27016, Protocol.sign(fake, cert, body), "client", "rpc")
  body.src = "other-card"
  a.network:send("server", 27016, Protocol.sign(fake, cert, body), "client", "rpc")
  a.network:send("server", 27016, "return os.execute('bad')", "client", "rpc")
  f:drain()
  return H.truth(b.executed == 0 and b.rpc.stats.denied >= 3)
end
local function revocation_and_grants_prevent_commands()
  local f, a, b = System.new()
  local restricted = System.certificate("limited", "Admin", {"client"}, {"client"}, {power = {"snapshot"}})
  assert(a.rpc:addIdentity(restricted, Fake.new("limited")))
  local id, err = a.rpc:begin("server", "defense", "arm", "Admin", {})
  assert(not id and err == "CERTIFICATE_DENIED")
  b.trust:revoke("client-key")
  id = assert(a.rpc:begin("server", "power", "set", "Owner", {})); f:drain(); f:advance(5)
  local result, timeout = a.rpc:take(id)
  return H.truth(result == nil and timeout == "ETIMEDOUT" and b.executed == 0)
end
local function dropped_reply_retries_same_challenge_and_shutdown_completes_waiters()
  local f, a, b = System.new()
  -- Complete hello/challenge/invoke but drop the first server result at the wire.
  local original, dropped = f.deliver, false
  f.deliver = function(self, packet)
    if packet.source == "server" and b.executed == 1 and not dropped then dropped = true; return end
    return original(self, packet)
  end
  local result = assert(a.rpc:request("server", "power", "set", "Owner", {value = 42}))
  assert(result.value == 42 and b.executed == 1 and dropped)
  local id = assert(a.rpc:begin("server", "power", "set", "Owner", {}))
  a.rpc:stop()
  local value, err = a.rpc:take(id)
  return H.truth(value == nil and err == "ESHUTDOWN")
end
local function completed_cache_never_exhausts_live_call_quota_or_replays_after_eviction()
  local f, a, b = System.new()
  local first = {}
  for index = 1, 40 do
    assert(a.rpc:request("server", "power", "set", "Owner", {value = index}).value == index)
    if index == 1 then for _, packet in ipairs(f.sent) do first[#first + 1] = packet end end
  end
  assert(b.executed == 40)
  local count = 0; for _ in pairs(b.rpc.inbound) do count = count + 1 end
  assert(count <= 32)
  for _, packet in ipairs(first) do f:deliver(packet) end
  f:drain()
  return H.equal(b.executed, 40)
end
local function wrong_server_address_certificate_cannot_elicit_client_invoke()
  local f, a, b = System.new()
  local codec = require("spacecross.core.codec")
  local network = require("spacecross.network.protocol")
  local original = f.deliver
  local wrong = System.certificate("server-key", "Ship", {"other-server"}, {"server"})
  f.deliver = function(self, packet)
    if packet.source == "server" then
      local data = assert(network.decode(packet.wire, 8192, 256))
      local envelope = assert(codec.decode(data.body, 98304))
      envelope.certificate = wrong
      data.body = codec.encode(envelope)
      packet = require("spacecross.core.util").copy(packet); packet.wire = network.encode(data)
    end
    return original(self, packet)
  end
  local value, err = a.rpc:request("server", "power", "set", "Owner", {})
  return H.truth(value == nil and err == "ETIMEDOUT" and b.executed == 0)
end
local function revocation_between_hello_and_proof_is_enforced()
  local f, a, b = System.new()
  local original = f.deliver
  f.deliver = function(self, packet)
    if packet.source == "server" then b.trust:revoke("client-key") end
    return original(self, packet)
  end
  local value, err = a.rpc:request("server", "power", "set", "Owner", {})
  return H.truth(value == nil and err == "ETIMEDOUT" and b.executed == 0)
end
local function signing_failure_after_dispatch_cannot_repeat_physical_action()
  local _, a, b = System.new()
  local original, recovered = b.crypto.sign, false
  b.crypto.sign = function(data)
    if b.executed > 0 and not recovered then error("data card lost power") end
    return original(data)
  end
  b.event.timer(1, function() recovered = true end)
  local value, err = a.rpc:request("server", "power", "set", "Owner", {})
  return H.truth(value == nil and err == "ERR_RPC_RESULT" and b.executed == 1)
end
local function shutdown_during_crypto_yield_cannot_create_or_execute_late_calls()
  local f, a, b = System.new()
  local sign = a.crypto.sign
  a.crypto.sign = function(data) a.rpc:stop(); return sign(data) end
  local id, err = a.rpc:begin("server", "power", "set", "Owner", {})
  assert(not id and err == "ESHUTDOWN" and not next(a.rpc.clients))
  a.crypto.sign = sign; a.rpc:start()
  local verify = b.crypto.verify
  b.crypto.verify = function(...) b.rpc:stop(); return verify(...) end
  assert(a.rpc:begin("server", "power", "set", "Owner", {}))
  f:drain()
  assert(b.executed == 0 and not next(b.rpc.inbound))
  a.rpc:stop(); return H.success()
end
local all_tests = {
  {test_name = "authenticated_request_uses_certificate_subject_and_preserves_false", test = authenticated_request_uses_certificate_subject_and_preserves_false},
  {test_name = "retries_and_captured_replays_never_repeat_action", test = retries_and_captured_replays_never_repeat_action},
  {test_name = "forged_frames_and_wrong_nick_never_reach_dispatch", test = forged_frames_and_wrong_nick_never_reach_dispatch},
  {test_name = "revocation_and_grants_prevent_commands", test = revocation_and_grants_prevent_commands},
  {test_name = "dropped_reply_retries_same_challenge_and_shutdown_completes_waiters", test = dropped_reply_retries_same_challenge_and_shutdown_completes_waiters},
  {test_name = "completed_cache_never_exhausts_live_call_quota_or_replays_after_eviction", test = completed_cache_never_exhausts_live_call_quota_or_replays_after_eviction},
  {test_name = "wrong_server_address_certificate_cannot_elicit_client_invoke", test = wrong_server_address_certificate_cannot_elicit_client_invoke},
  {test_name = "revocation_between_hello_and_proof_is_enforced", test = revocation_between_hello_and_proof_is_enforced},
  {test_name = "signing_failure_after_dispatch_cannot_repeat_physical_action", test = signing_failure_after_dispatch_cannot_repeat_physical_action},
  {test_name = "shutdown_during_crypto_yield_cannot_create_or_execute_late_calls", test = shutdown_during_crypto_yield_cannot_create_or_execute_late_calls},
}
return all_tests
