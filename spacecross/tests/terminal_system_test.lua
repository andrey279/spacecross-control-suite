local Fabric = require("spacecross.network.tests.stubs.fabric")
local Certificates = require("spacecross.rpc.tests.stubs.system")
local Fake = require("spacecross.rpc.tests.stubs.crypto")
local Runner = require("spacecross.terminal.tests.stubs.runner")
local App = require("spacecross.app")
local H = require("tests.support")
local function app_terminal_authorization_lifecycle_and_local_service_isolation()
  local f = Fabric.new(); local apps, hosts = {}, {}
  for _, name in ipairs({"client", "ship"}) do
    local p = f:host(name); hosts[name] = p
    f:card(p, name, "modem")
    p.wait = function(seconds) f:drain(); f:advance(math.min(seconds, 0.1)) end
    p.rpc = {crypto = Fake.new(name .. "-key"), authorities = {root = "root"},
      certificate = Certificates.certificate(name .. "-key", name == "client" and "Owner" or "Ship", {name}, {"client", "server"}, {["*"] = {"*"}})}
    local c = {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs"},
      network = {enabled = true}, rpc = {enabled = true}}
    if name == "client" then
      p.rpc.identities = {{certificate = Certificates.certificate("admin-key", "Admin", {name}, {"client"}, {["*"] = {"*"}}), crypto = Fake.new("admin-key")}}
    else
      c.terminal, p.terminalRunner = {enabled = true}, Runner.new()
    end
    apps[name] = App.new(p, c); apps[name]:start()
  end
  local admin, err = apps.client.rpc:request("ship", "terminal", "open", "Admin", {width = 20, height = 4, player = "Owner"})
  assert(not admin and err == "EACCES" and not next(apps.ship.terminal.sessions))
  local session = assert(apps.client.rpc:request("ship", "terminal", "open", "Owner", {width = 20, height = 4}))
  local count = 0; apps.ship.bus:subscribe(1234, function() count = count + 1 end)
  assert(apps.ship.bus:publish({proto_version = 1, msg_type = "event", port = 1234, payload = "tick"})); f:drain()
  assert(count == 1 and apps.ship.running)
  local handle = apps.ship.terminal.sessions[session.id].handle
  assert(apps.client.rpc:request("ship", "terminal", "close", "Owner", {id = session.id}))
  assert(handle.closed and apps.ship.running and apps.ship.network.running)
  local open = assert(apps.client.rpc:request("ship", "terminal", "open", "Owner", {width = 20, height = 4}))
  local second = apps.ship.terminal.sessions[open.id].handle
  apps.ship:stop(); assert(second.closed and not apps.ship.terminal.running)
  apps.client:stop(); return H.success()
end
local all_tests = {
  {test_name = "app_terminal_authorization_lifecycle_and_local_service_isolation", test = app_terminal_authorization_lifecycle_and_local_service_isolation},
}
return all_tests
