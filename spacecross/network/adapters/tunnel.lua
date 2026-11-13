local M = {}
function M.new(proxy)
  assert(type(proxy.send) == "function" and type(proxy.maxPacketSize) == "function", "tunnel API unavailable")
  return {open = function() return true end, close = function() end,
    maximum = function() return proxy.maxPacketSize() end,
    accepts = function(rawPort) return rawPort == 0 end,
    transmit = function(data) return proxy.send(data) end}
end
return M
