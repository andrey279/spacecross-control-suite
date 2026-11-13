local Access = require("spacecross.defense.access")
local M = {}
function M.new(config)
  local access = Access.new(config)
  local self = {}
  function self:evaluate(snapshot, heartbeatAge)
    local ownerPresent, strangers, admins = false, {}, {}
    for _, entity in ipairs(snapshot.entities or {}) do
      local role = access:role(entity.name)
      if role == "owner" then ownerPresent = true
      elseif role == "admin" then admins[#admins + 1] = entity.name
      else strangers[#strangers + 1] = entity.name end
    end
    local reasons, alerts = {}, {}
    if #admins > 0 then alerts[#alerts + 1] = {code = "ADMIN_PRESENT", players = admins} end
    if #strangers > 0 then
      alerts[#alerts + 1] = {code = "INTRUDER_DETECTED", players = strangers}
      if config.intrusion ~= false and snapshot.complete and not ownerPresent then
        reasons[#reasons + 1] = "UNAUTHORIZED_WITHOUT_OWNER"
      end
    end
    if config.scorchedEarth and heartbeatAge > assert(config.heartbeatTimeout) then
      reasons[#reasons + 1] = "TRUSTED_HEARTBEAT_TIMEOUT"
    end
    return {trigger = #reasons > 0, reasons = reasons, alerts = alerts, ownerPresent = ownerPresent,
      inconclusive = not snapshot.complete}
  end
  return self
end
return M
