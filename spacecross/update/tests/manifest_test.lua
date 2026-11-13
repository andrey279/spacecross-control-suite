local Release = require("spacecross.update.tests.stubs.release")
local Manifest = require("spacecross.update.manifest")
local Package = require("spacecross.update.package")
local P = require("tests.stubs.platform")
local codec = require("spacecross.core.codec")
local H = require("tests.support")
local function strict_manifest_selection_and_dependency_validation()
  local raw, value = Release.new()
  local m = assert(Manifest.decode(raw, string.rep("a", 40)))
  local selected, files = Manifest.select(m, {"Autopilot"})
  assert(#selected == 2 and selected[1] == "Autopilot" and #files == 2)
  assert(not Manifest.decode(raw, string.rep("b", 40)))
  value.components.Core.requires = {"Autopilot"}; assert(not Manifest.decode(codec.encode(value)))
  value.components.Core.requires = {}; value.components.Autopilot.requires = {"Unknown"}
  assert(not Manifest.decode(codec.encode(value)))
  value.components.Autopilot.requires = {}; value.files["../bad.lua"] = value.files["spacecross/app.lua"]
  assert(not Manifest.decode(codec.encode(value)))
  local malformed = {"return os.execute('bad')", "a2:s1:vts1:vf", "s9999999:x"}
  for _, data in ipairs(malformed) do assert(not Manifest.decode(data)) end
  return H.success()
end
local function package_profiles_hashes_reuse_and_removed_files()
  local p = P.new(); p.hash = Release.hash; p.reboots = 0
  p.reboot = function() p.reboots = p.reboots + 1 end
  local raw, _, files = Release.new()
  local package = Package.new(p, {root = "/system"})
  local plan = package:plan(raw, {"Autopilot"})
  local result = assert(package:install(plan, function(_, path) return files[path] end, true))
  assert(result.changed and p.reboots == 0 and #plan.generation <= 80)
  local current = Manifest.current(p.fs, "/system")
  assert(current.manifest and #current.selected == 2 and current.generation == result.generation)
  assert(package:plan(raw, {"Core", "Autopilot"}).same)
  local onlyCore = package:plan(raw, {"Core"})
  assert(#onlyCore.files == 1 and #onlyCore.missing == 0 and onlyCore.generation ~= result.generation)
  assert(package:install(onlyCore, function() error("unchanged file downloaded") end))
  assert(p.reboots == 1 and not p.files["/system/releases/" .. onlyCore.generation .. "/spacecross/autopilot/pilot.lua"])
  local nextRaw, nextValue, nextFiles = Release.new("b")
  nextValue.components.Autopilot.files = {}; nextValue.files["spacecross/autopilot/pilot.lua"] = nil
  local removed = package:plan(codec.encode(nextValue), {"Autopilot"})
  assert(package:install(removed, function(_, path) return nextFiles[path] end, true))
  assert(not p.files["/system/releases/" .. removed.generation .. "/spacecross/autopilot/pilot.lua"])
  return H.success()
end
local function bad_hash_syntax_and_metadata_write_never_publish()
  for _, mode in ipairs({"hash", "syntax", "metadata"}) do
    local p = P.new(); p.hash = Release.hash; p.fs.mkdir("/system"); p.files["/system/active"] = "old"
    local raw, value, files = Release.new()
    if mode == "syntax" then
      files["spacecross/app.lua"] = "this is invalid Lua"
      value.files["spacecross/app.lua"] = {size = #files["spacecross/app.lua"], sha256 = Manifest.digest(p.hash, files["spacecross/app.lua"])}
      raw = codec.encode(value)
    end
    local package = Package.new(p, {root = "/system"}); local plan = package:plan(raw, {"Core"})
    if mode == "metadata" then p.fail = function(operation, path) return operation == "write" and path:match("/PROFILE$") end end
    local ok = package:install(plan, function(_, path) return mode == "hash" and "forged" or files[path] end, true)
    assert(not ok and p.files["/system/active"] == "old")
  end
  return H.success()
end
local all_tests = {
  {test_name = "strict_manifest_selection_and_dependency_validation", test = strict_manifest_selection_and_dependency_validation},
  {test_name = "package_profiles_hashes_reuse_and_removed_files", test = package_profiles_hashes_reuse_and_removed_files},
  {test_name = "bad_hash_syntax_and_metadata_write_never_publish", test = bad_hash_syntax_and_metadata_write_never_publish},
}
return all_tests
