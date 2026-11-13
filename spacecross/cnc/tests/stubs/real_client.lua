-- PC-only cross-language integration fixture. Hardware/crypto calls cross ctypes;
-- app/channel/agent/logger/RPC/model are the actual shipped Lua implementations.
local codec = require("spacecross.core.codec")
local function call(name, ...)
  local data = _cnc_test_bridge(name, ...)
  local result, err = codec.decode(data, 200000)
  assert(not err, err)
  if type(result) == "table" and result.__error then error(result.__error, 0) end
  return result
end
local cfg = call("config")
local p = require("tests.stubs.platform").new()
p.clock = function() return call("clock") end
p.nodeId = "test-ship"
p.rpc = {certificate = cfg.ship, authorities = {root = cfg.ca}, crypto = {
  random = function(n) return call("random", tostring(n)) end,
  sha256 = function(data) return call("sha256", data) end,
  sign = function(data) return call("sign", data) end,
  verify = function(public, data, signature) return call("verify", public, data, signature) end,
}}
p.cncPeerCertificate = cfg.control
p.crypto = {seal = function(data) return call("seal", data) end}
p.components.internet = {type = "internet", connect = function(host, port)
  local id = call("connect", host, tostring(port))
  return {finishConnect = function() return true end, close = function() return call("close", id) end,
    read = function(n) return call("read", id, tostring(n)) end,
    write = function(data) return call("write", id, data) end}
end}
local app = require("spacecross.app").new(p, {owners = {"Owner"}, admins = {"Admin"},
  logging = {root = "/logs", interval = 0.2}, rpc = {enabled = true, timeout = 3},
  cnc = {enabled = true, address = "internet", host = "127.0.0.1", serverPort = cfg.port, peer = "control", actor = "Ship", heartbeatInterval = 0.2}})
local commands, receipts = 0, 0
app.model:register("probe", {snapshot = function() return {} end, command = function(_, action, args, actor)
  assert(action == "configure" and actor == "Owner" and args.player == "Admin" and args.value == 42)
  commands = commands + 1; return {actor = actor, count = commands, value = args.value}
end})
local upload = app.cnc.upload
function app.cnc:upload(...)
  local receipt, err = upload(self, ...)
  if receipt then receipts = receipts + 1 end
  return receipt, err
end
app:start(); app.logger:write("critical", "REAL_LUA_EVENT", {secret = "confidential-lua"})
local deadline = p.clock() + 7
while (commands == 0 or receipts < 2 or not app.cnc.lastHeartbeat) and p.clock() < deadline do
  p:advance(0.05); call("pause", "0.005")
end
for _ = 1, 30 do p:advance(0.05); call("pause", "0.005") end
assert(commands == 1 and receipts >= 2 and app.cnc.lastHeartbeat, "cross-language exchange incomplete")
for name, data in pairs(p.files) do if name:match("%.sealed$") then assert(not data:find("confidential-lua", 1, true)) end end
call("report", codec.encode({commands = commands, receipts = receipts, heartbeat = app.cnc.lastHeartbeat ~= nil}))
app:stop()
