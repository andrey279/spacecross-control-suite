local util = require("spacecross.core.util")
local M = {}
function M.new(deps, config)
  config = config or {}
  local allowed = config.controllers and util.set(config.controllers)
  local self = {running = false, cooling = {}, active = nil, failures = {}}
  function self:manages(address)
    local instance = deps.hal.registry.instances[address]
    return instance ~= nil and instance.kind == "navigation" and (not allowed or allowed[address] == true)
  end
  local function offline(address)
    local ok, err = deps.hal:call(address, "turn_off")
    self.failures[address] = ok and nil or err
    return ok, err
  end
  function self:setActive(address)
    if address and not self:manages(address) then return nil, "UNKNOWN_CONTROLLER" end
    local failures = {}
    for _, instance in ipairs(deps.hal.registry:list("navigation")) do
      local other = instance.address
      if other ~= address and self:manages(other) then
        if self.cooling[other] then
          if address then return nil, "EBUSY_COOLDOWN" end
        else
          local ok, err = offline(other)
          if not ok then failures[#failures + 1] = other .. ":" .. tostring(err) end
        end
      end
    end
    if #failures > 0 then return nil, table.concat(failures, ",") end
    self.active = address
    return true
  end
  function self:markCooling(address)
    if address ~= self.active or not self:manages(address) then return nil, "NOT_ACTIVE_CONTROLLER" end
    self.cooling[address] = true
    return true
  end
  function self:abort(address)
    self.cooling[address] = nil
    if address == self.active then self.active = nil end
    return offline(address)
  end
  local function cooled(_, address)
    if not self:manages(address) then return end
    local pending = self.cooling[address]
    self.cooling[address] = nil
    if address ~= self.active then offline(address) end
    if pending then deps.event.push("spacecross_core_cooled", address) end
  end
  local function removed(_, address)
    self.cooling[address], self.failures[address] = nil, nil
    if address == self.active then self.active = nil end
  end
  function self:snapshot() return {active = self.active, cooling = util.copy(self.cooling), failures = util.copy(self.failures)} end
  function self:start()
    if self.running then return false end
    deps.event.listen("shipCoreCooldownDone", cooled)
    deps.event.listen("component_removed", removed)
    self.running = true
    self.timer = deps.event.timer(config.retryInterval or 1, function()
      for _, address in ipairs(util.sortedKeys(self.failures)) do
        if address ~= self.active and not self.cooling[address] and self:manages(address) then offline(address) end
      end
    end, math.huge)
    return true
  end
  function self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    deps.event.ignore("shipCoreCooldownDone", cooled)
    deps.event.ignore("component_removed", removed)
    self.running = false
  end
  return self
end
return M
