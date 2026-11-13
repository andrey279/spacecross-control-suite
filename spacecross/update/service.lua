local codec = require("spacecross.core.codec")
local util = require("spacecross.core.util")
local Manifest = require("spacecross.update.manifest")
local Package = require("spacecross.update.package")
local Certificates = require("spacecross.security.certificates")
local M = {}
local function token(v) return type(v) == "string" and #v == 64 and v:match("^%x+$") end
local function integer(v, lo, hi) return type(v) == "number" and v % 1 == 0 and v >= lo and v <= hi end
local function set(list) local out = {}; for _, v in ipairs(list) do out[v] = true end; return out end
function M.new(deps, config)
  local self = {running = false, state = {phase = "idle", filesSent = 0}, pub = nil, client = nil}
  local epoch, workEpoch = 0, 0
  local packageDeps = {}; for k, v in pairs(deps) do packageDeps[k] = v end
  packageDeps.cancelled = function() return not self.running or epoch ~= workEpoch end
  local package = Package.new(packageDeps, config)
  local function active() return self.running and epoch == workEpoch end
  local function release()
    if self.lease then package:release(self.lease); self.lease = nil end
  end
  local timer, busy, checkRequested, nextCheck = nil, false, false, math.huge
  local port, chunkSize = 27016, 4096
  local function log(level, code, fields) if deps.log then pcall(deps.log, level, code, fields) end end
  local function cachePath(revision, path) return config.root .. "/cache/" .. revision .. "/" .. path end
  local function cached(m, path)
    local data = deps.fs.read(cachePath(m.revision, path))
    if Manifest.verify(deps.hash, m.files[path], data) then return data end
  end
  local function save(m, path, data)
    assert(Manifest.verify(deps.hash, m.files[path], data), "update file digest mismatch")
    local name = cachePath(m.revision, path)
    util.check(deps.fs.mkdir(assert(name:match("^(.*)/"))))
    util.check(deps.fs.atomicWrite(name, data))
  end
  local function broadcast(packet)
    local sent, err = deps.network:broadcast(port, codec.encode(packet), config.cards, "update")
    assert(sent, err); return sent
  end
  local function finish(err)
    local changed = self.publishedResult and self.publishedResult.changed or self.pub and self.pub.result.changed or self.client and self.client.result and self.client.result.changed
    release(); self.publishedResult = nil
    self.pub, self.client = nil, nil
    self.state.phase, self.state.error = err and "failed" or "complete", err and tostring(err) or nil
    log(err and "error" or "info", err and "UPDATE_FAILED" or "UPDATE_COMPLETE", {error = err and tostring(err), generation = self.state.generation})
    if changed and deps.reboot then deps.reboot() end
  end
  local function roots()
    return config.components or Manifest.current(deps.fs, config.root).selected
  end
  function self:trigger(actor)
    if actor and not deps.isOwner(actor) then return nil, "EACCES" end
    if not self.running then return nil, "ENOTRUNNING" end
    if self.pub or self.client or checkRequested then return nil, "EBUSY" end
    if not deps.hasInternet() or not deps.source then return nil, "NO_INTERNET_SOURCE" end
    checkRequested = true; return true
  end
  function self:snapshot() return util.copy(self.state) end
  local function peer(actor, context)
    return context and context.certificate and deps.network.cards[context.receiver]
      and (deps.isOwner(actor) or deps.isPeer(actor))
  end
  local function requested(p, client, args)
    local selected, paths = Manifest.select(p.manifest, args.components)
    local allowed, seen = set(paths), {}
    assert(type(args.missing) == "table" and #args.missing <= 4096, "invalid requested files")
    local count = 0
    for i, path in pairs(args.missing) do
      assert(integer(i, 1, #args.missing) and allowed[path] and not seen[path], "file outside selected components")
      count, seen[path] = count + 1, true
    end
    assert(count == #args.missing, "sparse requested files")
    client.selected = selected
    return seen
  end
  function self:rpc(action, actor, args, context)
    if not self.running or not peer(actor, context) then return nil, "EACCES" end
    local p = self.pub
    if not p or args.session ~= p.id or deps.clock() >= p.deadline then return nil, "ENOENT_UPDATE" end
    local address = context.source
    local client = p.clients[address]
    if action == "describe" then
      if not client then
        if p.phase ~= "collect" then return nil, "UPDATE_JOIN_CLOSED" end
        local count = 0; for _ in pairs(p.clients) do count = count + 1 end
        if count >= (config.maxClients or 64) then return nil, "EBUSY" end
        client = {actor = actor, round = -1}; p.clients[address] = client; p.quiet = deps.clock()
      end
      return {session = p.id, revision = p.manifest.revision, size = #p.raw, digest = p.digest}
    end
    if not client or client.actor ~= actor then return nil, "ENOENT_UPDATE_CLIENT" end
    if action == "manifest" then
      if not integer(args.offset, 1, #p.raw) or not integer(args.length, 1, 4096) then return nil, "EINVAL_CHUNK" end
      return p.raw:sub(args.offset, args.offset + args.length - 1)
    elseif action == "need" then
      if not integer(args.round, 0, config.maxRepairRounds or 3) then return nil, "EINVAL_ROUND" end
      local requestKey = codec.encode(args)
      if client.lastRequest == requestKey then return {round = client.round, accepted = true} end
      if args.round <= client.round then return nil, "STALE_UPDATE_REQUEST" end
      local ok, missing = pcall(requested, p, client, args)
      if not ok then return nil, tostring(missing) end
      local round = args.round
      for path in pairs(missing) do
        if p.sent[path] and p.sent[path] >= round then round = p.sent[path] + 1 end
      end
      if round > (config.maxRepairRounds or 3) then return nil, "UPDATE_REPAIR_LIMIT" end
      for path in pairs(missing) do
        local key = round .. "/" .. path
        if not p.tasks[key] then p.tasks[key] = {path = path, round = round} end
      end
      client.round, client.lastRequest, client.mode = round, requestKey, args.internet and "internet" or "lan"
      return {round = round, accepted = true}
    elseif action == "status" then
      if not client.mode then return nil, "UPDATE_NEEDS_REQUIRED" end
      local complete = true
      for _, path in ipairs(args.missing or {}) do
        if not p.manifest.files[path] then return nil, "INVALID_UPDATE_FILE" end
        if not p.sent[path] or p.sent[path] < client.round then complete = false end
      end
      return {transmitted = complete, phase = p.phase}
    elseif action == "done" then
      if type(args.ok) ~= "boolean" then return nil, "EINVAL_RESULT" end
      client.done, client.ok = true, args.ok
      p.doneAt = deps.clock()
      return {ack = true}
    end
    return nil, "ENOTSUP"
  end
  local function preparePublisher()
    self.state = {phase = "preparing", filesSent = 0}
    self.lease = assert(package:reserve())
    local revision = assert(deps.source.latest())
    local raw = assert(deps.source.manifest(revision))
    local manifest = assert(Manifest.decode(raw, revision))
    local plan = package:plan(raw, roots())
    local id = deps.id(); assert(token(id), "secure update session ID required")
    local digest = Manifest.digest(deps.hash, raw)
    local result, err = package:install(plan, deps.source.fetch, true, self.lease)
    assert(result, err)
    if not active() then return end
    self.publishedResult = result
    local now = deps.clock()
    self.pub = {id = id, raw = raw, manifest = manifest, digest = digest, result = result,
      clients = {}, tasks = {}, sent = {}, phase = "collect", started = now, quiet = now,
      deadline = now + (config.timeout or 120), announceAt = 0}
    self.state.revision, self.state.generation, self.state.phase = revision, result.generation, "collecting"
  end
  local function publisherTick()
    local p, now = self.pub, deps.clock()
    if now >= p.deadline then finish("UPDATE_DISTRIBUTION_TIMEOUT"); return end
    if p.phase == "collect" then
      if now >= p.announceAt then
        broadcast({v = 1, kind = "offer", session = p.id})
        p.announceAt = now + 2
      end
      local ready = true
      for _, c in pairs(p.clients) do if not c.mode and not c.done then ready = false end end
      if now - p.started < (config.collectTime or 3) or not ready or now - p.quiet < (config.quietTime or 1) then
        if now - p.started < (config.maxCollectTime or 30) then return end
      end
      p.phase = "transfer"; self.state.phase = "sending"
    end
    if not p.current then
      for _, key in ipairs(util.sortedKeys(p.tasks)) do
        if not p.tasks[key].done then p.current = p.tasks[key]; break end
      end
      if p.current then
        local t = p.current
        t.data = cached(p.manifest, t.path)
        if not t.data then
          local localFile = deps.fs.read(config.root .. "/releases/" .. p.result.generation .. "/" .. t.path)
          if Manifest.verify(deps.hash, p.manifest.files[t.path], localFile) then t.data = localFile end
        end
        if not t.data then
          local data, err = deps.source.fetch(p.manifest.revision, t.path)
          assert(data, err); save(p.manifest, t.path, data); t.data = data
        end
        if not active() or self.pub ~= p then return end
        t.offset = 1
      end
    end
    local t = p.current
    if t then
      broadcast({v = 1, kind = "file", session = p.id, path = t.path, round = t.round,
        offset = t.offset, data = t.data:sub(t.offset, t.offset + chunkSize - 1)})
      t.offset = t.offset + chunkSize
      if t.offset > #t.data then
        p.sent[t.path], t.done, t.data, p.current = t.round, true, nil, nil
        self.state.filesSent = self.state.filesSent + 1
      end
    else
      self.state.phase = "waiting"
      local complete = true
      for _, c in pairs(p.clients) do if not c.done then complete = false end end
      if complete and now - (p.doneAt or p.started) >= (config.finishGrace or 1) then finish() end
    end
  end
  local function call(c, action, args)
    assert(active() and self.client == c, "UPDATE_CANCELLED")
    args.session = c.id
    local id, err = deps.rpc:begin(c.source, "_update", action, config.actor, args, c.card)
    assert(id, err); c.call, c.action = id, action
  end
  local function needs(c, round)
    local list = util.sortedKeys(c.missing)
    call(c, "need", {components = c.plan.selected, missing = c.internet and {} or list, internet = c.internet, round = round})
    c.phase = "need"
  end
  local function makePlan(c, raw)
    assert(#raw == c.meta.size and Manifest.digest(deps.hash, raw) == c.meta.digest, "UPDATE_MANIFEST_DIGEST")
    assert(Manifest.decode(raw, c.meta.revision))
    c.plan = package:plan(raw, roots()); c.raw = raw
    c.missing = {}
    for _, path in ipairs(c.plan.missing) do if not cached(c.plan.manifest, path) then c.missing[path] = true end end
    needs(c, 0)
  end
  local function acceptResult(c, action, value)
    if action == "describe" then
      local cert = assert(deps.rpc:peer(c.source), "missing publisher identity")
      local trusted = assert((config.publishers or {})[c.source], "untrusted update publisher")
      assert(cert.subject == trusted and Certificates.granted(cert, "_update", "publish"), "UPDATE_PUBLISHER_IDENTITY")
      self.lease = assert(package:reserve())
      assert(type(value) == "table" and value.session == c.id and integer(value.size, 1, 131072)
        and type(value.digest) == "string" and #value.digest == 64, "invalid manifest descriptor")
      c.meta, c.internet = value, deps.hasInternet()
      if c.internet then makePlan(c, assert(deps.source.manifest(value.revision)))
      else c.phase, c.parts, c.offset = "manifest", {}, 1 end
    elseif action == "manifest" then
      local size = math.min(4096, c.meta.size - c.offset + 1)
      assert(type(value) == "string" and #value == size, "truncated manifest page")
      c.parts[#c.parts + 1] = value; c.offset = c.offset + #value
      if c.offset > c.meta.size then makePlan(c, table.concat(c.parts)); c.parts = nil end
    elseif action == "need" then
      assert(type(value) == "table" and value.accepted and integer(value.round, 0, config.maxRepairRounds or 3), "invalid needs receipt")
      c.round, c.phase, c.checkAt = value.round, "data", deps.clock() + (config.repairInterval or 2)
    elseif action == "status" then
      assert(type(value) == "table" and type(value.transmitted) == "boolean", "invalid update status")
      if value.transmitted and next(c.missing) then needs(c, c.round + 1)
      else c.checkAt = deps.clock() + (config.repairInterval or 2) end
    elseif action == "done" then
      assert(type(value) == "table" and value.ack == true, "invalid update result receipt")
      finish()
    end
  end
  local function clientTick()
    local c = self.client
    if deps.clock() >= c.deadline then finish("UPDATE_RECEIVE_TIMEOUT"); return end
    if c.call then
      local ready, value, err = deps.rpc:poll(c.call)
      if ready == false then return end
      if ready then deps.rpc:take(c.call) end
      c.call = nil
      assert(ready and value ~= nil, err or "UPDATE_RPC_FAILED")
      acceptResult(c, c.action, value)
      return
    end
    if c.phase == "describe" then call(c, "describe", {})
    elseif c.phase == "manifest" then call(c, "manifest", {offset = c.offset, length = math.min(4096, c.meta.size - c.offset + 1)})
    elseif c.phase == "data" then
      if next(c.missing) and c.internet then
        local path = util.sortedKeys(c.missing)[1]
        local data, err = deps.source.fetch(c.plan.manifest.revision, path)
        assert(data, err); save(c.plan.manifest, path, data); c.missing[path] = nil
      elseif not next(c.missing) then
        self.state.phase = "installing"
        c.result = assert(package:install(c.plan, function(_, path) return cached(c.plan.manifest, path) end, true, self.lease))
        self.state.generation = c.result.generation
        c.phase = "done"; call(c, "done", {ok = true, generation = c.result.generation})
      elseif deps.clock() >= c.checkAt then call(c, "status", {missing = util.sortedKeys(c.missing)}) end
    end
  end
  local function onPacket(_, receiver, source, destination, logicalPort, service, wire)
    if not self.running or service ~= "update" or logicalPort ~= port or destination ~= "*" then return end
    local packet = codec.decode(wire, 16384)
    if type(packet) ~= "table" or packet.v ~= 1 or not token(packet.session) then return end
    if packet.kind == "offer" then
      if self.pub or self.client or checkRequested or not (config.publishers or {})[source] then return end
      self.client = {id = packet.session, source = source, card = receiver, phase = "describe",
        deadline = deps.clock() + (config.timeout or 120), assemblies = {}}
      self.state = {phase = "receiving", filesSent = 0}
    elseif packet.kind == "file" then
      local c = self.client
      if not c or c.source ~= source or c.id ~= packet.session or (c.phase ~= "data" and c.phase ~= "need") or c.internet or not c.missing[packet.path] then return end
      local meta = c.plan.manifest.files[packet.path]
      if not integer(packet.round, c.round or 0, config.maxRepairRounds or 3) or not integer(packet.offset, 1, math.max(1, meta.size))
        or (packet.offset - 1) % chunkSize ~= 0 or type(packet.data) ~= "string"
        or #packet.data ~= math.min(chunkSize, meta.size - packet.offset + 1) then return end
      local a = c.assemblies[packet.path]
      if not a then
        local count = 0; for _ in pairs(c.assemblies) do count = count + 1 end
        if count >= 2 then return end
        a = {parts = {}, bytes = 0, round = packet.round}; c.assemblies[packet.path] = a
      end
      if packet.round > a.round then a.parts, a.bytes, a.round = {}, 0, packet.round end
      if packet.round < a.round or a.parts[packet.offset] then return end
      a.parts[packet.offset], a.bytes = packet.data, a.bytes + #packet.data
      if a.bytes == meta.size then
        local parts = {}; for offset = 1, math.max(1, meta.size), chunkSize do parts[#parts + 1] = a.parts[offset] end
        local data = table.concat(parts)
        c.assemblies[packet.path] = nil
        if Manifest.verify(deps.hash, meta, data) then
          save(c.plan.manifest, packet.path, data); c.missing[packet.path] = nil
        end
      end
    end
  end
  local function onMessage(...)
    local ok, err = pcall(onPacket, ...)
    if not ok then self.packetError = tostring(err); log("warning", "UPDATE_PACKET_ERROR", {error = tostring(err)}) end
  end
  function self:tick()
    if not self.running or busy then return end
    local currentEpoch = epoch; workEpoch = epoch
    busy = true
    local ok, err = pcall(function()
      if self.pub then publisherTick()
      elseif self.client then clientTick()
      elseif checkRequested then checkRequested = false; preparePublisher()
      elseif deps.clock() >= nextCheck then
        nextCheck = deps.clock() + (config.checkInterval or math.huge)
        if deps.hasInternet() then self:trigger() end
      end
    end)
    busy = false
    if currentEpoch ~= epoch or not self.running then return end
    if not ok then finish(tostring(err)) end
  end
  function self:start()
    if self.running then return false end
    epoch = epoch + 1
    if not busy then workEpoch = epoch end
    self.running = true
    self.state.phase = "idle"
    nextCheck = deps.clock() + (config.checkInterval or math.huge)
    deps.event.listen("spacecross_network_message", onMessage)
    timer = deps.event.timer(config.interval or 0.1, function() self:tick() end, math.huge)
    return true
  end
  function self:stop()
    epoch = epoch + 1
    self.running, checkRequested = false, false
    if timer then deps.event.cancel(timer); timer = nil end
    deps.event.ignore("spacecross_network_message", onMessage)
    self.pub, self.client = nil, nil
    self.state.phase = "stopped"
    self.publishedResult = nil; release()
  end
  return self
end
return M
