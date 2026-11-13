local protocol = require("spacecross.network.protocol")
local util = require("spacecross.core.util")
local M = {}
local adapters = {modem = require("spacecross.network.adapters.modem"), tunnel = require("spacecross.network.adapters.tunnel")}
local function positive(value) return type(value) == "number" and value > 0 and value < math.huge end
function M.new(deps, config)
  config = config or {}
  local wirePort = config.port or 27015
  local maximumMessage, maxFragments = config.maxMessage or 131072, config.maxFragments or 256
  local maxPending, maxPeerPending = config.maxPending or 16, config.maxPeerPending or 4
  local maxBuffered, maxSeen = config.maxBuffered or 524288, config.maxSeen or 512
  local fragmentTTL, seenTTL = config.fragmentTTL or 5, config.seenTTL or 30
  assert(protocol.port(wirePort) and positive(maximumMessage) and positive(maxFragments) and maxFragments % 1 == 0)
  assert(positive(maxPending) and positive(maxPeerPending) and positive(maxBuffered) and positive(maxSeen))
  assert(positive(fragmentTTL) and positive(seenTTL))
  local session = assert(config.sessionId or deps.randomId(), "network session ID required")
  assert(type(session) == "string" and #session <= 96 and session:match("^[%w:._%-]+$"), "invalid network session ID")
  local self = {cards = {}, pending = {}, seen = {}, buffered = 0, sequence = 0, running = false,
    stats = {received = 0, delivered = 0, dropped = 0, duplicates = 0, expired = 0, hardwareErrors = 0}}
  local function log(address, err)
    self.stats.hardwareErrors = self.stats.hardwareErrors + 1
    if deps.log then pcall(deps.log, "error", "ERR_NETWORK_CARD", {address = address, error = tostring(err)}) end
  end
  local function discard(key)
    local item = self.pending[key]
    if item then self.buffered = self.buffered - item.bytes; self.pending[key] = nil end
  end
  function self:cleanup()
    local now = deps.clock()
    for key, item in pairs(self.pending) do
      if now >= item.expires then discard(key); self.stats.expired = self.stats.expired + 1 end
    end
    for id, expires in pairs(self.seen) do if now >= expires then self.seen[id] = nil end end
  end
  local function remember(receiver, id)
    local count, oldestId, oldestTime = 0
    for key, expires in pairs(self.seen) do
      count = count + 1
      if not oldestTime or expires < oldestTime then oldestId, oldestTime = key, expires end
    end
    if count >= maxSeen then self.seen[oldestId] = nil end
    self.seen[receiver .. "/" .. id] = deps.clock() + seenTTL
    -- Copies sent through another local interface may have unfinished assemblies.
    for key, item in pairs(self.pending) do if item.id == id and item.receiver == receiver then discard(key) end end
  end
  function self:listCards()
    local out = {}
    for _, address in ipairs(util.sortedKeys(self.cards)) do out[#out + 1] = {address = address, type = self.cards[address].type} end
    return out
  end
  function self:remove(address)
    local card = self.cards[address]
    self.cards[address] = nil
    if card then
      local ok, err = pcall(card.adapter.close)
      if not ok then log(address, err) end
      for key, item in pairs(self.pending) do if item.receiver == address then discard(key) end end
      deps.event.push("spacecross_network_card_removed", address)
    end
  end
  function self:add(address, kind)
    if self.cards[address] or not adapters[kind] or (config.cards and config.cards[address] == nil) or config.cards and config.cards[address] == false then return false end
    local adapter
    local ok, err = pcall(function()
      adapter = adapters[kind].new(assert(deps.component.proxy(address)), wirePort, config.cards and config.cards[address])
      assert(adapter.open())
      local maximum = adapter.maximum()
      assert(positive(maximum) and maximum > 2, "NETWORK_PACKET_LIMIT_TOO_SMALL")
      self.cards[address] = {adapter = adapter, type = kind, maximum = maximum}
    end)
    if not ok then
      if adapter then pcall(adapter.close) end
      log(address, err); return nil, tostring(err)
    end
    deps.event.push("spacecross_network_card_added", address)
    return true
  end
  local function receive(_, receiver, source, rawPort, _, wire, ...)
    self.stats.received = self.stats.received + 1
    local card = self.cards[receiver]
    if not card or not card.adapter.accepts(rawPort) or select("#", ...) ~= 0 then self.stats.dropped = self.stats.dropped + 1; return end
    local packet = protocol.decode(wire, card.maximum, maxFragments)
    if not packet or packet.src ~= source or self.cards[source] or packet.dst ~= "*" and packet.dst ~= receiver then
      self.stats.dropped = self.stats.dropped + 1; return
    end
    self:cleanup()
    if self.seen[receiver .. "/" .. packet.id] then self.stats.duplicates = self.stats.duplicates + 1; return end
    local key = receiver .. "/" .. source .. "/" .. packet.id
    local item = self.pending[key]
    if not item then
      local count, peerCount = 0, 0
      for _, old in pairs(self.pending) do count = count + 1; if old.source == source then peerCount = peerCount + 1 end end
      if count >= maxPending or peerCount >= maxPeerPending then self.stats.dropped = self.stats.dropped + 1; return end
      item = {id = packet.id, source = source, receiver = receiver, destination = packet.dst, port = packet.port,
        service = packet.service, total = packet.total, parts = {}, received = 0, bytes = 0, expires = deps.clock() + fragmentTTL}
      self.pending[key] = item
    end
    if item.total ~= packet.total or item.port ~= packet.port or item.destination ~= packet.dst or item.service ~= packet.service then
      discard(key); self.stats.dropped = self.stats.dropped + 1; return
    end
    if item.parts[packet.part] then
      if item.parts[packet.part] ~= packet.body then discard(key); self.stats.dropped = self.stats.dropped + 1
      else self.stats.duplicates = self.stats.duplicates + 1 end
      return
    end
    if item.bytes + #packet.body > maximumMessage or self.buffered + #packet.body > maxBuffered then
      discard(key); self.stats.dropped = self.stats.dropped + 1; return
    end
    item.parts[packet.part], item.received = packet.body, item.received + 1
    item.bytes, self.buffered = item.bytes + #packet.body, self.buffered + #packet.body
    if item.received == item.total then
      local payload = table.concat(item.parts)
      remember(receiver, packet.id)
      self.stats.delivered = self.stats.delivered + 1
      deps.event.push("spacecross_network_message", receiver, source, packet.dst, packet.port, packet.service, payload, packet.id)
    end
  end
  function self:send(destination, port, payload, selector, service)
    if not self.running then return nil, "ENOTRUNNING" end
    service = service or "data"
    if destination ~= "*" and not protocol.address(destination) or not protocol.port(port)
        or not protocol.service(service) or type(payload) ~= "string" or #payload > maximumMessage then return nil, "EINVAL_NETWORK_MESSAGE" end
    self.sequence = self.sequence + 1
    local id = session .. ":" .. self.sequence
    local selected = {}
    if type(selector) == "string" then selected[selector] = true
    elseif type(selector) == "table" then for _, address in ipairs(selector) do selected[address] = true end
    elseif selector == nil then for address in pairs(self.cards) do selected[address] = true end
    else return nil, "EINVAL_CARD_SELECTOR" end
    local report = {id = id, cards = {}, sent = 0}
    for _, address in ipairs(util.sortedKeys(selected)) do
      local card = self.cards[address]
      local ok, result = pcall(function()
        assert(card, "UNKNOWN_NETWORK_CARD")
        local template = {v = 1, id = id, src = address, dst = destination, port = port, service = service,
          part = maxFragments, total = maxFragments, body = ""}
        local size = card.maximum - 2 - #protocol.encode(template) - 32
        assert(size >= 1, "NETWORK_HEADER_TOO_LARGE")
        local total = math.max(1, math.ceil(#payload / size))
        assert(total <= maxFragments, "TOO_MANY_FRAGMENTS")
        for index = 1, total do
          template.part, template.total = index, total
          template.body = payload:sub((index - 1) * size + 1, index * size)
          local data = protocol.encode(template)
          assert(#data + 2 <= card.maximum, "NETWORK_PACKET_TOO_LARGE")
          local sent, err = card.adapter.transmit(data)
          assert(sent == true, err or "SEND_REJECTED")
        end
        return total
      end)
      report.cards[address] = {ok = ok, fragments = ok and result or nil, error = not ok and tostring(result) or nil}
      if ok then report.sent = report.sent + 1 else log(address, result) end
    end
    if report.sent == 0 then return nil, "ENETUNREACH", report end
    return report
  end
  function self:broadcast(port, payload, selector, service) return self:send("*", port, payload, selector, service) end
  local function added(_, address, kind) self:add(address, kind) end
  local function removed(_, address) self:remove(address) end
  function self:start()
    if self.running then return false end
    self.running = true
    deps.event.listen("modem_message", receive)
    deps.event.listen("component_added", added)
    deps.event.listen("component_removed", removed)
    self.timer = deps.event.timer(math.min(fragmentTTL, seenTTL), function() self:cleanup() end, math.huge)
    for address, kind in deps.component.list() do self:add(address, kind) end
    return true
  end
  function self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    deps.event.ignore("modem_message", receive)
    deps.event.ignore("component_added", added)
    deps.event.ignore("component_removed", removed)
    for _, card in ipairs(self:listCards()) do self:remove(card.address) end
    self.pending, self.seen, self.buffered, self.running = {}, {}, 0, false
  end
  return self
end
return M
