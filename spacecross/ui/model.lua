local util = require("spacecross.core.util")
local M = {}
-- Lives on the controller host. A transport exposes exactly this API remotely.
function M.new(authorize)
  local self = {models = {}}
  function self:register(id, model)
    assert(not self.models[id] and type(model.snapshot) == "function")
    self.models[id] = model
  end
  function self:list() return util.sortedKeys(self.models) end
  function self:catalog(player)
    if not authorize(player, "snapshot") then return nil, "EACCES" end
    return self:list()
  end
  function self:request(id, action, player, args)
    if not authorize(player, action) then return nil, "EACCES" end
    local model = self.models[id]
    if not model then return nil, "ENOENT_MODEL" end
    local handler = action == "snapshot" and model.snapshot or model.command
    if not handler then return nil, "ENOTSUP" end
    local ok, result, err = pcall(handler, model, action == "snapshot" and nil or action, util.copy(args or {}), player)
    if not ok then return nil, "ERR_MODEL: " .. tostring(result) end
    return util.copy(result), err
  end
  return self
end
return M
