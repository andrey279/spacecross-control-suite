local codec = require("spacecross.core.codec")
local util = require("spacecross.core.util")
local Certificates = require("spacecross.security.certificates")
local Protocol = require("spacecross.rpc.protocol")
local Net = require("spacecross.network.protocol")
local M = {}
function M.new(deps, config)
  config = config or {}
  local port = config.port or 27016
  local timeout, challengeTTL, cacheTTL, retry = config.timeout or 8, config.challengeTTL or 10, config.cacheTTL or 30, config.retryInterval or 1
  local maxSessions, maxPeer, maxBytes, maxFrame = config.maxSessions or 32, config.maxPeer or 4, config.maxBytes or 524288, config.maxFrame or 98304
  assert(Net.port(port) and timeout > 0 and challengeTTL > 0 and cacheTTL > 0 and retry > 0)
  assert(maxSessions >= 1 and maxPeer >= 1 and maxBytes > 0 and maxFrame > 0)
  local crypto, trust = assert(deps.crypto), assert(deps.trust)
  local certificateWire = assert(config.certificate)
  local own = assert(trust:verify(certificateWire))
  local self = {running = false, clients = {}, inbound = {}, identities = {}, peers = {}, stats = {accepted = 0, denied = 0, executed = 0, timeouts = 0, faults = 0}}
  local reportedDenied, reportedFaults = 0, 0
  function self:peer(host)
    local wire = self.peers[host]
    if not wire then return nil end
    return trust:verify(wire, "server", host)
  end
  local function nonce(provider)
    local value = provider.random(32)
    assert(type(value) == "string" and #value == 32, "INVALID_SECURE_RANDOM")
    return Protocol.hex(value)
  end
  -- Verify the configured private key against its certificate without exposing it.
  local probe = "SpaceCross key proof\0" .. crypto.random(32)
  assert(crypto.verify(own.public_key, probe, crypto.sign(probe)), "RPC_PRIVATE_KEY_MISMATCH")
  function self:addIdentity(wire, provider)
    local cert, err = trust:verify(wire, "client")
    if not cert then return nil, err end
    local proof = "SpaceCross identity proof\0" .. provider.random(32)
    if not crypto.verify(cert.public_key, proof, provider.sign(proof)) then return nil, "RPC_PRIVATE_KEY_MISMATCH" end
    self.identities[cert.subject:lower()] = {wire = wire, crypto = provider, certificate = cert}
    return true
  end
  if trust:verify(certificateWire, "client") then assert(self:addIdentity(certificateWire, crypto)) end
  local function frame(provider, cert, kind, id, src, dst, clientNonce, extra)
    local body = {v = 1, kind = kind, id = id, src = src, dst = dst, port = port, client_nonce = clientNonce}
    for key, value in pairs(extra or {}) do body[key] = value end
    local wire = Protocol.sign(provider, cert, body)
    assert(#wire <= maxFrame, "RPC_FRAME_TOO_LARGE")
    return wire
  end
  local function send(wire, source, destination)
    if not self.running then return nil, "ESHUTDOWN" end
    return deps.network:send(destination, port, wire, source, "rpc")
  end
  local function usageCount(entries, peer)
    local count, peers, bytes = 0, 0, 0
    for _, entry in pairs(entries) do
      count, bytes = count + 1, bytes + (entry.bytes or 0)
      if entry.peer == peer and entry.state ~= "done" then peers = peers + 1 end
    end
    return count, peers, bytes
  end
  local function makeRoom(required, reserveSlot)
    while true do
      local count, _, used = usageCount(self.inbound)
      if (not reserveSlot or count < maxSessions) and used + required <= maxBytes then return true end
      local oldest, expiry
      for key, entry in pairs(self.inbound) do
        if entry.state == "done" and (not expiry or entry.expires < expiry) then oldest, expiry = key, entry.expires end
      end
      if not oldest then return false end
      -- Eviction removes only cached results, never an executing/unused challenge.
      -- A replayed hello then receives a new challenge; its old invoke cannot run.
      self.inbound[oldest] = nil
    end
  end
  local function completeClient(call, value, err)
    local size = 0
    if value ~= nil then
      local ok, encoded = pcall(codec.encode, value)
      local _, _, used = usageCount(self.clients)
      if not ok or used - (call.bytes or 0) + #encoded > maxBytes then value, err = nil, "RPC_RESPONSE_LIMIT"
      else size = #encoded end
    end
    call.bytes, call.wire, call.identity = size, nil, nil
    call.done, call.value, call.error, call.expires = true, util.copy(value), err, deps.clock() + cacheTTL
  end
  function self:begin(host, model, action, player, args, card)
    if not self.running then return nil, "ENOTRUNNING" end
    local identity = type(player) == "string" and self.identities[player:lower()]
    if not identity then return nil, "NO_CLIENT_IDENTITY" end
    local cert, certErr = trust:verify(identity.wire, "client")
    if not cert then return nil, certErr end
    if not Certificates.granted(cert, model, action) then return nil, "CERTIFICATE_DENIED" end
    if not Net.address(host) then return nil, "INVALID_RPC_HOST" end
    if type(model) ~= "string" or type(action) ~= "string" then return nil, "INVALID_RPC_METHOD" end
    if not card then
      for _, candidate in ipairs(deps.network:listCards()) do if Certificates.bound(cert, candidate.address) then card = candidate.address; break end end
    end
    if not deps.network.cards[card] or not Certificates.bound(cert, card) then return nil, "NO_CERTIFIED_INTERFACE" end
    local count, _, used = usageCount(self.clients)
    if count >= maxSessions then return nil, "EBUSY" end
    local ok, call = pcall(function()
      local id, clientNonce = nonce(identity.crypto), nonce(identity.crypto)
      assert(not self.clients[id], "RPC_NONCE_COLLISION")
      local request = codec.encode({model = model, action = action, args = util.copy(args or {})})
      local hello = frame(identity.crypto, identity.wire, "hello", id, card, host, clientNonce, {request = request})
      assert(used + #hello <= maxBytes, "RPC_CLIENT_LIMIT")
      local outer = assert(codec.decode(hello, maxFrame))
      return {id = id, clientNonce = clientNonce, source = card, peer = host, identity = identity,
        phase = "hello", wire = hello, bytes = #hello, helloDigest = crypto.sha256(outer.body), deadline = deps.clock() + timeout, lastSent = deps.clock()}
    end)
    if not ok then return nil, tostring(call) end
    if not self.running then return nil, "ESHUTDOWN" end
    count, _, used = usageCount(self.clients)
    if count >= maxSessions or used + call.bytes > maxBytes then return nil, "EBUSY" end
    if self.clients[call.id] then return nil, "RPC_NONCE_COLLISION" end
    self.clients[call.id] = call
    local report, err = send(call.wire, card, host)
    if not report then self.clients[call.id] = nil; return nil, err end
    return call.id
  end
  function self:poll(id)
    local call = self.clients[id]
    if not call then return nil, "ENOENT_RPC_CALL" end
    if not call.done then return false end
    return true, util.copy(call.value), call.error
  end
  function self:take(id)
    local ready, value, err = self:poll(id)
    if ready == nil then return nil, value end
    if not ready then return nil, "EAGAIN" end
    self.clients[id] = nil
    return value, err
  end
  function self:request(host, model, action, player, args, card)
    if type(deps.wait) ~= "function" then return nil, "RPC_WAIT_UNAVAILABLE" end
    local id, err = self:begin(host, model, action, player, args, card)
    if not id then return nil, err end
    while self.clients[id] and not self.clients[id].done do
      self:tick()
      if not self.clients[id].done then deps.wait(math.min(retry, math.max(0, self.clients[id].deadline - deps.clock()))) end
    end
    return self:take(id)
  end
  function self:tick()
    local now = deps.clock()
    for key, entry in pairs(self.inbound) do if entry.state ~= "executing" and now >= entry.expires then self.inbound[key] = nil end end
    for id, call in pairs(self.clients) do
      if call.done then if now >= call.expires then self.clients[id] = nil end
      elseif now >= call.deadline then self.stats.timeouts = self.stats.timeouts + 1; completeClient(call, nil, "ETIMEDOUT")
      elseif now - call.lastSent >= retry then call.lastSent = now; send(call.wire, call.source, call.peer) end
    end
    if deps.log and (reportedDenied ~= self.stats.denied or reportedFaults ~= self.stats.faults) then
      pcall(deps.log, "warning", "RPC_ACCESS_FAILURES", {denied = self.stats.denied - reportedDenied,
        faults = self.stats.faults - reportedFaults, lastError = self.lastError})
      reportedDenied, reportedFaults = self.stats.denied, self.stats.faults
    end
  end
  local function receive(receiver, source, destination, logicalPort, service, payload)
    if not self.running then return end
    if service ~= "rpc" or logicalPort ~= port or destination ~= receiver or not deps.network.cards[receiver] then return end
    local verified, err = Protocol.verify(crypto, trust, payload, source, receiver, port, maxFrame)
    if not verified then self.stats.denied = self.stats.denied + 1; return end
    if not self.running then return end
    local body, cert = verified.body, verified.certificate
    local key = source .. "/" .. body.id
    if body.kind == "hello" then
      if not trust:verify(certificateWire, "server", receiver) then self.stats.denied = self.stats.denied + 1; return end
      if type(body.request) ~= "string" then return end
      local digest, existing = crypto.sha256(verified.bodyWire), self.inbound[key]
      if existing then
        if existing.helloDigest == digest and existing.certificateWire == verified.certificateWire then send(existing.challengeWire, receiver, source) end
        return
      end
      local request = codec.decode(body.request, maxFrame)
      if type(request) ~= "table" or type(request.model) ~= "string" or type(request.action) ~= "string" or type(request.args) ~= "table"
          or not Certificates.granted(cert, request.model, request.action) then self.stats.denied = self.stats.denied + 1; return end
      local count, peers, bytes = usageCount(self.inbound, source)
      if peers >= maxPeer or #payload > maxBytes then self.stats.denied = self.stats.denied + 1; return end
      local challenge = nonce(crypto)
      local wire = frame(crypto, certificateWire, "challenge", body.id, receiver, source, body.client_nonce,
        {challenge = challenge, hello_digest = digest})
      if not self.running then return end
      if self.inbound[key] then send(self.inbound[key].challengeWire, receiver, source); return end
      local _, active = usageCount(self.inbound, source)
      if active >= maxPeer then self.stats.denied = self.stats.denied + 1; return end
      if not makeRoom(#payload + #wire, true) then self.stats.denied = self.stats.denied + 1; return end
      self.inbound[key] = {state = "challenge", peer = source, receiver = receiver, id = body.id, clientNonce = body.client_nonce,
        challenge = challenge, helloDigest = digest, request = request, certificate = cert, certificateWire = verified.certificateWire,
        challengeWire = wire, bytes = #payload + #wire, expires = deps.clock() + challengeTTL}
      self.stats.accepted = self.stats.accepted + 1
      send(wire, receiver, source)
    elseif body.kind == "invoke" then
      if not trust:verify(certificateWire, "server", receiver) then self.stats.denied = self.stats.denied + 1; return end
      local entry = self.inbound[key]
      if not entry or entry.receiver ~= receiver or entry.clientNonce ~= body.client_nonce or entry.challenge ~= body.challenge
          or entry.helloDigest ~= body.hello_digest or entry.certificateWire ~= verified.certificateWire then self.stats.denied = self.stats.denied + 1; return end
      if entry.state == "done" then
        if entry.responseWire then send(entry.responseWire, receiver, source)
        else
          local ok, wire = pcall(frame, crypto, certificateWire, "result", body.id, receiver, source, body.client_nonce,
            {challenge = entry.challenge, hello_digest = entry.helloDigest, ok = false, error = "ERR_RPC_RESULT"})
          if ok then send(wire, receiver, source) end
        end
        return
      end
      if entry.state ~= "challenge" or deps.clock() >= entry.expires then return end
      if not self.running then return end
      -- Consume the challenge before invoking anything; reentrant duplicates see executing.
      entry.state = "executing"
      self.stats.executed = self.stats.executed + 1
      local ok, value, callErr = pcall(deps.dispatch, entry.request.model, entry.request.action, cert.subject, util.copy(entry.request.args),
        {source = source, receiver = receiver, id = body.id, certificate = util.copy(cert)})
      if not ok then value, callErr = nil, "ERR_RPC_HANDLER" end
      local extra = {challenge = entry.challenge, hello_digest = entry.helloDigest, ok = value ~= nil, value = value, error = callErr}
      local encoded, response = pcall(frame, crypto, certificateWire, "result", body.id, receiver, source, body.client_nonce, extra)
      if not encoded or not makeRoom(#response, false) then
        extra.ok, extra.value, extra.error = false, nil, "ERR_RPC_RESULT"
        encoded, response = pcall(frame, crypto, certificateWire, "result", body.id, receiver, source, body.client_nonce, extra)
      end
      entry.state, entry.expires = "done", deps.clock() + cacheTTL
      if encoded and makeRoom(#response, false) then
        entry.responseWire = response; entry.bytes = entry.bytes + #response
        send(response, receiver, source)
      end
      if deps.log then pcall(deps.log, "info", "RPC_EXECUTED", {subject = cert.subject, model = entry.request.model, action = entry.request.action, ok = value ~= nil}) end
    else
      local call = self.clients[body.id]
      if not call or call.done or call.peer ~= source or call.source ~= receiver or call.clientNonce ~= body.client_nonce
          or call.helloDigest ~= body.hello_digest then self.stats.denied = self.stats.denied + 1; return end
      if deps.clock() >= call.deadline then self.stats.timeouts = self.stats.timeouts + 1; completeClient(call, nil, "ETIMEDOUT"); return end
      if body.kind == "challenge" and call.phase == "hello" then
        local wire = frame(call.identity.crypto, call.identity.wire, "invoke", body.id, receiver, source, body.client_nonce,
          {challenge = body.challenge, hello_digest = body.hello_digest})
        if not self.running or call.done then return end
        call.phase, call.challenge, call.serverKey, call.wire, call.lastSent = "invoke", body.challenge, cert.public_key, wire, deps.clock()
        send(wire, receiver, source)
      elseif body.kind == "result" and call.phase == "invoke" and call.challenge == body.challenge and call.serverKey == cert.public_key
          and type(body.ok) == "boolean" then
        local count = 0; for _ in pairs(self.peers) do count = count + 1 end
        if count >= maxSessions then self.peers = {} end
        self.peers[source] = verified.certificateWire
        if body.ok then completeClient(call, body.value)
        else completeClient(call, nil, type(body.error) == "string" and body.error or "ERR_RPC_REMOTE") end
      end
    end
  end
  local function onMessage(_, ...)
    local ok, err = pcall(receive, ...)
    if not ok then
      self.stats.denied, self.stats.faults = self.stats.denied + 1, self.stats.faults + 1
      self.lastError = tostring(err):sub(1, 256)
    end
  end
  function self:start()
    if self.running then return false end
    self.running = true
    deps.event.listen("spacecross_network_message", onMessage)
    self.timer = deps.event.timer(math.min(retry, challengeTTL), function() self:tick() end, math.huge)
    return true
  end
  function self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    deps.event.ignore("spacecross_network_message", onMessage)
    for _, call in pairs(self.clients) do if not call.done then completeClient(call, nil, "ESHUTDOWN") end end
    self.inbound, self.running = {}, false
  end
  return self
end
return M
