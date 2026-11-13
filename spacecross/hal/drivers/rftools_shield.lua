local util = require("spacecross.core.util")
local M = {}
local modes = {Ignored = true, Off = true, On = true}

local function validateDevices(devices)
  devices = util.copy(devices or {})
  for address, value in pairs(devices) do
    assert(type(address) == "string" and address:match("^[%w%-]+$") and type(value) == "table", "invalid shield binding")
    for key in pairs(value) do
      assert(key == "controlAddress" or key == "side" or key == "activationMode" or key == "onValue" or key == "offValue",
        "unknown shield binding option: " .. tostring(key))
    end
    assert(type(value.controlAddress) == "string" and value.controlAddress:match("^[%w%-]+$"), "shield redstone controller required")
    assert(type(value.side) == "number" and value.side % 1 == 0 and value.side >= 0 and value.side <= 5, "invalid shield redstone side")
    value.activationMode = value.activationMode or "On"
    assert(value.activationMode == "On" or value.activationMode == "Off", "shield activationMode must be On or Off")
    local defaultOn, defaultOff = value.activationMode == "On" and 15 or 0, value.activationMode == "On" and 0 or 15
    value.onValue, value.offValue = value.onValue or defaultOn, value.offValue or defaultOff
    assert(type(value.onValue) == "number" and value.onValue % 1 == 0 and value.onValue >= 0 and value.onValue <= 15
      and type(value.offValue) == "number" and value.offValue % 1 == 0 and value.offValue >= 0 and value.offValue <= 15
      and value.onValue ~= value.offValue, "invalid shield redstone values")
  end
  return devices
end

function M.configure(options)
  options = options or {}
  for key in pairs(options) do assert(key == "devices", "unknown RFTools shield option: " .. tostring(key)) end
  local devices = validateDevices(options.devices)
  return {id = "rftools_shield", types = {"shield_projector"}, kind = "shield",
    matches = function(address) return next(devices) == nil or devices[address] ~= nil end,
    new = function(context)
      local self = {}
      function self:init(proxy)
        for _, name in ipairs({"isShieldActive", "isShieldComposed", "getRedstoneMode", "setRedstoneMode",
            "composeShield", "decomposeShield"}) do
          assert(type(proxy[name]) == "function", "RFTools shield API missing " .. name)
        end
        self.proxy, self.settings = proxy, devices[self.address]
        return true
      end
      function self:isOperational()
        return type(self.proxy.isShieldComposed()) == "boolean"
      end
      function self:getEnergyLevel() return nil, "ENOTSUP" end
      function self:getStatus()
        local active, composed, mode = self.proxy.isShieldActive(), self.proxy.isShieldComposed(), self.proxy.getRedstoneMode()
        if type(active) ~= "boolean" or type(composed) ~= "boolean" or not modes[mode] then return nil, "INVALID_SHIELD_STATUS" end
        return {active = active, composed = composed, redstoneMode = mode, health = nil}
      end
      function self:setRedstoneMode(mode)
        assert(modes[mode], "invalid RFTools redstone mode")
        self.proxy.setRedstoneMode(mode)
        return true
      end
      local function setPower(value)
        if not self.settings then return nil, "ENOTSUP" end
        self.proxy.setRedstoneMode(self.settings.activationMode)
        return context.registry:call(self.settings.controlAddress, "setOutput", self.settings.side, value)
      end
      function self:turn_on()
        local status, err = self:getStatus()
        if not status then return nil, err end
        if status.active then return true end
        if not status.composed then return nil, "SHIELD_NOT_COMPOSED" end
        return setPower(self.settings and self.settings.onValue)
      end
      function self:turn_off()
        local status, err = self:getStatus()
        if not status then return nil, err end
        if not status.active then return true end
        return setPower(self.settings and self.settings.offValue)
      end
      function self:compose(disconnected)
        local status, err = self:getStatus()
        if not status then return nil, err end
        if status.composed then return true end
        local result
        if disconnected then
          if type(self.proxy.composeShieldDsc) ~= "function" then return nil, "ENOTSUP" end
          result = self.proxy.composeShieldDsc()
        else result = self.proxy.composeShield() end
        if result == false then return nil, "SHIELD_COMPOSE_REJECTED" end
        return true
      end
      function self:decompose()
        local status, err = self:getStatus()
        if not status then return nil, err end
        if not status.composed then return true end
        local result = self.proxy.decomposeShield()
        if result == false then return nil, "SHIELD_DECOMPOSE_REJECTED" end
        return true
      end
      return self
    end}
end

return M
