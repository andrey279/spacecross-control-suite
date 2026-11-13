local P = require("tests.stubs.platform")
local M = {}
function M.new()
  local self = {hosts = {}, cards = {}, sent = {}, held = {}, paused = false, session = 0}
  function self:host(name)
    local p = P.new(); p.nodeId = name
    p.randomId = function() self.session = self.session + 1; return name .. "-session-" .. self.session end
    self.hosts[#self.hosts + 1] = p
    return p
  end
  function self:deliver(packet)
    for address, card in pairs(self.cards) do
      if address ~= packet.source and card.proxy.type == packet.kind and card.segment == packet.segment
          and (packet.kind == "tunnel" or card.open[packet.port]) then
        card.host.event.push("modem_message", address, packet.source, packet.port, 0, packet.wire)
      end
    end
  end
  function self:card(p, address, kind, segment, maximum)
    local record = {host = p, segment = segment or "lan", open = {}, maximum = maximum or 8192}
    local proxy = {type = kind, address = address, strength = 0, closeCalls = 0}
    record.proxy = proxy; self.cards[address] = record; p.components[address] = proxy
    function proxy.maxPacketSize() return record.maximum end
    local function transmit(port, wire)
      if proxy.broken then error("card unreachable") end
      assert(type(wire) == "string" and #wire + 2 <= record.maximum, "packet exceeds OC limit")
      local packet = {source = address, port = port, wire = wire, kind = kind, segment = record.segment}
      self.sent[#self.sent + 1] = packet
      if self.paused then self.held[#self.held + 1] = packet else self:deliver(packet) end
      return true
    end
    if kind == "modem" then
      function proxy.isOpen(port) return record.open[port] == true end
      function proxy.open(port)
        local already = record.open[port]; record.open[port] = true; return not already
      end
      function proxy.close(port) record.open[port] = nil; proxy.closeCalls = proxy.closeCalls + 1; return true end
      proxy.broadcast = transmit
      function proxy.getStrength() return proxy.strength end
      function proxy.setStrength(value) proxy.strength = value; return value end
    else function proxy.send(wire) return transmit(0, wire) end end
    return proxy
  end
  function self:flush(reverse)
    local held = self.held; self.held = {}; self.paused = false
    if reverse then for index = #held, 1, -1 do self:deliver(held[index]) end
    else for _, packet in ipairs(held) do self:deliver(packet) end end
    return held
  end
  function self:drain()
    for _ = 1, 100 do
      local pending = false
      for _, p in ipairs(self.hosts) do if #p.queue > 0 then pending = true; p:pump() end end
      if not pending then return end
    end
    error("fabric message loop")
  end
  function self:advance(seconds)
    for _, p in ipairs(self.hosts) do p:advance(seconds) end
    self:drain()
  end
  return self
end
return M
