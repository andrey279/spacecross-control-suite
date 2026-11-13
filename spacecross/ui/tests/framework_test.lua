local UI = require("spacecross.ui.framework")
local Model = require("spacecross.ui.model")
local GPU = require("spacecross.ui.tests.stubs.gpu")
local H = require("tests.support")
local function fresh_snapshots_merge_hosts_without_inactive_cache()
  local requests, drawn, static = 0, nil, 0
  local ui = UI.new({request = function(endpoint)
    requests = requests + 1; return {energy = endpoint.host == "a" and 10 or 20}
  end, static = function() static = static + 1 end})
  local gpu = GPU(); ui:addPanel("main", gpu, "screen", "owner")
  ui:addTab("main", {id = "energy", endpoints = {{host = "a"}, {host = "b"}}, draw = function(_, rows) drawn = rows end})
  ui:addTab("main", {id = "empty", draw = function() end})
  ui:select("main", "energy"); assert(#drawn == 2 and requests == 2)
  ui:select("main", "empty"); assert(requests == 2)
  ui:select("main", "energy"); assert(requests == 4 and static == 1)
  gpu.width = 80; ui:refresh("main"); assert(static == 2)
  assert(ui.panels.main.tabs.energy.state == nil)
  return H.equal(requests, 6)
end
local function multi_gpu_and_input_authorization()
  local commanded = nil
  local ui = UI.new({request = function(_, _, player) commanded = player; return true end,
    authorize = function(player) return player == "owner" end})
  local a, b = GPU(), GPU()
  ui:addPanel("a", a, "screen-a", "owner"); ui:addPanel("b", b, "screen-b", "owner")
  assert(a.screen ~= b.screen)
  ui:addTab("a", {id = "control", draw = function() end,
    input = function(_, command) return command({host = "local"}, "turn_off", {}) end})
  ui:select("a", "control")
  assert(not ui:input("a", {"touch", "screen-a", 1, 1, 0}))
  assert(not ui:input("a", {"touch", "screen-a", 1, 1, 0, "intruder"}))
  assert(not ui:input("a", {"touch", "screen-b", 1, 1, 0, "owner"}))
  assert(ui:input("a", {"touch", "screen-a", 1, 1, 0, "owner"}))
  return H.equal(commanded, "owner")
end
local function model_stays_on_target_and_denies_unidentified_clients()
  local model = Model.new(function(player) return player == "owner" end)
  local state = {energy = 10}
  model:register("power", {snapshot = function() return state end,
    command = function(_, action) if action == "off" then state.energy = 0 end; return true end})
  assert(not model:request("power", "off", nil))
  local snapshot = assert(model:request("power", "snapshot", "owner"))
  snapshot.energy = 100
  assert(state.energy == 10)
  assert(model:request("power", "off", "owner"))
  return H.equal(state.energy, 0)
end
local function unreachable_host_does_not_break_other_views()
  local ui = UI.new({request = function(endpoint)
    if endpoint.host == "broken" then error("disconnected") end
    return {ok = true}
  end})
  ui:addPanel("main", GPU(), "screen", "owner")
  local good, bad
  ui:addTab("main", {id = "test", endpoints = {{host = "broken"}, {host = "healthy"}},
    draw = function(_, rows, failures) good, bad = #rows, #failures end})
  assert(ui:select("main", "test"))
  return H.truth(good == 1 and bad == 1)
end
local all_tests = {
  {test_name = "fresh_snapshots_merge_hosts_without_inactive_cache", test = fresh_snapshots_merge_hosts_without_inactive_cache},
  {test_name = "multi_gpu_and_input_authorization", test = multi_gpu_and_input_authorization},
  {test_name = "model_stays_on_target_and_denies_unidentified_clients", test = model_stays_on_target_and_denies_unidentified_clients},
  {test_name = "unreachable_host_does_not_break_other_views", test = unreachable_host_does_not_break_other_views},
}
return all_tests
