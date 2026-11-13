local Fabric = require("spacecross.network.tests.stubs.fabric")
local Transport = require("spacecross.network.transport")
local Certificates = require("spacecross.security.certificates")
local RPC = require("spacecross.rpc.service")
local Fake = require("spacecross.rpc.tests.stubs.crypto")
local codec = require("spacecross.core.codec")
local M = {}
function M.certificate(key, subject, addresses, usage, grants, serial)
  local ca = Fake.new("root")
  local body = codec.encode({v = 1, issuer = "root", serial = serial or key, subject = subject,
    addresses = addresses, usage = usage, public_key = key, grants = grants or {}})
  return codec.encode({body = body, signature = ca.sign(Certificates.domain .. ca.sha256(body))})
end
function M.new()
  local f = Fabric.new(); local a, b = f:host("client"), f:host("server")
  f:card(a, "client", "modem"); f:card(b, "server", "modem")
  for _, p in ipairs({a, b}) do p.network = Transport.new(p); p.network:start() end
  a.crypto, b.crypto = Fake.new("client-key"), Fake.new("server-key")
  a.certificate = M.certificate("client-key", "Owner", {"client"}, {"client"}, {["*"] = {"*"}})
  b.certificate = M.certificate("server-key", "Ship", {"server"}, {"server"})
  a.trust = Certificates.new(a.crypto, {authorities = {root = "root"}})
  b.trust = Certificates.new(b.crypto, {authorities = {root = "root"}})
  b.executed = 0
  b.dispatch = function(model, action, subject, args)
    assert(subject == "Owner"); b.executed = b.executed + 1
    if action == "false" then return false end
    if action == "fail" then return nil, "EACCES" end
    return {model = model, action = action, value = args.value}
  end
  a.dispatch = function() error("client has no exposed models") end
  for _, p in ipairs({a, b}) do
    p.wait = function(wait) f:drain(); f:advance(math.min(wait, 0.1)) end
    p.rpc = RPC.new(p, {certificate = p.certificate, timeout = 4, retryInterval = 0.5, challengeTTL = 3})
    p.rpc:start()
  end
  f:drain()
  return f, a, b
end
return M
