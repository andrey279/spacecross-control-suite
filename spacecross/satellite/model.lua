local M = {}
function M.new(satellite, isOwner)
  local self = {}
  function self:snapshot() return satellite:snapshot() end
  function self:command(action, args, actor)
    if not isOwner(actor) then return nil, "EACCES" end
    args = args or {}
    if action == "setMode" then return satellite:setMode(args.mode) end
    if action == "scan" then return satellite:scan() end
    if action == "attack" then return satellite:attack(args.target) end
    return nil, "ENOTSUP"
  end
  return self
end
return M
