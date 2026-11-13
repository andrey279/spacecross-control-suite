local M = {}
function M.new(proxy, port, settings)
  settings = type(settings) == "table" and settings or {}
  for _, method in ipairs({"maxPacketSize", "isOpen", "open", "close", "broadcast"}) do
    assert(type(proxy[method]) == "function", "modem API missing " .. method)
  end
  local self = {}
  function self.open()
    if not proxy.isOpen(port) then
      self.owned = proxy.open(port) == true
      assert(proxy.isOpen(port), "MODEM_PORT_NOT_OPEN")
    end
    if settings.strength ~= nil then
      assert(type(proxy.setStrength) == "function" and type(proxy.getStrength) == "function", "wireless strength API unavailable")
      self.oldStrength = proxy.getStrength()
      proxy.setStrength(settings.strength)
      self.appliedStrength = proxy.getStrength()
    end
    return true
  end
  function self.close()
    if self.owned then proxy.close(port); self.owned = nil end
    if self.oldStrength and proxy.getStrength() == self.appliedStrength then proxy.setStrength(self.oldStrength) end
    self.oldStrength = nil
  end
  function self.maximum() return proxy.maxPacketSize() end
  function self.accepts(rawPort) return rawPort == port end
  function self.transmit(data) return proxy.broadcast(port, data) end
  return self
end
return M
