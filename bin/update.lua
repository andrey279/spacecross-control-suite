local arguments = rawget(_G, "arg") or {...}
local script = arguments[0] or require("process").info().path
local root = (script:match("^(.*)/bin/[^/]+$") or ".")
package.path = root .. "/?.lua;" .. package.path
local config = assert(loadfile(arguments[1] or "/etc/spacecross.lua"))()
local deps = require("spacecross.runtime.openos").new(config)
local source = require("spacecross.update.github").new(deps.request, config.update.repository)
if config.update.versioned then
  assert(deps.hash, "UPDATE_SHA256_REQUIRED: configure update.hashAddress or RPC crypto")
  local package = require("spacecross.update.package").new(deps, config.update)
  local result, err = package:latest(source, config.update.components)
  assert(result, err)
  print((result.changed and "Installed " or "Already current: ") .. result.generation)
  return
end
local updater = require("spacecross.update.updater").new({fs = deps.fs, fetch = source.fetch,
  latest = source.latest, files = source.files, reboot = deps.reboot}, config.update)
local revision, err = updater:latest()
assert(revision, err)
print("Installed " .. revision)
