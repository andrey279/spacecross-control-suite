local UI = require("spacecross.ui.framework")
local GPU = require("spacecross.ui.tests.stubs.gpu")
local Tab = require("spacecross.ui.turret_tab")
local H = require("tests.support")

local function multi_host_turret_buttons_route_to_their_own_host()
  local gpu, calls = GPU(), {}
  gpu.width, gpu.height = 60, 14
  local ui = UI.new({authorize = function(player) return player == "Owner" end,
    request = function(endpoint, action, player, args)
      if action == "snapshot" then
        return {turrets = {{address = endpoint.host .. "-turret", status = {
          active = false, mode = 1, modes = {1, 2},
        }}}, failures = {}}
      end
      calls[#calls + 1] = {endpoint.host, action, player, args.address, args.mode}
      return true
    end})
  ui:addPanel("main", gpu, "screen", "Owner")
  ui:addTab("main", Tab.new({{host = "host-a", model = "turrets"}, {host = "host-b", model = "turrets"}}))
  assert(ui:select("main", "turrets"))
  assert(ui:input("main", {"touch", "screen", 2, 5, 0, "Owner"}))
  assert(calls[1][1] == "host-a" and calls[1][2] == "toggle" and calls[1][4] == "host-a-turret")
  assert(ui:input("main", {"touch", "screen", 2, 7, 0, "Owner"}))
  assert(calls[2][1] == "host-b" and calls[2][2] == "toggle" and calls[2][4] == "host-b-turret")
  assert(ui:input("main", {"touch", "screen", 11, 7, 0, "Owner"}))
  assert(calls[3][1] == "host-b" and calls[3][2] == "turn_on")
  assert(ui:input("main", {"touch", "screen", 2, 5, 0, "Admin"}) == nil)
  return H.truth(#calls == 3)
end

local all_tests = {
  {test_name = "multi_host_turret_buttons_route_to_their_own_host", test = multi_host_turret_buttons_route_to_their_own_host},
}
return all_tests
