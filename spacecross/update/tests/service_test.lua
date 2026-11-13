local Cluster = require("spacecross.update.tests.stubs.cluster")
local Net = require("spacecross.network.protocol")
local codec = require("spacecross.core.codec")
local Manifest = require("spacecross.update.manifest")
local H = require("tests.support")
local function transfers(f)
  local out = {}
  for _, packet in ipairs(f.sent) do
    if packet.source == "publisher" then
      local network = assert(Net.decode(packet.wire, 8192, 256))
      if network.service == "update" then
        local body = assert(codec.decode(network.body))
        if body.kind == "file" then
          local key = body.path .. ":" .. body.round .. ":" .. body.offset
          out[key] = (out[key] or 0) + 1
        end
      end
    end
  end
  return out
end
local function shared_components_are_broadcast_once_and_internet_clients_download()
  local f, hosts, apps, manifest, files = Cluster.new()
  assert(apps.publisher.model:request("update", "check", "Admin", {player = "Owner"}) == nil)
  assert(hosts.publisher.files["/system/active"] == "old")
  assert(apps.publisher.model:request("update", "check", "Owner", {}))
  f:run(8)
  for name, p in pairs(hosts) do
    assert(apps[name].update:snapshot().phase == "complete", name .. ": " .. tostring(apps[name].update:snapshot().error))
    local installed = Manifest.current(p.fs, "/system")
    assert(installed.manifest.revision == manifest.revision and p.reboots == 1)
    if name == "publisher" then assert(#installed.selected == 1)
    else assert(#installed.selected == 2 and p.files[installed.directory .. "/spacecross/autopilot/pilot.lua"] == files["spacecross/autopilot/pilot.lua"]) end
  end
  assert(hosts.publisher.downloads["spacecross/app.lua"] == 1 and hosts.publisher.downloads["spacecross/autopilot/pilot.lua"] == 1)
  assert(hosts.online.downloads["spacecross/autopilot/pilot.lua"] == 1 and not next(hosts.a.downloads) and not next(hosts.b.downloads))
  for _, count in pairs(transfers(f)) do assert(count == 1, "duplicate broadcast for shared file chunk") end
  assert(apps.publisher.update.state.filesSent == 2)
  f:close(); return H.success()
end
local function tampered_file_cannot_activate_and_repair_is_shared()
  local f, hosts, apps, _, files = Cluster.new()
  local original, altered = f.deliver, false
  f.deliver = function(self, packet)
    if packet.source == "publisher" then
      local net = assert(Net.decode(packet.wire, 8192, 256))
      if net.service == "update" then
        local body = assert(codec.decode(net.body))
        if body.kind == "file" and body.path:find("pilot", 1, true) and body.round == 0 and body.offset == 1 then
          assert(hosts.a.files["/system/active"] == "old" and hosts.b.files["/system/active"] == "old")
          body.data = "!" .. body.data:sub(2); net.body = codec.encode(body)
          local copy = {}; for k, v in pairs(packet) do copy[k] = v end
          copy.wire = Net.encode(net); altered = true
          return original(self, copy)
        end
      end
    end
    return original(self, packet)
  end
  assert(apps.publisher.update:trigger("Owner")); f:run(10)
  assert(altered)
  for _, name in ipairs({"a", "b"}) do
    local installed = Manifest.current(hosts[name].fs, "/system")
    assert(installed.manifest and hosts[name].files[installed.directory .. "/spacecross/autopilot/pilot.lua"] == files["spacecross/autopilot/pilot.lua"])
    assert(hosts[name].reboots == 1)
  end
  local repairChunks = 0
  for key, count in pairs(transfers(f)) do
    assert(count == 1)
    if key:find("pilot.lua:1:", 1, true) then repairChunks = repairChunks + 1 end
  end
  assert(repairChunks == math.ceil(#files["spacecross/autopilot/pilot.lua"] / 4096))
  f:close(); return H.success()
end
local function internet_corruption_and_untrusted_offers_keep_old_generation()
  local f, hosts, apps = Cluster.new()
  local original = hosts.online.updateSource.fetch
  hosts.online.updateSource.fetch = function(revision, path)
    if path:find("pilot", 1, true) then return "forged source" end
    return original(revision, path)
  end
  hosts.a.event.push("spacecross_network_message", "a", "attacker", "*", 27016, "update",
    codec.encode({v = 1, kind = "offer", session = string.rep("e", 64)}))
  hosts.a:pump(); assert(not apps.a.update.client)
  assert(apps.publisher.update:trigger("Owner")); f:run(8)
  assert(hosts.online.files["/system/active"] == "old" and hosts.online.reboots == 0)
  assert(apps.online.update.state.phase == "failed")
  assert(hosts.a.reboots == 1 and hosts.b.reboots == 1)
  f:close(); return H.success()
end
local function valid_ca_but_wrong_publisher_subject_never_installs()
  local f, hosts, apps = Cluster.new({publisherSubject = "Admin"})
  assert(apps.publisher.update:trigger("Owner")); f:run(5)
  for _, name in ipairs({"a", "b", "online"}) do
    assert(hosts[name].files["/system/active"] == "old" and hosts[name].reboots == 0)
    assert(apps[name].update.state.error:find("UPDATE_PUBLISHER_IDENTITY"))
  end
  f:close(); return H.success()
end
local function stop_during_fetch_cannot_publish_late_and_releases_lease()
  local f, hosts, apps = Cluster.new()
  local fetch = hosts.publisher.updateSource.fetch
  hosts.publisher.updateSource.fetch = function(revision, path)
    apps.publisher.update:stop()
    apps.publisher.update:start() -- a new lifecycle must not revive the suspended old install
    return fetch(revision, path)
  end
  assert(apps.publisher.update:trigger("Owner")); f:run(1)
  assert(hosts.publisher.files["/system/active"] == "old" and hosts.publisher.reboots == 0)
  hosts.publisher.updateSource.fetch = fetch
  assert(apps.publisher.update:trigger("Owner")); f:run(8)
  assert(hosts.publisher.reboots == 1 and hosts.a.reboots == 1)
  f:close(); return H.success()
end
local function publisher_holds_install_lease_until_distribution_finishes()
  local f, hosts, apps = Cluster.new()
  assert(apps.publisher.update:trigger("Owner")); f:run(0.2)
  assert(apps.publisher.update.pub and apps.publisher.update.lease)
  local other = require("spacecross.update.updater").new({fs = hosts.publisher.fs, fetch = function() return "return {}" end}, {root = "/system"})
  local value, err = other:install("concurrent", {"spacecross/app.lua"})
  assert(not value and err == "EBUSY")
  f:run(8); assert(apps.publisher.update.state.phase == "complete")
  assert(other:install("afterwards", {"spacecross/app.lua"}))
  f:close(); return H.success()
end
local function replayed_completed_offer_cannot_reinstall_without_a_fresh_session()
  local f, hosts, apps = Cluster.new()
  assert(apps.publisher.update:trigger("Owner")); f:run(8)
  local generation = hosts.a.files["/system/active"]
  local captured
  for _, packet in ipairs(f.sent) do
    local outer = assert(Net.decode(packet.wire, 8192, 256))
    if packet.source == "publisher" and outer.service == "update" then
      local body = assert(codec.decode(outer.body))
      if body.kind == "offer" then captured = packet; break end
    end
  end
  assert(captured); f:run(35) -- expire transport's ordinary duplicate cache
  f:deliver(captured); f:drain(); f:run(2)
  assert(hosts.a.files["/system/active"] == generation and hosts.a.reboots == 1)
  assert(apps.a.update.state.phase == "failed" and apps.a.update.state.error:find("ENOENT_UPDATE"))
  f:close(); return H.success()
end
local function publisher_capability_is_separate_from_player_owner_role()
  local f, hosts, apps = Cluster.new({publisherSubject = "UpdatePublisher", expectedPublisherSubject = "UpdatePublisher", publisherGrants = {_update = {"publish"}}})
  assert(apps.publisher.update:trigger("Owner")); f:run(8)
  for _, p in pairs(hosts) do assert(p.reboots == 1 and p.files["/system/active"] ~= "old") end
  f:close(); return H.success()
end
local function matching_subject_without_publish_grant_cannot_update_clients()
  local f, hosts, apps = Cluster.new({publisherSubject = "UpdatePublisher", expectedPublisherSubject = "UpdatePublisher", publisherGrants = {_update = {"describe"}}})
  assert(apps.publisher.update:trigger("Owner")); f:run(5)
  for _, name in ipairs({"a", "b", "online"}) do
    assert(hosts[name].files["/system/active"] == "old" and hosts[name].reboots == 0)
    assert(apps[name].update.state.error:find("UPDATE_PUBLISHER_IDENTITY"))
  end
  f:close(); return H.success()
end
local all_tests = {
  {test_name = "shared_components_are_broadcast_once_and_internet_clients_download", test = shared_components_are_broadcast_once_and_internet_clients_download},
  {test_name = "tampered_file_cannot_activate_and_repair_is_shared", test = tampered_file_cannot_activate_and_repair_is_shared},
  {test_name = "internet_corruption_and_untrusted_offers_keep_old_generation", test = internet_corruption_and_untrusted_offers_keep_old_generation},
  {test_name = "valid_ca_but_wrong_publisher_subject_never_installs", test = valid_ca_but_wrong_publisher_subject_never_installs},
  {test_name = "stop_during_fetch_cannot_publish_late_and_releases_lease", test = stop_during_fetch_cannot_publish_late_and_releases_lease},
  {test_name = "publisher_holds_install_lease_until_distribution_finishes", test = publisher_holds_install_lease_until_distribution_finishes},
  {test_name = "replayed_completed_offer_cannot_reinstall_without_a_fresh_session", test = replayed_completed_offer_cannot_reinstall_without_a_fresh_session},
  {test_name = "publisher_capability_is_separate_from_player_owner_role", test = publisher_capability_is_separate_from_player_owner_role},
  {test_name = "matching_subject_without_publish_grant_cannot_update_clients", test = matching_subject_without_publish_grant_cannot_update_clients},
}
return all_tests
