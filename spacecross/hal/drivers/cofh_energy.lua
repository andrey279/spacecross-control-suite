-- Shared RF telemetry contracts exposed by the official OC CoFH integration.
local M = {}
local function valid(stored, capacity)
  return type(stored) == "number" and type(capacity) == "number" and stored == stored and capacity == capacity
    and capacity > 0 and capacity < math.huge and stored >= 0 and stored <= capacity
end
local readers = {
  energy_handler = function(proxy, side) return proxy.getEnergyStored(side or 6), proxy.getMaxEnergyStored(side or 6) end,
  energy_info = function(proxy) return proxy.getEnergy(), proxy.getMaxEnergy() end,
}
function M.read(proxy, side)
  local read = readers[proxy.type]
  if not read then return nil, "UNSUPPORTED_RF_COMPONENT" end
  local stored, capacity = read(proxy, side)
  if not valid(stored, capacity) then return nil, "INVALID_ENERGY" end
  return {stored = stored, capacity = capacity}
end
return M
