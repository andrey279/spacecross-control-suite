-- WarpDrive MC1.7, commit 8c00788a1cd8005afd73128dbaba8a893d500471.
local function integer(value) return type(value) == "number" and value == value and math.abs(value) < math.huge and value % 1 == 0 end
return {id = "warpdrive_ship", types = {"warpdriveShipController"}, kind = "navigation", new = function()
  local self = {}
  function self:init(proxy)
    for _, name in ipairs({"enable", "command", "movement", "rotationSteps", "position", "getOrientation",
        "getMaxJumpDistance", "getEnergyRequired", "energy", "isAssemblyValid"}) do
      assert(type(proxy[name]) == "function", "ship API missing " .. name)
    end
    self.proxy = proxy; return true
  end
  function self:isOperational() return self.proxy.isAssemblyValid() end
  function self:getEnergyLevel()
    local stored, capacity = self.proxy.energy()
    if type(stored) ~= "number" or type(capacity) ~= "number" then return nil, "INVALID_ENERGY" end
    return {stored = stored, capacity = capacity}
  end
  function self:getPosition()
    local x, y, z = self.proxy.position()
    if not integer(x) or not integer(y) or not integer(z) then return nil, "POSITION_UNAVAILABLE" end
    return {x = x, y = y, z = z}
  end
  function self:turn_off()
    if self.proxy.enable(false) ~= false then return nil, "DISABLE_REJECTED" end
    if self.proxy.command("OFFLINE") ~= "OFFLINE" then return nil, "OFFLINE_REJECTED" end
    return true
  end
  function self:prepare()
    local valid, err = self.proxy.isAssemblyValid()
    if not valid then return nil, err end
    if self.proxy.enable(false) ~= false then return nil, "DISABLE_REJECTED" end
    if self.proxy.command("MANUAL") ~= "MANUAL" then return nil, "COMMAND_REJECTED" end
    return true
  end
  local function setMovement(vector)
    for _, axis in ipairs({"x", "y", "z"}) do assert(integer(vector[axis]), "integer jump vector required") end
    local ox, oy, oz = self.proxy.getOrientation()
    if not integer(ox) or not integer(oz) or oy ~= 0 or math.abs(ox) + math.abs(oz) ~= 1 then return nil, "INVALID_ORIENTATION" end
    local front, up, right = vector.x * ox + vector.z * oz, vector.y, -vector.x * oz + vector.z * ox
    local f, u, r = self.proxy.movement(front, up, right)
    if f ~= front or u ~= up or r ~= right then return nil, "MOVEMENT_REJECTED" end
    return true
  end
  function self:getMaxDistance(vector)
    if vector then
      local moved, err = setMovement(vector)
      if not moved then return nil, err end
    end
    local ok, distance = self.proxy.getMaxJumpDistance()
    if ok ~= true then return nil, distance or "DISTANCE_UNAVAILABLE" end
    if not integer(distance) or distance < 1 then return nil, "INVALID_DISTANCE" end
    return distance
  end
  function self:jump(vector)
    if self.proxy.command("MANUAL") ~= "MANUAL" then return nil, "COMMAND_REJECTED" end
    local moved, moveErr = setMovement(vector)
    if not moved then return nil, moveErr end
    if self.proxy.rotationSteps(0) ~= 0 then return nil, "MOVEMENT_REJECTED" end
    local ok, required = self.proxy.getEnergyRequired()
    if ok ~= true then return nil, required or "ENERGY_UNAVAILABLE" end
    local level, err = self:getEnergyLevel()
    if not level then return nil, err end
    if level.stored < required then return nil, "INSUFFICIENT_ENERGY" end
    if self.proxy.enable(true) ~= true then return nil, "ENABLE_REJECTED" end
    return true
  end
  return self
end}
