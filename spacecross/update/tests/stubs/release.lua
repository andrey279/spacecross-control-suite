local Fake = require("spacecross.rpc.tests.stubs.crypto")
local Manifest = require("spacecross.update.manifest")
local codec = require("spacecross.core.codec")
local M = {hash = Fake.new("release-hash").sha256}
function M.new(revision, files, components)
  files = files or {["spacecross/app.lua"] = "return {}", ["spacecross/autopilot/pilot.lua"] = "return {pilot=true}"}
  local metadata = {}
  for path, data in pairs(files) do metadata[path] = {size = #data, sha256 = Manifest.digest(M.hash, data)} end
  local value = {v = 1, revision = string.rep(revision or "a", 40), files = metadata,
    components = components or {Core = {version = string.rep("a", 40), files = {"spacecross/app.lua"}, requires = {}},
      Autopilot = {version = string.rep(revision or "a", 40), files = {"spacecross/autopilot/pilot.lua"}, requires = {"Core"}}}}
  return codec.encode(value), value, files
end
return M
