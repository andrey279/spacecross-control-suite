local Fabric = require("spacecross.network.tests.stubs.fabric")
local Cert = require("spacecross.rpc.tests.stubs.system")
local Fake = require("spacecross.rpc.tests.stubs.crypto")
local Release = require("spacecross.update.tests.stubs.release")
local App = require("spacecross.app")
local M = {}
function M.new(options)
  options = options or {}
  local f = Fabric.new()
  local raw, manifest, files = Release.new("a", {["spacecross/app.lua"] = "return {}",
    ["spacecross/autopilot/pilot.lua"] = "return {text='" .. string.rep("x", 12000) .. "'}"})
  local hosts, apps = {}, {}
  local names = {publisher = options.publisherSubject or "Owner", a = "ShipA", b = "ShipB", online = "ShipOnline"}
  for _, name in ipairs({"publisher", "a", "b", "online"}) do
    local p = f:host(name); hosts[name] = p; f:card(p, name, "modem")
    p.fs.mkdir("/system"); p.files["/system/active"] = "old"
    p.hash, p.reboots, p.downloads = Release.hash, 0, {}
    p.reboot = function() p.reboots = p.reboots + 1; assert(p.files["/system/active"] ~= "old") end
    p.hasInternet = function() return name == "publisher" or name == "online" end
    p.updateSource = {latest = function() assert(name == "publisher"); return manifest.revision end,
      manifest = function(revision) assert(revision == manifest.revision and p.hasInternet()); return raw end,
      fetch = function(revision, path)
        assert(revision == manifest.revision and p.hasInternet())
        p.downloads[path] = (p.downloads[path] or 0) + 1
        return files[path]
      end}
    p.rpc = {crypto = Fake.new(name .. "-key"), authorities = {root = "root"},
      certificate = Cert.certificate(name .. "-key", names[name], {name}, {"client", "server"},
        name == "publisher" and (options.publisherGrants or {["*"] = {"*"}}) or {_update = {"describe", "manifest", "need", "status", "done"}})}
    p.wait = function(seconds) f:drain(); f:advance(math.min(seconds, 0.1)) end
    local config = {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs"},
      network = {enabled = true}, rpc = {enabled = true},
      update = {enabled = true, root = "/system", components = name == "publisher" and {"Core"} or {"Autopilot"},
        actor = names[name], publishers = {publisher = options.expectedPublisherSubject or "Owner"}, peers = {"ShipA", "ShipB", "ShipOnline"},
        interval = 0.1, timeout = 20, collectTime = 1, quietTime = 0.5, maxCollectTime = 5, repairInterval = 0.5}}
    apps[name] = App.new(p, config); apps[name]:start()
  end
  f:drain()
  function f:run(seconds)
    for _ = 1, math.floor(seconds * 10 + 0.5) do self:advance(0.1) end
  end
  function f:close() for _, app in pairs(apps) do app:stop() end end
  return f, hosts, apps, manifest, files
end
return M
