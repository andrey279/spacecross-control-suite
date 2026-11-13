local M = {}
local actions = {toggle = "toggle", turn_on = "turn_on", turn_off = "turn_off", setMode = "setMode"}

function M.new(hal, isOwner)
  local self = {}
  function self:snapshot()
    local turrets, failures = {}, {}
    for _, instance in ipairs(hal.registry:list("turret")) do
      local status, err = hal:call(instance.address, "getStatus")
      if status then turrets[#turrets + 1] = {address = instance.address, status = status}
      else failures[#failures + 1] = {address = instance.address, error = err or "UNAVAILABLE"} end
    end
    return {turrets = turrets, failures = failures}
  end
  function self:command(action, args, actor)
    if not isOwner(actor) then return nil, "EACCES" end
    args = args or {}
    local address = args.address
    local instance = type(address) == "string" and hal.registry.instances[address]
    if not instance or instance.kind ~= "turret" then return nil, "ENOENT_TURRET" end
    local method = actions[action]
    if not method then return nil, "ENOTSUP" end
    if action == "setMode" then return hal:call(address, method, args.mode) end
    return hal:call(address, method)
  end
  return self
end

return M
