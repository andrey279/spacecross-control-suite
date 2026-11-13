-- Stable OpenOS entrypoint outside the replaceable release tree.
local fs = require("filesystem")
local root = "/var/lib/spacecross/system"
local f = assert(io.open(root .. "/active", "r"))
local revision = f:read("*a"); f:close()
assert(revision and revision:match("^[%w%-_]+$") and #revision <= 80, "invalid active generation")
local release = root .. "/releases/" .. revision
assert(fs.exists(release .. "/READY"), "incomplete generation")
package.path = release .. "/?.lua;" .. package.path
local config = assert(loadfile("/etc/spacecross.lua"))()
local deps = require("spacecross.runtime.openos").new(config)
local app = require("spacecross.app").new(deps, config)
local ok, err = xpcall(function()
  app:start()
  while deps.event.pull(1) ~= "interrupted" do end
end, debug.traceback)
app:stop()
if not ok then error(err, 0) end
