local util = require("spacecross.core.util")
local M = {}

local function validTypes(types)
  assert(type(types) == "table" and #types > 0 and #types <= 16, "configure OMT component types")
  local seen = {}
  for i, value in ipairs(types) do
    assert(type(value) == "string" and value:match("^[%w_-]+$") and not seen[value], "invalid OMT component type")
    seen[value] = true
  end
  return types
end

local function definition(types, options)
  return {id = "omt_turret", types = types, kind = "turret", new = function()
    local self = {}
    function self:init(proxy)
      assert(type(proxy.toggle) == "function", "OMT toggle API unavailable")
      assert(type(proxy.setMode) == "function", "OMT setMode API unavailable")
      self.proxy = proxy
      return true
    end
    function self:isOperational()
      if options.activeMethod and type(self.proxy[options.activeMethod]) == "function" then
        return type(self.proxy[options.activeMethod]()) == "boolean"
      end
      return type(self.proxy.toggle) == "function" and type(self.proxy.setMode) == "function"
    end
    function self:getEnergyLevel()
      local current, maximum = options.currentEnergyMethod, options.maxEnergyMethod
      if not current or not maximum then return nil, "ENOTSUP" end
      if type(self.proxy[current]) ~= "function" or type(self.proxy[maximum]) ~= "function" then return nil, "ENOTSUP" end
      local stored, capacity = self.proxy[current](), self.proxy[maximum]()
      if type(stored) ~= "number" or type(capacity) ~= "number" or stored < 0 or capacity < 0 or stored > capacity then
        return nil, "INVALID_ENERGY_TELEMETRY"
      end
      return {stored = stored, capacity = capacity}
    end
    function self:getMode()
      local method = options.getModeMethod
      if type(self.proxy[method]) ~= "function" then return nil, "ENOTSUP" end
      local mode = self.proxy[method]()
      if type(mode) ~= "number" or mode % 1 ~= 0 or math.abs(mode) > 2147483647 then return nil, "INVALID_TURRET_MODE" end
      return mode
    end
    function self:setMode(mode)
      assert(type(mode) == "number" and mode % 1 == 0 and math.abs(mode) <= 2147483647, "integer OMT mode required")
      if options.modes then
        local allowed = false
        for _, value in ipairs(options.modes) do if value == mode then allowed = true; break end end
        if not allowed then return nil, "EINVAL_MODE" end
      end
      local ok, err = self.proxy.setMode(mode)
      if ok == false then return nil, err or "MODE_REJECTED" end
      return true
    end
    function self:getStatus()
      local status = {modes = options.modes and util.copy(options.modes) or nil}
      if options.activeMethod then
        if type(self.proxy[options.activeMethod]) ~= "function" then return nil, "ACTIVE_STATE_UNAVAILABLE" end
        local active = self.proxy[options.activeMethod]()
        if type(active) ~= "boolean" then return nil, "ACTIVE_STATE_UNAVAILABLE" end
        status.active = active
      end
      if options.getModeMethod then
        local mode, err = self:getMode()
        if mode == nil then return nil, err end
        status.mode = mode
      end
      local energy, energyErr = self:getEnergyLevel()
      if energy then status.energy = energy elseif energyErr ~= "ENOTSUP" then return nil, energyErr end
      return status
    end
    function self:toggle()
      if type(self.proxy.toggle) ~= "function" then return nil, "ENOTSUP" end
      local result, err = self.proxy.toggle()
      if result == false then return nil, err or "TOGGLE_REJECTED" end
      return true
    end
    function self:turn_off()
      local method = options.activeMethod
      if not method then return nil, "ENOTSUP" end
      if type(self.proxy[method]) ~= "function" then return nil, "ENOTSUP" end
      local active = self.proxy[method]()
      if active == false then return true end
      if active ~= true then return nil, "ACTIVE_STATE_UNAVAILABLE" end
      local ok, err = self:toggle()
      if not ok then return nil, err end
      if self.proxy[method]() ~= false then return nil, "TURRET_STILL_ACTIVE" end
      return true
    end
    function self:turn_on()
      local method = options.activeMethod
      if not method then return nil, "ENOTSUP" end
      if type(self.proxy[method]) ~= "function" then return nil, "ENOTSUP" end
      local active = self.proxy[method]()
      if active == true then return true end
      if active ~= false then return nil, "ACTIVE_STATE_UNAVAILABLE" end
      local ok, err = self:toggle()
      if not ok then return nil, err end
      if self.proxy[method]() ~= true then return nil, "TURRET_STILL_INACTIVE" end
      return true
    end
    return self
  end}
end

function M.configure(options)
  options = options or {}
  local allowed = {types = true, activeMethod = true, currentEnergyMethod = true,
    maxEnergyMethod = true, getModeMethod = true, modes = true}
  for key in pairs(options) do assert(allowed[key], "unknown OMT driver option: " .. tostring(key)) end
  for _, key in ipairs({"activeMethod", "currentEnergyMethod", "maxEnergyMethod", "getModeMethod"}) do
    if options[key] ~= nil then assert(type(options[key]) == "string" and options[key]:match("^[%a_][%w_]*$"), "invalid OMT method option") end
  end
  if options.modes ~= nil then
    assert(type(options.modes) == "table" and #options.modes > 0 and #options.modes <= 16, "invalid OMT mode list")
    local seen = {}
    for i, value in ipairs(options.modes) do
      assert(type(value) == "number" and value % 1 == 0 and math.abs(value) <= 2147483647 and not seen[value], "invalid OMT mode")
      seen[value] = true
    end
  end
  return definition(validTypes(options.types), options)
end

return M
