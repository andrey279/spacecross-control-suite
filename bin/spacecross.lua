-- Run from the project root: lua bin/spacecross.lua /etc/spacecross.lua
local arguments = rawget(_G, "arg") or {...}
local script = arguments[0] or require("process").info().path
local root = (script:match("^(.*)/bin/[^/]+$") or ".")
package.path = root .. "/?.lua;" .. package.path
local config = assert(loadfile(arguments[1] or "/etc/spacecross.lua"))()
local deps = require("spacecross.runtime.openos").new(config)
local app = require("spacecross.app").new(deps, config)
local ok, err = xpcall(function()
  app:start()
  while true do if deps.event.pull(1) == "interrupted" then break end end
end, debug.traceback)
app:stop()
if not ok then error(err, 0) end
