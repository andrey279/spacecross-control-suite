-- Usage: lua bin/remote.lua HOST OWNER [/etc/spacecross-client.lua]
local arguments = rawget(_G, "arg") or {...}
local script = arguments[0] or require("process").info().path
package.path = (script:match("^(.*)/bin/[^/]+$") or ".") .. "/?.lua;" .. package.path
local host, actor = assert(arguments[1], "HOST required"), assert(arguments[2], "OWNER required")
local config = assert(loadfile(arguments[3] or "/etc/spacecross-client.lua"))()
-- The client starts only transport and RPC; it does not start ship controllers.
local deps = require("spacecross.runtime.openos").new({network = config.network, rpc = config.rpc})
local network = require("spacecross.network.transport").new(deps, config.network)
local trust = require("spacecross.security.certificates").new(deps.rpc.crypto, {authorities = deps.rpc.authorities, revoked = config.rpc.revoked})
local rpcConfig = require("spacecross.core.util").copy(config.rpc)
rpcConfig.certificate = deps.rpc.certificate
local rpc = require("spacecross.rpc.service").new({network = network, event = deps.event, clock = deps.clock,
  crypto = deps.rpc.crypto, trust = trust, wait = deps.wait, dispatch = function() return nil, "ENOTSUP" end}, rpcConfig)
for _, identity in ipairs(deps.rpc.identities) do assert(rpc:addIdentity(identity.certificate, identity.crypto)) end
local gpu = assert(require("term").gpu(), "client GPU required")
local renderer = require("spacecross.terminal.renderer").new(gpu, require("unicode").wlen)
local saved = renderer:capture()
local client = require("spacecross.terminal.client").new({rpc = rpc, renderer = renderer, widthOf = require("unicode").wlen}, {host = host, actor = actor})
local filter = require("spacecross.terminal.input").new(actor, gpu.getScreen(), deps.component.proxy(gpu.getScreen()).getKeyboards())
local queue, queuedBytes, detached, inputError = {}, 0, false, nil
local function input(...)
  local e, action = filter({...})
  if action == "detach" then detached = true; return end
  if e then
    queuedBytes = queuedBytes + #(e.text or "") + 64
    if #queue >= 256 or queuedBytes > 32768 then inputError = "LOCAL_INPUT_FULL"; detached = true; return end
    queue[#queue + 1] = e
  end
end
local names = {"key_down", "key_up", "clipboard", "touch", "drag", "drop", "scroll"}
local ok, err = xpcall(function()
  network:start(); rpc:start()
  local w, h = gpu.getResolution()
  assert(client:open(w, h))
  for _, name in ipairs(names) do deps.event.listen(name, input) end
  while not detached do
    if #queue > 0 then
      local batch = {}
      for _ = 1, math.min(32, #queue) do
        local e = table.remove(queue, 1); queuedBytes = queuedBytes - #(e.text or "") - 64; batch[#batch + 1] = e
      end
      assert(client:input(batch)) -- An unknown outcome ends the session, never duplicates input.
    end
    local refreshed, frameErr = client:refresh()
    assert(refreshed or frameErr == "EAGAIN", frameErr)
    if client.status == "exited" or client.status == "failed" then break end
    deps.event.pull(0.2)
  end
  if inputError then error(inputError, 0) end
end, debug.traceback)
for _, name in ipairs(names) do deps.event.ignore(name, input) end
pcall(client.close, client); rpc:stop(); network:stop()
local restored, restoreErr = renderer:restore(saved)
if not restored then error(restoreErr, 0) end
if not ok then error(err, 0) end
