local Policy = require("spacecross.defense.policy")
local Access = require("spacecross.defense.access")
local util = require("spacecross.core.util")
local M = {}
function M.new(deps, config)
  assert(not config.scorchedEarth or (type(config.heartbeatTimeout) == "number" and config.heartbeatTimeout > 0))
  local policy, access = Policy.new(config), Access.new(config)
  local self = {armed = config.armed == true, fired = false, lastHeartbeat = deps.clock(), running = false}
  function self:heartbeat(proof)
    if not deps.verifyHeartbeat then return nil, "NO_TRUSTED_HEARTBEAT_VERIFIER" end
    local ok, verified = pcall(deps.verifyHeartbeat, proof)
    if not ok or verified ~= true then return nil, "EACCES" end
    self.lastHeartbeat = deps.clock()
    return true
  end
  function self:setArmed(player, value)
    if not access:authorize(player, value and "arm" or "disarm") then return nil, "EACCES" end
    if self.fired then return nil, "ALREADY_FIRED" end
    self.armed = value == true
    return true
  end
  function self:tick()
    local decision = policy:evaluate(deps.watcher:snapshot(), deps.clock() - self.lastHeartbeat)
    self.decision = decision
    local fingerprint = require("spacecross.core.codec").encode(decision.alerts)
    if fingerprint ~= self.lastAlerts then
      self.lastAlerts = fingerprint
      for _, alert in ipairs(decision.alerts) do
        if deps.log then deps.log("critical", alert.code, alert) end
      end
    end
    if self.armed and decision.trigger and not self.fired then
      self.fired = deps.actuator:fire(table.concat(decision.reasons, ",")) == true
    end
    return util.copy(decision)
  end
  function self:snapshot()
    return {armed = self.armed, fired = self.fired, heartbeatAge = deps.clock() - self.lastHeartbeat,
      decision = util.copy(self.decision)}
  end
  function self:start()
    if self.running then return false end
    self.timer = deps.event.timer(config.interval or 1, function()
      local ok, err = pcall(self.tick, self)
      if not ok and deps.log then deps.log("error", "ERR_DEFENSE", {error = tostring(err)}) end
    end, math.huge)
    self.running = true
    return true
  end
  function self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    self.running = false
  end
  return self
end
return M
