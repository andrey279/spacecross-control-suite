local P = require("tests.stubs.platform")
local Socket = require("spacecross.cnc.tests.stubs.socket")
local Channel = require("spacecross.cnc.channel")
local Agent = require("spacecross.cnc.agent")
local RPC = require("spacecross.rpc.service")
local Cert = require("spacecross.security.certificates")
local System = require("spacecross.rpc.tests.stubs.system")
local Fake = require("spacecross.rpc.tests.stubs.crypto")
local App = require("spacecross.app")
local codec = require("spacecross.core.codec")
local H = require("tests.support")
local function fixture()
  local ship, server = P.new(), P.new()
  local sa, sb, a, b = Socket.pair()
  ship.components.internet = {type = "internet", connect = function() return sa end}
  server.components.control = {type = "internet", connect = function() return sb end}
  ship.rpc = {crypto = Fake.new("ship-key"), authorities = {root = "root"}, certificate = System.certificate("ship-key", "Ship", {"internet"}, {"client", "server"}, {_cnc = {"heartbeat", "whitelist", "alert"}, _logs = {"put"}})}
  local serverCrypto = Fake.new("control-key")
  local cert = System.certificate("control-key", "Owner", {"control"}, {"client", "server"}, {["*"] = {"*"}})
  ship.cncPeerCertificate = cert
  local channel = Channel.new(server, {address = "control", peer = "internet", host = "ship", peerCertificate = ship.rpc.certificate})
  server.network, server.crypto = channel, serverCrypto
  server.trust = Cert.new(serverCrypto, {authorities = {root = "root"}})
  server.dispatch = function(model, action, actor, args)
    assert(actor == "Ship")
    if model == "_cnc" and action == "heartbeat" then server.satelliteStatus = args.satellite; return {alive = true} end
    if model == "_cnc" and action == "whitelist" then return {values = {"Owner", "friend"}} end
    if model == "_cnc" and action == "alert" then server.alert = args; return {accepted = true} end
    if model == "_logs" and action == "put" then
      server.uploaded = args.data; return {receipt = args.id, digest = serverCrypto.sha256(args.data)}
    end
  end
  server.rpc = RPC.new(server, {certificate = cert}); server.rpc:start(); channel:start()
  ship.nodeId = "ship-node"
  ship.crypto = {seal = function(data) return "SEALED:" .. data end}
  local config = {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs", interval = 0.2}, rpc = {enabled = true},
    cnc = {enabled = true, host = "control.test", address = "internet", peer = "control", actor = "Ship", heartbeatInterval = 0.5},
    watcher = {enabled = true, range = 16}, defense = {enabled = true, armed = false, scorchedEarth = true, heartbeatTimeout = 2,
      channels = {{address = "test-lamp", side = 1, value = 1}}}}
  local app = App.new(ship, config); app:start()
  local function advance(seconds)
    for _ = 1, math.floor(seconds / 0.1 + 0.5) do ship:advance(0.1); server:advance(0.1) end
  end
  return app, ship, server, channel, advance, a, b
end
local function outbound_rpc_heartbeat_logs_and_control_share_one_channel()
  local app, ship, server, channel, advance = fixture()
  advance(3)
  assert(app.cnc.lastHeartbeat and app.defense:snapshot().heartbeatAge < 2)
  assert(not app.defense:heartbeat({alive = true}) and not app.cnc:verifyHeartbeat({}))
  assert(server.uploaded and server.uploaded:sub(1, 7) == "SEALED:")
  -- Server command uses the same model ACL and actor from the pinned Owner cert.
  local id = assert(server.rpc:begin("internet", "hardware", "snapshot", "Owner", {}, "control"))
  advance(2)
  local ready, value = server.rpc:poll(id); assert(ready and value.count == 0)
  app:stop(); channel:stop(); server.rpc:stop()
  assert(not app.cncChannel.connected and not app.cnc.running and not next(ship.timers))
  return H.success()
end
local function disconnection_keeps_encrypted_spool_and_expires_heartbeat()
  local app, ship, server, channel, advance, a, b = fixture()
  advance(2); assert(app.cnc.lastHeartbeat)
  local oldHeartbeat = app.cnc.lastHeartbeat
  channel:stop(); server.rpc:stop()
  app.logger:write("critical", "OFFLINE", {secret = "retained"})
  advance(5)
  assert(app.defense:snapshot().heartbeatAge >= 2)
  app.defense:tick(); assert(app.defense:snapshot().decision.trigger and not app.defense.fired)
  local retained = false
  for name, data in pairs(ship.files) do if name:match("%.sealed$") then assert(data:sub(1, 7) == "SEALED:"); retained = true end end
  assert(retained and app.running and app.cncChannel.lastError)
  -- New socket endpoints in the game; reset the duplex stub to model reconnection.
  a.closed, b.closed, a.buffer, b.buffer = false, false, "", ""
  channel:start(); server.rpc:start(); advance(20)
  assert(app.cnc.lastHeartbeat > oldHeartbeat and app.cncChannel.trusted)
  local offlineRemains = false
  for name, data in pairs(ship.files) do
    if name:match("%.sealed$") and data:find("OFFLINE", 1, true) then offlineRemains = true end
  end
  assert(not offlineRemains)
  channel:stop(); server.rpc:stop()
  app:stop(); return H.success()
end
local function tcp_partial_frames_pin_limits_and_connect_timeout()
  local p = P.new(); local sa, sb, a, b = Socket.pair()
  a.readSize, b.writeSize = 3, 2
  p.components.internet = {type = "internet", connect = function() return sa end}
  local c = Channel.new(p, {address = "internet", peer = "control", host = "server", peerCertificate = "pinned", connectTimeout = 0.2})
  local received = 0
  p.event.listen("spacecross_network_message", function() received = received + 1 end)
  c:start(); p:advance(0.1)
  local wire = codec.encode({certificate = "pinned", body = "opaque RPC"})
  local framed = string.char(0, 0, 0, #wire) .. wire
  while #framed > 0 do local n = sb.write(framed); framed = framed:sub(n + 1) end
  p:advance(3); assert(received == 1)
  assert(not c:send("control", 1, "body", "internet", "rpc"))
  b.buffer = ""; a.buffer = "\0\1\255\255" -- 131071 > maxFrame
  p:advance(0.3); assert(not c.connected and c.lastError:find("frame length"))
  c:stop()
  local p2 = P.new(); local bad, _, badState = Socket.pair()
  p2.components.internet = {type = "internet", connect = function() return bad end}
  local pin = Channel.new(p2, {address = "internet", peer = "control", host = "server", peerCertificate = "pinned"})
  pin:start(); p2:advance(0.1)
  -- Wrong certificate never reaches the shared RPC event stream.
  local wrong = codec.encode({certificate = "different", body = "x"})
  badState.buffer = string.char(0, 0, 0, #wrong) .. wrong
  local rejected = 0; p2.event.listen("spacecross_network_message", function() rejected = rejected + 1 end)
  p2:advance(0.1)
  assert(not pin.connected and pin.lastError:find("pin mismatch") and rejected == 0)
  pin:stop()
  a.connecting = true; a.closed, b.closed = false, false
  c:start(); p:advance(0.5)
  assert(not c.connected and c.lastError:find("connect timeout")); c:stop()
  return H.success()
end
local function receipt_must_match_id_and_content_and_proof_is_one_use()
  local p = P.new(); local accepted, pending = 0, {}
  local agent
  local rpc = {begin = function(_, _, model) pending.model = model; return "call" end,
    poll = function() return true, pending.result end, take = function() end}
  local channel = {connected = true, authenticated = function() end}
  agent = Agent.new({rpc = rpc, channel = channel, clock = p.clock, event = p.event, crypto = Fake.new("x"),
    heartbeat = function(proof) assert(agent:verifyHeartbeat(proof)); assert(not agent:verifyHeartbeat(proof)); accepted = accepted + 1 end},
    {peer = "control", actor = "Ship", address = "internet"})
  agent:start(); agent:tick(); pending.result = {alive = true}; agent:tick(); assert(accepted == 1)
  assert(not agent:upload("id.sealed", "encrypted"))
  pending.result = {receipt = "id.sealed", digest = "wrong"}
  assert(not agent:upload("id.sealed", "encrypted"))
  assert(not agent:upload("id.sealed", "encrypted"))
  pending.result = {receipt = "id.sealed", digest = Fake.new("x").sha256("encrypted")}
  assert(agent:upload("id.sealed", "encrypted") == "id.sealed")
  agent:stop(); return H.success()
end
local function satellite_status_whitelist_and_alert_use_authenticated_rpc_calls()
  local p, calls, pending = P.new(), {}, {}
  local rpc = {
    begin = function(_, host, model, action, actor, args, card)
      calls[#calls + 1] = {host, model, action, actor, args, card}
      local id = "call-" .. #calls; pending[id] = {ready = false}; return id
    end,
    poll = function(_, id)
      local entry = pending[id]
      if not entry.ready then return false end
      return true, entry.value
    end,
    take = function(_, id) local entry = pending[id]; pending[id] = nil; return entry.value end,
  }
  local agent = Agent.new({rpc = rpc, channel = {connected = true}, clock = p.clock,
    event = p.event, crypto = Fake.new("ship")},
    {peer = "control", actor = "Ship", address = "internet", heartbeatInterval = 10})
  assert(agent:start())
  assert(agent:updateSatelliteStatus({mode = "charges", state = "idle"}))
  agent:tick()
  assert(calls[1][2] == "_cnc" and calls[1][3] == "heartbeat" and calls[1][5].satellite.mode == "charges")
  pending["call-1"] = {ready = true, value = {alive = true}}
  agent:tick()
  local whitelistId = assert(agent:beginSatelliteWhitelist())
  assert(calls[2][3] == "whitelist")
  pending[whitelistId] = {ready = true, value = {values = {"Owner", "friend"}}}
  local ready, values = agent:pollSatelliteWhitelist(whitelistId)
  assert(ready and values[2] == "friend")
  assert(agent:sendSatelliteAlert({mode = "charges", target = {id = "hostile"}}))
  assert(calls[3][3] == "alert" and calls[3][5].target.id == "hostile")
  agent:stop()
  return H.truth(not next(p.timers))
end
local function satellite_whitelist_and_attack_alert_traverse_the_live_cnc_channel()
  local app, ship, server, channel, advance = fixture()
  advance(2)
  assert(app.cnc:updateSatelliteStatus({mode="charges",state="armed"}))
  advance(1)
  assert(server.satelliteStatus.mode=="charges" and server.satelliteStatus.state=="armed")
  local id=assert(app.cnc:beginSatelliteWhitelist())
  advance(1)
  local ready,value=app.cnc:pollSatelliteWhitelist(id)
  assert(ready and value[2]=="friend")
  assert(app.cnc:sendSatelliteAlert({mode="jump",target={id="hostile"}}))
  advance(1)
  assert(server.alert.mode=="jump" and server.alert.target.id=="hostile")
  app:stop(); channel:stop(); server.rpc:stop()
  return H.truth(not next(ship.timers))
end
local all_tests = {
  {test_name = "outbound_rpc_heartbeat_logs_and_control_share_one_channel", test = outbound_rpc_heartbeat_logs_and_control_share_one_channel},
  {test_name = "disconnection_keeps_encrypted_spool_and_expires_heartbeat", test = disconnection_keeps_encrypted_spool_and_expires_heartbeat},
  {test_name = "tcp_partial_frames_pin_limits_and_connect_timeout", test = tcp_partial_frames_pin_limits_and_connect_timeout},
  {test_name = "receipt_must_match_id_and_content_and_proof_is_one_use", test = receipt_must_match_id_and_content_and_proof_is_one_use},
  {test_name = "satellite_status_whitelist_and_alert_use_authenticated_rpc_calls", test = satellite_status_whitelist_and_alert_use_authenticated_rpc_calls},
  {test_name = "satellite_whitelist_and_attack_alert_traverse_the_live_cnc_channel", test = satellite_whitelist_and_attack_alert_traverse_the_live_cnc_channel},
}
return all_tests
