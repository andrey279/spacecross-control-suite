local Deployer = require("spacecross.structures.deployer")
local Platform = require("tests.stubs.platform")
local H = require("tests.support")

local function route_waits_for_navigation_deployment_provision_and_confirmation()
  local p, events = Platform.new(), {}
  local autopilot = {status = "idle"}
  function autopilot:navigate(target) events[#events + 1] = {"navigate", target.x}; self.status = "moving"; return true end
  function autopilot:snapshot() return {state = self.status} end
  function autopilot:cancel() self.status = "cancelled"; return true end
  local deployer = Deployer.new({autopilot = autopilot, clock = p.clock, event = p.event,
    deploy = function(point) events[#events + 1] = {"deploy", point.x}; return {computerAddress="built-computer"} end,
    provisionComputer = function(point, program, index, receipt)
      assert(receipt.computerAddress=="built-computer"); events[#events + 1] = {"provision", point.x, program}; return true
    end,
    confirm = function(point, index, receipt)
      assert(receipt.computerAddress=="built-computer"); events[#events + 1] = {"confirm", point.x}; return true
    end},
    {program = "mine-controller", interval = 1})
  assert(deployer:activate())
  assert(deployer:start({{x = 1, y = 64, z = 1}, {x = 2, y = 64, z = 2}}))
  deployer:tick(); assert(deployer.phase == "travel")
  autopilot.status = "done"; deployer:tick(); assert(deployer.phase == "deploy")
  deployer:tick(); deployer:tick(); deployer:tick(); assert(deployer.index == 2 and deployer.phase == "navigate")
  deployer:tick(); autopilot.status = "done"; deployer:tick()
  deployer:tick(); deployer:tick(); deployer:tick(); deployer:tick()
  assert(deployer.state == "done" and #events == 8)
  assert(events[3][1] == "provision" and events[3][3] == "mine-controller")
  deployer:deactivate()
  return H.truth(not next(p.timers))
end

local function invalid_routes_and_unconfirmed_builds_do_not_advance()
  local p = Platform.new()
  local autopilot = {navigate = function() return true end, snapshot = function() return {state = "done"} end}
  local deployer = Deployer.new({autopilot = autopilot, clock = p.clock, event = p.event,
    deploy = function() return true end, provisionComputer = function() return true end,
    confirm = function() return nil, "PENDING" end}, {program = "mine-controller"})
  assert(deployer:activate())
  assert(deployer:start({{x = 1.5, y = 64, z = 1}}) == nil)
  assert(deployer:start({{x = 1, y = 64, z = 1}}))
  for _ = 1, 5 do deployer:tick() end
  assert(deployer.phase == "confirm" and deployer.index == 1 and deployer.state == "running")
  deployer:deactivate()
  return H.truth(not next(p.timers))
end

local function cancelled_and_timed_out_navigation_fail_the_deployment()
  local p=Platform.new(); local autopilot={status="idle"}
  function autopilot:navigate() self.status="planning"; return true end
  function autopilot:snapshot() return {state=self.status} end
  function autopilot:cancel() self.status="cancelled"; return true end
  local deps={autopilot=autopilot,clock=p.clock,event=p.event,deploy=function() return true end,
    provisionComputer=function() return true end,confirm=function() return true end}
  local deployer=Deployer.new(deps,{program="mine",navigationTimeout=2})
  deployer:activate(); deployer:start({{x=1,y=64,z=1}}); deployer:tick()
  autopilot.status="cancelled"; deployer:tick()
  assert(deployer.state=="error" and deployer.error=="NAVIGATION_CANCELLED")
  deployer:deactivate()

  local p2=Platform.new(); deps.clock=p2.clock; deps.event=p2.event
  autopilot.status="idle"
  local timeout=Deployer.new(deps,{program="mine",navigationTimeout=2})
  timeout:activate(); timeout:start({{x=1,y=64,z=1}}); timeout:tick(); p2:advance(2)
  assert(timeout.state=="error" and timeout.error=="NAVIGATION_TIMEOUT" and autopilot.status=="cancelled")
  timeout:deactivate()
  return H.truth(not next(p2.timers))
end

local all_tests = {
  {test_name = "route_waits_for_navigation_deployment_provision_and_confirmation", test = route_waits_for_navigation_deployment_provision_and_confirmation},
  {test_name = "invalid_routes_and_unconfirmed_builds_do_not_advance", test = invalid_routes_and_unconfirmed_builds_do_not_advance},
  {test_name = "cancelled_and_timed_out_navigation_fail_the_deployment", test = cancelled_and_timed_out_navigation_fail_the_deployment},
}
return all_tests
