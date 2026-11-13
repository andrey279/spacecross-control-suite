local Fabric = require("spacecross.network.tests.stubs.fabric")
local Certificates = require("spacecross.rpc.tests.stubs.system")
local Fake = require("spacecross.rpc.tests.stubs.crypto")
local GPU = require("spacecross.ui.tests.stubs.gpu")
local App = require("spacecross.app")
local H = require("tests.support")
local function fixture()
  local f = Fabric.new()
  local p, apps = {}, {}
  for _, name in ipairs({"ui", "power-a", "power-b"}) do
    local platform = f:host(name); p[name] = platform
    f:card(platform, name, "modem")
    platform.wait = function(seconds) f:drain(); f:advance(math.min(seconds, 0.1)) end
    local subject = name == "ui" and "Owner" or name
    platform.rpc = {crypto = Fake.new(name .. "-key"), authorities = {root = "root"},
      certificate = Certificates.certificate(name .. "-key", subject, {name}, {"client", "server"}, {["*"] = {"*"}})}
    local config = {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs"},
      network = {enabled = true, discovery = {host_name = name}}, rpc = {enabled = true}}
    if name == "ui" then
      platform.components.gpu = GPU(); platform.components.gpu.type = "gpu"
      platform.components.gpu.width, platform.components.gpu.height = 60, 16
      platform.components.screen = {type = "screen", getKeyboards = function() return {"keyboard"} end}
      config.panels = {{id = "main", gpu = "gpu", screen = "screen", player = "Owner"}}
      platform.rpc.identities = {{certificate = Certificates.certificate("admin-key", "Admin", {"ui"}, {"client"}, {["*"] = {"*"}}), crypto = Fake.new("admin-key")}}
    else
      platform.stored = name == "power-a" and 25 or 75
      platform.components.buffer = {type = "energy_handler", getEnergyStored = function() return platform.stored end,
        getMaxEnergyStored = function() return 100 end}
      config.drivers, config.power = {"spacecross.hal.drivers.enderio_capacitor"}, {enabled = true, buffers = {"buffer"}, sources = {}}
    end
    apps[name] = App.new(platform, config); apps[name]:start()
  end
  f:drain()
  return f, p, apps
end
local function remote_views_authenticate_catalog_and_merge_fresh_controller_snapshots()
  local f, p, apps = fixture()
  local ui, a, b = apps.ui, apps["power-a"], apps["power-b"]
  assert(ui.remoteViews:open("main", "power-a", "power", "Owner"))
  assert(ui.remoteViews:open("main", "power-b", "power", "Owner"))
  local tab = ui.ui.panels.main.tabs.remote_power
  assert(#tab.endpoints == 2 and tab.state == nil and tab.snapshot == nil)
  assert(ui.rpc:peer("power-a").subject == "power-a")
  ui.ui:select("main", "hardware")
  local count = a.rpc.stats.executed
  p["power-a"].stored = 55; a.power:tick()
  assert(a.rpc.stats.executed == count) -- inactive view does not fetch business state
  ui.ui:select("main", "remote_power")
  assert(a.rpc.stats.executed > count and b.rpc.stats.executed > 0)
  local found = false
  for _, call in ipairs(p.ui.components.gpu.calls) do
    if call[1] == "set" and call[4]:find("55.0%%") then found = true end
  end
  assert(found)
  assert(ui.remoteViews:open("main", "power-a", "power", "Owner"))
  assert(#ui.ui.panels.main.tabs.remote_power.endpoints == 1)
  for _, app in pairs(apps) do app:stop() end
  f:drain()
  return H.success()
end
local function certificate_subject_cannot_be_replaced_by_payload_player()
  local f, _, apps = fixture()
  local changed = 0
  apps["power-a"].model:register("settings", {snapshot = function() return {} end,
    command = function() changed = changed + 1; return true end})
  local result, err = apps.ui.rpc:request("power-a", "settings", "configure", "Admin", {player = "Owner"})
  assert(result == nil and err == "EACCES" and changed == 0)
  assert(apps.ui.rpc:request("power-a", "settings", "configure", "Owner", {}))
  assert(changed == 1)
  for _, app in pairs(apps) do app:stop() end
  f:drain()
  return H.success()
end
local all_tests = {
  {test_name = "remote_views_authenticate_catalog_and_merge_fresh_controller_snapshots", test = remote_views_authenticate_catalog_and_merge_fresh_controller_snapshots},
  {test_name = "certificate_subject_cannot_be_replaced_by_payload_player", test = certificate_subject_cannot_be_replaced_by_payload_player},
}
return all_tests
