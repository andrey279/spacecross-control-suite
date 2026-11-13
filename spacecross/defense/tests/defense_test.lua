local Policy = require("spacecross.defense.policy")
local Controller = require("spacecross.defense.controller")
local Destruct = require("spacecross.defense.destruct")
local Access = require("spacecross.defense.access")
local P = require("tests.stubs.platform")
local H = require("tests.support")
local function either_condition_triggers_and_any_owner_suppresses_intrusion()
  local policy = Policy.new({owners = {"Owner", "Second"}, admins = {"Admin"},
    scorchedEarth = true, heartbeatTimeout = 10})
  local cases = {
    {names = {"Guest"}, age = 0, trigger = true},
    {names = {"Guest", "owner"}, age = 0, trigger = false},
    {names = {"Admin"}, age = 0, trigger = false},
    {names = {}, age = 11, trigger = true},
    {names = {"Guest", "Owner"}, age = 11, trigger = true},
    {names = {"Guest", "Admin"}, age = 0, trigger = true},
    {names = {}, age = 10, trigger = false},
  }
  for _, item in ipairs(cases) do
    local snapshot = {complete = true, entities = {}}
    for _, name in ipairs(item.names) do snapshot.entities[#snapshot.entities + 1] = {name = name} end
    assert(policy:evaluate(snapshot, item.age).trigger == item.trigger)
  end
  local admin = policy:evaluate({complete = true, entities = {{name = "Admin"}}}, 0)
  return H.equal(admin.alerts[1].code, "ADMIN_PRESENT")
end
local function missing_sensor_evidence_does_not_prove_owner_absence()
  local policy = Policy.new({owners = {"Owner"}})
  local result = policy:evaluate({complete = false, entities = {{name = "Guest"}}}, 0)
  return H.truth(not result.trigger and result.inconclusive and #result.alerts == 1)
end
local function heartbeat_requires_proof_and_firing_is_latched()
  local p, fired = P.new(), 0
  p.watcher = {snapshot = function() return {complete = true, entities = {}} end}
  p.actuator = {fire = function() fired = fired + 1; return true end}
  p.verifyHeartbeat = function(proof) return proof == "signed-proof" end
  local defense = Controller.new(p, {owners = {"Owner"}, admins = {"Admin"}, armed = true,
    scorchedEarth = true, heartbeatTimeout = 10})
  assert(not defense:heartbeat("spoofed"))
  p.time = 5; assert(defense:heartbeat("signed-proof"))
  p.time = 11; assert(not defense:tick().trigger)
  assert(not defense:setArmed("Admin", false) and not defense:setArmed(nil, false))
  p.time = 16; assert(defense:tick().trigger)
  defense:tick(); defense:tick()
  assert(defense:snapshot().fired)
  return H.equal(fired, 1)
end
local function disarmed_monitor_only_reports_and_owner_can_arm()
  local p, fired = P.new(), 0
  p.watcher = {snapshot = function() return {complete = true, entities = {{name = "Guest"}}} end}
  p.actuator = {fire = function() fired = fired + 1; return true end}
  local defense = Controller.new(p, {owners = {"Owner"}})
  assert(defense:tick().trigger and fired == 0)
  assert(defense:setArmed("owner", true)); defense:tick()
  return H.equal(fired, 1)
end
local function actuator_continues_and_retries_only_failed_channels()
  local calls, broken = {}, true
  local actuator = Destruct.new({hal = {call = function(_, address)
    calls[address] = (calls[address] or 0) + 1
    if address == "bad" and broken then return nil, "unreachable" end
    return true
  end}}, {{address = "bad", side = 1}, {address = "good", side = 2}})
  assert(not actuator:fire("test") and calls.good == 1)
  broken = false; assert(actuator:fire("test"))
  return H.truth(calls.good == 1 and calls.bad == 2)
end
local function access_requires_actor_and_limits_configuration_to_owners()
  local access = Access.new({owners = {"Owner"}, admins = {"Admin"}})
  assert(not access:authorize(nil, "snapshot") and not access:authorize("", "snapshot"))
  assert(access:authorize("admin", "snapshot") and not access:authorize("Admin", "configure"))
  return H.truth(access:authorize("OWNER", "configure"))
end
local all_tests = {
  {test_name = "either_condition_triggers_and_any_owner_suppresses_intrusion", test = either_condition_triggers_and_any_owner_suppresses_intrusion},
  {test_name = "missing_sensor_evidence_does_not_prove_owner_absence", test = missing_sensor_evidence_does_not_prove_owner_absence},
  {test_name = "heartbeat_requires_proof_and_firing_is_latched", test = heartbeat_requires_proof_and_firing_is_latched},
  {test_name = "disarmed_monitor_only_reports_and_owner_can_arm", test = disarmed_monitor_only_reports_and_owner_can_arm},
  {test_name = "actuator_continues_and_retries_only_failed_channels", test = actuator_continues_and_retries_only_failed_channels},
  {test_name = "access_requires_actor_and_limits_configuration_to_owners", test = access_requires_actor_and_limits_configuration_to_owners},
}
return all_tests
