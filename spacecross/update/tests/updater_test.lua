local P = require("tests.stubs.platform")
local Updater = require("spacecross.update.updater")
local H = require("tests.support")
local function fixture()
  local p = P.new()
  p.fs.mkdir("/system"); p.files["/system/active"] = "old"
  p.source = {["spacecross/app.lua"] = "return {}", ["spacecross/util.lua"] = "return {n=1}"}
  p.fetch = function(_, path) return p.source[path] end
  p.reboots = 0; p.reboot = function() p.reboots = p.reboots + 1 end
  return p, Updater.new(p, {root = "/system"})
end
local function publishes_complete_generation_then_reboots()
  local p, updater = fixture()
  local result = assert(updater:install("new", {"spacecross/app.lua", "spacecross/util.lua"}))
  assert(result == "new" and p.reboots == 1)
  assert(p.files["/system/releases/new/READY"])
  return H.equal(p.files["/system/active"], "new")
end
local function syntax_and_download_failure_keep_old_release()
  for _, mode in ipairs({"syntax", "download", "rename", "write"}) do
    local p, updater = fixture()
    if mode == "syntax" then p.source["spacecross/util.lua"] = "this is not lua"
    elseif mode == "download" then p.source["spacecross/util.lua"] = nil
    else p.fail = function(operation, path)
      return operation == mode and (mode ~= "rename" or path == "/system/active")
    end end
    assert(not updater:install("new", {"spacecross/app.lua", "spacecross/util.lua"}), mode)
    assert(p.files["/system/active"] == "old" and p.reboots == 0, mode)
  end
  return H.success()
end
local function traversal_missing_entry_and_duplicate_rejected()
  for _, files in ipairs({{"../x.lua"}, {"spacecross/util.lua"}, {"spacecross/app.lua", "spacecross/app.lua"}}) do
    local p, updater = fixture()
    assert(not updater:install("new", files))
    assert(p.files["/system/active"] == "old")
  end
  return H.success()
end
local function source_is_pinned_and_live_generation_immutable()
  local p = fixture()
  local fetched = 0
  local deps = {fs = p.fs, fetch = p.fetch, reboot = p.reboot,
    latest = function() return "commit123" end, files = function(revision)
      assert(revision == "commit123"); return {"spacecross/app.lua"}
    end}
  deps.fetch = function(revision)
    assert(revision == "commit123"); fetched = fetched + 1; return "return {}"
  end
  local updater = Updater.new(deps, {root = "/system"})
  assert(updater:latest() == "commit123")
  return H.equal(fetched, 1)
end
local function immutable_committed_release()
  local p, updater = fixture()
  assert(updater:install("new", {"spacecross/app.lua"}))
  p.source["spacecross/app.lua"] = "return 'changed'"
  assert(not updater:install("new", {"spacecross/app.lua"}))
  return H.equal(p.files["/system/releases/new/spacecross/app.lua"], "return {}")
end
local function interrupted_publication_can_be_retried()
  local p, updater = fixture()
  p.fail = function(operation, path) return operation == "rename" and path == "/system/active" end
  assert(not updater:install("new", {"spacecross/app.lua"}))
  assert(p.files["/system/releases/new/READY"] and p.files["/system/active"] == "old")
  p.fail = nil
  assert(updater:install("new", {"spacecross/app.lua"}))
  return H.equal(p.files["/system/active"], "new")
end
local function every_write_failure_preserves_old_generation()
  local initial, updater = fixture()
  assert(updater:install("new", {"spacecross/app.lua", "spacecross/util.lua"}))
  local mutations = 0
  for _, operation in ipairs(initial.operations) do
    if operation[1] == "write" or operation[1] == "rename" then mutations = mutations + 1 end
  end
  for failAt = 1, mutations do
    local p, subject = fixture()
    local index = 0
    p.fail = function(operation)
      if operation == "write" or operation == "rename" then index = index + 1; return index == failAt end
    end
    assert(not subject:install("new", {"spacecross/app.lua", "spacecross/util.lua"}))
    assert(p.files["/system/active"] == "old" and p.reboots == 0)
    p.fail = nil
    assert(subject:install("new", {"spacecross/app.lua", "spacecross/util.lua"}))
  end
  return H.success()
end
local function independent_instances_share_a_filesystem_lease()
  local p, a = fixture()
  local b = Updater.new(p, {root = "/system"})
  local fetch = p.fetch
  p.fetch = function(revision, path)
    local value, err = b:install("racing", {"spacecross/app.lua"})
    assert(not value and err == "EBUSY")
    return fetch(revision, path)
  end
  assert(a:install("new", {"spacecross/app.lua"}))
  p.fetch = fetch
  assert(b:install("later", {"spacecross/app.lua"}))
  return H.equal(p.files["/system/active"], "later")
end
local function cancellation_before_pointer_rename_preserves_old_release()
  local p = fixture(); local stopped = false
  p.cancelled = function() return stopped end
  local write = p.fs.write
  p.fs.write = function(path, data)
    local ok, err = write(path, data)
    if path == "/system/active.new" then stopped = true end
    return ok, err
  end
  local updater = Updater.new(p, {root = "/system"})
  local value, err = updater:install("new", {"spacecross/app.lua"})
  assert(not value and err:find("UPDATE_CANCELLED") and p.files["/system/active"] == "old" and p.reboots == 0)
  stopped = false; p.fs.write = write
  assert(updater:install("new", {"spacecross/app.lua"}))
  return H.success()
end
local all_tests = {
  {test_name = "publishes_complete_generation_then_reboots", test = publishes_complete_generation_then_reboots},
  {test_name = "syntax_and_download_failure_keep_old_release", test = syntax_and_download_failure_keep_old_release},
  {test_name = "traversal_missing_entry_and_duplicate_rejected", test = traversal_missing_entry_and_duplicate_rejected},
  {test_name = "immutable_committed_release", test = immutable_committed_release},
  {test_name = "source_is_pinned_and_live_generation_immutable", test = source_is_pinned_and_live_generation_immutable},
  {test_name = "interrupted_publication_can_be_retried", test = interrupted_publication_can_be_retried},
  {test_name = "every_write_failure_preserves_old_generation", test = every_write_failure_preserves_old_generation},
  {test_name = "independent_instances_share_a_filesystem_lease", test = independent_instances_share_a_filesystem_lease},
  {test_name = "cancellation_before_pointer_rename_preserves_old_release", test = cancellation_before_pointer_rename_preserves_old_release},
}
return all_tests
