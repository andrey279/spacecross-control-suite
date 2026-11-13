-- Explicit, version-gated component adapter for satellite hardware.
-- Method names and argument shapes are configuration, because legacy mod APIs
-- differ between 1.7.10 packs. No method is guessed.
local M = {}

local function name(value, required)
  if value == nil and not required then return nil end
  assert(type(value) == "string" and value:match("^[%a_][%w_]*$"), "invalid satellite method")
  return value
end
local function address(value) assert(type(value) == "string" and value:match("^[%w%-]+$"), "invalid satellite address"); return value end

function M.new(deps, config)
  config = config or {}; local component = assert(deps.component)
  local radar = config.radar and {address = address(config.radar.address), scan = name(config.radar.scan, true)}
  local ship = config.ship and {address = address(config.ship.address), jump = name(config.ship.jump, true), position = name(config.ship.position, false)}
  local charges = config.charges and {
    auxiliary = {address = address(config.charges.auxiliary.address), method = name(config.charges.auxiliary.method, true)},
    central = {address = address(config.charges.central.address), method = name(config.charges.central.method, true)},
  }
  local function proxy(binding, method)
    local ok, value = pcall(component.proxy, binding.address)
    if not ok or not value then return nil, "COMPONENT_UNAVAILABLE" end
    if type(value[method]) ~= "function" then return nil, "METHOD_UNAVAILABLE" end
    return value
  end
  local function call(binding, method, ...)
    local device, err = proxy(binding, method); if not device then return nil, err end
    local ok, result, detail = pcall(device[method], ...)
    if not ok then return nil, tostring(result) end
    if result == false or (result == nil and detail ~= nil) then return nil, detail or "HARDWARE_REJECTED" end
    if result == nil then return true end -- void-returning OC methods are successful unless they return an error.
    return result, detail
  end
  local self = {}
  function self:scan(range)
    if not radar then return nil, "RADAR_UNAVAILABLE" end
    local result, err = call(radar, radar.scan, range)
    if type(result) ~= "table" then return nil, err or "INVALID_SCAN_RESPONSE" end
    return result
  end
  function self:position()
    if not ship or not ship.position then return nil, "POSITION_UNAVAILABLE" end
    return call(ship, ship.position)
  end
  function self:jump(target)
    if not ship then return nil, "SHIP_UNAVAILABLE" end
    return call(ship, ship.jump, target)
  end
  function self:auxiliary(target, vector, count)
    if not charges then return nil, "CHARGES_UNAVAILABLE" end
    return call(charges.auxiliary, charges.auxiliary.method, target, vector, count)
  end
  function self:central(target)
    if not charges then return nil, "CHARGES_UNAVAILABLE" end
    return call(charges.central, charges.central.method, target)
  end
  return self
end
return M
