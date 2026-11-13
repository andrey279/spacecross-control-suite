local util = require("spacecross.core.util")
local M = {}
local required = {"init", "getEnergyLevel", "turn_off", "isOperational"}

function M.new(deps)
  local self = {definitions = {}, instances = {}, running = false}
  local function report(address, err)
    self.lastError = {address = address, code = "ERR_COMPONENT_UNREACHABLE", error = tostring(err)}
    if deps.log then pcall(deps.log, "error", "ERR_COMPONENT_UNREACHABLE", self.lastError) end
  end
  function self:register(definition)
    assert(type(definition.id) == "string" and type(definition.types) == "table")
    assert(type(definition.new) == "function" and not self.definitions[definition.id], "invalid/duplicate driver")
    for _, other in pairs(self.definitions) do
      for _, a in ipairs(other.types) do
        for _, b in ipairs(definition.types) do
          assert(a ~= b or type(other.matches) == "function" or type(definition.matches) == "function", "ambiguous component type: " .. a)
        end
      end
    end
    self.definitions[definition.id] = definition
    if self.running then self:scan() end
  end
  function self:add(address, componentType)
    if self.instances[address] then return true end
    local matches = {}
    for _, id in ipairs(util.sortedKeys(self.definitions)) do
      local definition = self.definitions[id]
      for _, accepted in ipairs(definition.types) do
        if accepted == componentType then
          local ok, acceptedAddress = true, true
          if definition.matches then ok, acceptedAddress = pcall(definition.matches, address, componentType) end
          if not ok then report(address, acceptedAddress); return nil, acceptedAddress end
          if acceptedAddress then matches[#matches + 1] = definition end
          break
        end
      end
    end
    if #matches > 1 then report(address, "ERR_AMBIGUOUS_DRIVER"); return nil, "ERR_AMBIGUOUS_DRIVER" end
    local definition = matches[1]
    if definition then
      local ok, driver = pcall(function()
        local instance = definition.new({registry = self, event = deps.event, log = deps.log})
        for _, method in ipairs(required) do
          assert(type(instance[method]) == "function", "driver contract missing " .. method)
        end
        instance.address, instance.kind = address, definition.kind
        local initialized, err = instance:init(assert(deps.component.proxy(address)))
        assert(initialized, err or "driver init rejected")
        return instance
      end)
      if not ok then report(address, driver); return nil, driver end
      self.instances[address] = driver
      return true
    end
    return false, "no driver"
  end
  function self:remove(address)
    local driver = self.instances[address]
    self.instances[address] = nil
    if driver and driver.close then
      local ok, err = pcall(driver.close, driver)
      if not ok then report(address, err) end
    end
  end
  function self:scan()
    local present = {}
    for address, kind in deps.component.list() do present[address] = true; self:add(address, kind) end
    for address in pairs(self.instances) do if not present[address] then self:remove(address) end end
  end
  function self:list(kind)
    local result = {}
    for _, address in ipairs(util.sortedKeys(self.instances)) do
      local instance = self.instances[address]
      if not kind or instance.kind == kind then result[#result + 1] = instance end
    end
    return result
  end
  function self:call(address, method, ...)
    local instance = self.instances[address]
    if not instance or type(instance[method]) ~= "function" then return nil, "ENOTSUP" end
    local ok, value, extra = pcall(instance[method], instance, ...)
    if not ok then report(address, value); return nil, "ERR_COMPONENT_UNREACHABLE" end
    if value == nil or (value == false and extra ~= nil) then return nil, extra or "ERR_DRIVER_REJECTED" end
    return value, extra
  end
  function self:all(kind, method, ...)
    local results = {}
    for _, instance in ipairs(self:list(kind)) do
      local value, err = self:call(instance.address, method, ...)
      results[instance.address] = {ok = value ~= nil, value = value, error = err}
    end
    return results
  end
  local added = function(_, address, kind) self:add(address, kind) end
  local removed = function(_, address) self:remove(address) end
  function self:start()
    if self.running then return false end
    deps.event.listen("component_added", added)
    deps.event.listen("component_removed", removed)
    self.running = true
    self:scan()
    return true
  end
  function self:stop()
    if not self.running then return end
    deps.event.ignore("component_added", added)
    deps.event.ignore("component_removed", removed)
    self.running = false
    for _, instance in ipairs(self:list()) do self:remove(instance.address) end
  end
  return self
end
return M
