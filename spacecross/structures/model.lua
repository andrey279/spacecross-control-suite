local M = {}
function M.new(deployer, isOwner)
  local self = {}
  function self:snapshot() return deployer:snapshot() end
  function self:command(action, args, actor)
    if not isOwner(actor) then return nil, "EACCES" end
    args = args or {}
    if action == "start" then return deployer:start(args.route) end
    if action == "stop" then return deployer:stop() end
    return nil, "ENOTSUP"
  end
  return self
end
return M
