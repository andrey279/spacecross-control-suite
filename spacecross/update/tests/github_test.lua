local GitHub = require("spacecross.update.github")
local H = require("tests.support")
local function resolves_main_once_then_uses_immutable_urls()
  local calls, sha = {}, string.rep("a", 40)
  local source = GitHub.new(function(url)
    calls[#calls + 1] = url
    if url:find("git/ref/heads/main", 1, true) then return '{"object":{"sha":"' .. sha .. '"}}' end
    if url:match("/install.list$") then return "spacecross/app.lua\nspacecross/core/util.lua\n" end
    return "return {}"
  end, "owner/repo")
  local revision = assert(source.latest())
  local files = assert(source.files(revision))
  assert(#files == 2 and source.fetch(revision, files[1]) == "return {}")
  assert(calls[2]:find("/" .. sha .. "/install.list", 1, true))
  return H.truth(calls[3]:find("/" .. sha .. "/spacecross/app.lua", 1, true))
end
local function rejects_invalid_source_and_manifest()
  local source = GitHub.new(function() return "../escape.lua" end, "owner/repo")
  assert(not source.files(string.rep("a", 40)))
  assert(not source.fetch("main", "spacecross/app.lua"))
  assert(not source.fetch(string.rep("a", 40), "../escape.lua"))
  return H.truth(not source.latest())
end
local function manifest_is_bound_to_the_resolved_commit_release_asset()
  local seen, limit
  local source = GitHub.new(function(url, maximum) seen, limit = url, maximum; return "data-only manifest" end, "owner/repo")
  local sha = string.rep("b", 40)
  assert(source.manifest(sha) == "data-only manifest")
  assert(seen == "https://github.com/owner/repo/releases/download/spacecross-" .. sha .. "/components.sc" and limit == 131072)
  assert(not source.manifest("main"))
  return H.success()
end
local all_tests = {
  {test_name = "resolves_main_once_then_uses_immutable_urls", test = resolves_main_once_then_uses_immutable_urls},
  {test_name = "rejects_invalid_source_and_manifest", test = rejects_invalid_source_and_manifest},
  {test_name = "manifest_is_bound_to_the_resolved_commit_release_asset", test = manifest_is_bound_to_the_resolved_commit_release_asset},
}
return all_tests
