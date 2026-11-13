-- Minecraft redstone actuator. Every physical operation goes through HAL.
local M = {}
function M.new(deps, channels)
  assert(type(channels) == "table" and #channels > 0, "destruction channels required")
  local self = {completed = {}, fired = false}
  function self:fire(reason)
    local failed = {}
    for index, channel in ipairs(channels) do
      if not self.completed[index] then
        local ok, err = deps.hal:call(channel.address, "setOutput", channel.side, channel.value or 15)
        if ok then self.completed[index] = true
        else failed[#failed + 1] = {address = channel.address, error = err} end
      end
    end
    self.fired = #failed == 0
    if deps.log then deps.log("critical", self.fired and "DESTRUCTION_FIRED" or "DESTRUCTION_PARTIAL",
      {reason = reason, failures = failed}) end
    return self.fired, failed
  end
  return self
end
return M
