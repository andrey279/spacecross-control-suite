local Model = require("spacecross.shields.model")
local H = require("tests.support")

local function shield_model_owner_checks_commands_and_uses_fresh_hal_status()
  local active, commandLog = false, {}
  local driver = {
    address = "shield-1", kind = "shield",
    getStatus = function() return {active = active, composed = true, redstoneMode = "On"} end,
    turn_on = function() active = true; commandLog[#commandLog + 1] = "on"; return true end,
    turn_off = function() active = false; commandLog[#commandLog + 1] = "off"; return true end,
    compose = function(_, disconnected) commandLog[#commandLog + 1] = disconnected and "composeDsc" or "compose"; return true end,
    decompose = function() commandLog[#commandLog + 1] = "decompose"; return true end,
    setRedstoneMode = function(_, mode) commandLog[#commandLog + 1] = mode; return true end,
  }
  local hal = {registry = {instances = {['shield-1'] = driver}, list = function(_, kind) assert(kind == "shield"); return {driver} end},
    call = function(_, address, method, ...)
      assert(address == "shield-1")
      return driver[method](driver, ...)
    end}
  local model = Model.new(hal, function(actor) return actor == "Owner" end)
  assert(model:snapshot().shields[1].status.active == false)
  assert(model:command("turn_on", {address = "shield-1"}, "Admin") == nil)
  assert(model:snapshot().shields[1].status.active == false)
  assert(model:command("turn_on", {address = "shield-1"}, "Owner"))
  assert(model:snapshot().shields[1].status.active == true)
  assert(model:command("composeDisconnected", {address = "shield-1"}, "Owner"))
  assert(model:command("setRedstoneMode", {address = "shield-1", mode = "Off"}, "Owner"))
  assert(model:command("decompose", {address = "shield-1"}, "Owner"))
  assert(model:command("turn_off", {address = "foreign"}, "Owner") == nil)
  assert(commandLog[1] == "on" and commandLog[2] == "composeDsc" and commandLog[3] == "Off" and commandLog[4] == "decompose")
  return H.success()
end

local all_tests = {
  {test_name = "shield_model_owner_checks_commands_and_uses_fresh_hal_status", test = shield_model_owner_checks_commands_and_uses_fresh_hal_status},
}
return all_tests
