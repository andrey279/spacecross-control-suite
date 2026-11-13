local codec = require("spacecross.core.codec")
local Bus = require("spacecross.bus.local_bus")
local Policy = require("spacecross.bus.policy")
local M = {}
function M.new(deps, config)
  config = config or {}
  local policy = Policy.new(config)
  local self = {running = false, seen = {}, stats = {sent = 0, received = 0, dropped = 0}}
  local function outbound(message)
    -- Remote publications cannot be reflected back to the wire.
    if message.src_addr ~= nil then return end
    local cards = {}
    for _, card in ipairs(deps.network:listCards()) do
      if policy:allows("outbound", card.address, message, message.dst_addr or "*") then cards[#cards + 1] = card.address end
    end
    if #cards == 0 then return end
    local data = {proto_version = 1, msg_type = message.msg_type, dst_addr = message.dst_addr or "*", port = message.port, payload = message.payload}
    local report, err = deps.network:send(data.dst_addr, data.port, codec.encode(data), cards, "bus")
    if report then self.stats.sent = self.stats.sent + 1
    else
      self.stats.dropped = self.stats.dropped + 1
      if deps.log then pcall(deps.log, "error", "ERR_BUS_NETWORK_SEND", {error = tostring(err), port = data.port}) end
    end
  end
  local function inbound(_, receiver, source, destination, port, service, payload, id)
    if service ~= "bus" then return end
    if type(id) ~= "string" or #id > 128 or not deps.network.cards[receiver] then self.stats.dropped = self.stats.dropped + 1; return end
    local message = codec.decode(payload, 131072)
    if not Bus.validate(message) or message.src_addr ~= nil or message.dst_addr ~= destination or message.port ~= port
        or not policy:allows("inbound", receiver, message, source) then
      self.stats.dropped = self.stats.dropped + 1; return
    end
    -- Deduplicate only after each receiving interface's policy has accepted it.
    local now, count, oldest, oldestTime = deps.clock(), 0
    for key, expires in pairs(self.seen) do
      if now >= expires then self.seen[key] = nil
      else
        count = count + 1
        if not oldestTime or expires < oldestTime then oldest, oldestTime = key, expires end
      end
    end
    if self.seen[id] then return end
    if count >= (config.maxSeen or 512) then self.seen[oldest] = nil end
    self.seen[id] = now + (config.seenTTL or 30)
    message.src_addr = source
    local ok = deps.bus:publish(message)
    if ok then self.stats.received = self.stats.received + 1 else self.stats.dropped = self.stats.dropped + 1 end
  end
  function self:start()
    if self.running then return false end
    self.subscription = deps.bus:subscribe(nil, outbound)
    deps.event.listen("spacecross_network_message", inbound)
    self.running = true
    return true
  end
  function self:stop()
    if self.subscription then deps.bus:unsubscribe(self.subscription); self.subscription = nil end
    deps.event.ignore("spacecross_network_message", inbound)
    self.seen, self.running = {}, false
  end
  return self
end
return M
