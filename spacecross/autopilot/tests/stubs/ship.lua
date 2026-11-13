-- Real proxy signature, simulated Minecraft movement/cooldown.
return function(p, address, options)
  options = options or {}
  local self = {type = "warpdriveShipController", mode = "IDLE", enabled = false,
    x = options.x or 0, y = options.y or 64, z = options.z or 0, ox = options.ox or 1, oz = options.oz or 0,
    energyStored = options.energy or 10000, calls = {}, jumps = 0}
  local front, up, right = 0, 0, 0
  local function record(name, value) self.calls[#self.calls + 1] = {name, value} end
  function self.command(mode)
    if mode then self.mode = mode; record("command", mode) end
    return self.mode
  end
  function self.enable(enabled)
    if enabled ~= nil then
      self.enabled = enabled; record("enable", enabled)
      if enabled then
        self.jumps = self.jumps + 1
        if not options.stall then
          p.event.timer(options.cooldown or 2, function()
            self.x, self.y, self.z = self.x + self.ox * front - self.oz * right,
              self.y + up, self.z + self.oz * front + self.ox * right
            self.mode, self.enabled = "IDLE", false
            p.event.push("shipCoreCooldownDone", address)
          end)
        end
      end
    end
    return self.enabled
  end
  function self.position() return self.x, self.y, self.z end
  function self.getOrientation() return self.ox, 0, self.oz end
  function self.movement(f, u, r)
    if f then front, up, right = f, u, r end
    return front, up, right
  end
  function self.rotationSteps(steps) return steps or 0 end
  function self.getMaxJumpDistance() return true, options.maximum or 10 end
  function self.getEnergyRequired() return true, 100 end
  function self.energy() return self.energyStored, 10000 end
  function self.isAssemblyValid() return not options.invalid, "invalid assembly" end
  return self
end
