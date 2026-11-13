local UI = require("spacecross.ui.framework")
local GPU = require("spacecross.ui.tests.stubs.gpu")
local H = require("tests.support")
local function tab_changed_while_waiting_never_draws_old_model_data()
  local ui, oldDraws, newDraws, deactivated = nil, 0, 0, 0
  ui = UI.new({request = function(endpoint)
    if endpoint.model == "old" then
      local ok, err = ui:select("main", "new")
      assert(ok == nil and err == "EBUSY")
    end
    return {current = true}
  end})
  ui:addPanel("main", GPU(), "screen", "Owner")
  ui:addTab("main", {id = "old", endpoints = {{model = "old"}}, draw = function() oldDraws = oldDraws + 1 end,
    deactivate = function() deactivated = deactivated + 1 end})
  ui:addTab("main", {id = "new", endpoints = {{model = "new"}}, draw = function() newDraws = newDraws + 1 end})
  local ok, err = ui:select("main", "old")
  assert(ok == nil and err == "VIEW_CHANGED" and oldDraws == 0 and deactivated == 1)
  assert(ui:refresh("main") and newDraws == 1)
  return H.success()
end
local all_tests = {
  {test_name = "tab_changed_while_waiting_never_draws_old_model_data", test = tab_changed_while_waiting_never_draws_old_model_data},
}
return all_tests
