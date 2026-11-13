-- Outgoing, nonblocking Internet Card TCP route for the existing RPC protocol.
local codec = require("spacecross.core.codec")
local Net = require("spacecross.network.protocol")
local M = {}
local function prefix(n) return string.char(math.floor(n / 16777216), math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
local function length(s) local a,b,c,d = s:byte(1,4); return ((a * 256 + b) * 256 + c) * 256 + d end
function M.new(deps, config)
  assert(Net.address(config.address) and Net.address(config.peer) and config.address ~= config.peer)
  assert(Net.port(config.serverPort or 27016) and Net.port(config.rpcPort or 27016))
  assert(type(config.peerCertificate) == "string" and type(config.host) == "string")
  local lan, maximum = deps.network, config.maxFrame or 98304
  local self = {running = false, connected = false, generation = 0, cards = {}, lastError = nil}
  setmetatable(self.cards, {__index = function(_, address) return lan and lan.cards[address] end})
  local socket, incoming, outgoing, retryAt, backoff, openedAt = nil, "", "", 0, 1, 0
  local timer, busy
  local lastReported
  local function disconnect(err)
    if socket then pcall(socket.close) end
    socket, self.connected, incoming, outgoing = nil, false, "", ""
    self.cards[config.address] = nil
    self.lastError, retryAt = tostring(err):sub(1, 256), deps.clock() + backoff
    self.trusted = false
    if self.running and self.lastError ~= lastReported then
      lastReported = self.lastError
      if deps.log then pcall(deps.log, "warning", "CNC_DISCONNECTED", {error = self.lastError}) end
    end
    backoff = math.min(config.maxBackoff or 30, backoff * 2)
  end
  function self:listCards()
    local result = lan and lan:listCards() or {}
    if self.connected then table.insert(result, 1, {address = config.address, type = "internet"}) end
    return result
  end
  function self:send(destination, port, body, source, service)
    if destination ~= config.peer then
      if source == config.address or not lan then return nil, "NO_ROUTE" end
      return lan:send(destination, port, body, source, service)
    end
    if not self.running or not self.connected then return nil, "CNC_DISCONNECTED" end
    if source ~= config.address or port ~= (config.rpcPort or 27016) or service ~= "rpc" then return nil, "INVALID_CNC_ROUTE" end
    if type(body) ~= "string" or #body < 1 or #body > maximum then return nil, "CNC_FRAME_LIMIT" end
    if #outgoing + #body + 4 > (config.maxQueued or 262144) then return nil, "CNC_QUEUE_FULL" end
    outgoing = outgoing .. prefix(#body) .. body
    return {sent = {config.address}, failed = {}}
  end
  local function tick()
    if not socket then
      if deps.clock() < retryAt then return end
      local card = deps.component.proxy(config.address)
      assert(card and card.type == "internet", "Internet Card unavailable")
      socket = assert(card.connect(config.host, config.serverPort or 27016))
      if not self.running then pcall(socket.close); socket = nil; return end
      openedAt = deps.clock()
    end
    if not self.connected then
      local ready, err = socket.finishConnect()
      assert(ready ~= nil, err or "TCP connect failed")
      if not ready then assert(deps.clock() - openedAt < (config.connectTimeout or 10), "TCP connect timeout"); return end
      self.connected, self.generation = true, self.generation + 1
      self.cards[config.address] = {address = config.address, type = "internet"}
      self.lastError = nil
    end
    if #outgoing > 0 then
      local sent = assert(socket.write(outgoing:sub(1, 8192)))
      assert(type(sent) == "number" and sent % 1 == 0 and sent >= 0 and sent <= math.min(#outgoing, 8192), "invalid TCP write")
      outgoing = outgoing:sub(sent + 1)
    end
    -- Bounded work per tick, including peers flooding complete small frames.
    local data = socket.read(8192)
    if not self.running then return end
    assert(data ~= nil, "TCP closed")
    assert(type(data) == "string" and #data <= 8192, "invalid TCP read")
    incoming = incoming .. data
    assert(#incoming <= maximum + 8196, "CNC receive limit")
    local delivered = 0
    while #incoming >= 4 and delivered < 16 do
      local size = length(incoming)
      assert(size > 0 and size <= maximum, "CNC frame length")
      if #incoming < size + 4 then break end
      local wire = incoming:sub(5, size + 4); incoming = incoming:sub(size + 5)
      local outer = codec.decode(wire, maximum)
      assert(type(outer) == "table" and outer.certificate == config.peerCertificate, "CNC certificate pin mismatch")
      deps.event.push("spacecross_network_message", config.address, config.peer, config.address,
        config.rpcPort or 27016, "rpc", wire)
      delivered = delivered + 1
    end
  end
  function self:tick()
    if not self.running or busy then return end
    busy = true
    local ok, err = pcall(tick)
    busy = false
    if not ok then disconnect(err) end
  end
  function self:authenticated()
    backoff, lastReported = 1, nil
    if not self.trusted and deps.log then pcall(deps.log, "info", "CNC_AUTHENTICATED", {peer = config.peer}) end
    self.trusted = true
  end
  function self:start()
    if self.running then return false end
    self.running, retryAt = true, 0
    timer = deps.event.timer(config.interval or 0.1, function() self:tick() end, math.huge)
    return true
  end
  function self:stop()
    self.running = false
    if timer then deps.event.cancel(timer); timer = nil end
    disconnect("ESHUTDOWN")
  end
  return self
end
return M
