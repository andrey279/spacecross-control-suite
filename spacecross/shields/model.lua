local M = {}
local actions = {
  turn_on = "turn_on", turn_off = "turn_off", compose = "compose",
  composeDisconnected = "compose", decompose = "decompose",
}

function M.new(hal, isOwner)
  local self = {}
  function self:snapshot()
    local shields, failures = {}, {}
    for _, instance in ipairs(hal.registry:list("shield")) do
      local status, err = hal:call(instance.address, "getStatus")
      if status then shields[#shields + 1] = {address = instance.address, status = status}
      else failures[#failures + 1] = {address = instance.address, error = err or "UNAVAILABLE"} end
    end
    return {shields = shields, failures = failures}
  end
  function self:command(action, args, actor)
    if not isOwner(actor) then return nil, "EACCES" end
    args = args or {}
    if type(args.address) ~= "string" or not hal.registry.instances[args.address]
        or hal.registry.instances[args.address].kind ~= "shield" then return nil, "ENOENT_SHIELD" end
    local method = actions[action]
    if method then
      if action == "composeDisconnected" then return hal:call(args.address, method, true) end
      return hal:call(args.address, method)
    elseif action == "setRedstoneMode" then
      if args.mode ~= "Ignored" and args.mode ~= "Off" and args.mode ~= "On" then return nil, "EINVAL_MODE" end
      return hal:call(args.address, "setRedstoneMode", args.mode)
    end
    return nil, "ENOTSUP"
  end
  return self
end

return M
