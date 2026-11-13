local M = {}
function M.new(config)
  local self = {owners = {}, admins = {}}
  for _, name in ipairs(config.owners or {}) do self.owners[name:lower()] = true end
  for _, name in ipairs(config.admins or {}) do self.admins[name:lower()] = true end
  function self:role(name)
    if type(name) ~= "string" or name == "" then return nil end
    if self.owners[name:lower()] then return "owner" end
    if self.admins[name:lower()] then return "admin" end
  end
  function self:authorize(name, action)
    local role = self:role(name)
    if action == "arm" or action == "disarm" or action == "configure" then return role == "owner" end
    return role ~= nil
  end
  return self
end
return M
