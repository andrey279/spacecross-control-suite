local M = {}
function M.new(config)
  local component, event, computer = require("component"), require("event"), require("computer")
  local deps = {component = component, event = event, clock = computer.uptime, nodeId = computer.address(),
    fs = require("spacecross.core.fs").new(require("filesystem")),
    reboot = function() computer.shutdown(true) end}
  -- Lazy: systems with no internet card can still run local services.
  function deps.request(url, maxBytes)
    local handle
    local ok, result = pcall(function()
      handle = require("internet").request(url, nil, {["User-Agent"] = "SpaceCross"})
      local chunks, size = {}, 0
      for chunk in handle do
        size = size + #chunk
        assert(size <= (maxBytes or 1024 * 1024), "HTTP_RESPONSE_TOO_LARGE")
        chunks[#chunks + 1] = chunk
      end
      local response = getmetatable(handle).__index
      local status = response.response()
      assert(status and status >= 200 and status < 300, "HTTP_STATUS_" .. tostring(status))
      return table.concat(chunks)
    end)
    if handle then
      local mt = getmetatable(handle)
      if mt and mt.__index and mt.__index.close then pcall(mt.__index.close) end
    end
    if not ok then return nil, tostring(result) end
    return result
  end
  if config.crypto and config.crypto.module then
    deps.crypto = require(config.crypto.module).new(deps, config.crypto)
  end
  if config.autopilot and config.autopilot.enabled or config.update and (config.update.enabled or config.update.versioned) then
    deps.processes = require("spacecross.runtime.processes").new(require("process"))
  end
  if config.network and config.network.enabled then
    deps.randomId = function() return require("uuid").next() end
  end
  deps.wait = function(timeout) return event.pull(timeout) end
  if config.rpc and config.rpc.enabled then
    local settings = config.rpc
    assert(settings.crypto and settings.crypto.module, "explicit RPC crypto provider required")
    local provider = require(settings.crypto.module)
    deps.rpc = {crypto = provider.new(deps, settings.crypto), certificate = assert(deps.fs.read(assert(settings.certificateFile))), authorities = {}, identities = {}}
    for issuer, path in pairs(settings.authorities or {}) do deps.rpc.authorities[issuer] = assert(deps.fs.read(path)) end
    for _, identity in ipairs(settings.identities or {}) do
      assert(identity.crypto and identity.crypto.module, "explicit identity crypto provider required")
      deps.rpc.identities[#deps.rpc.identities + 1] = {certificate = assert(deps.fs.read(assert(identity.certificateFile))),
        crypto = require(identity.crypto.module).new(deps, identity.crypto)}
    end
  end
  if config.cnc and config.cnc.enabled then
    deps.cncPeerCertificate = assert(deps.fs.read(assert(config.cnc.peerCertificateFile)))
  end
  if config.update then
    if deps.rpc then deps.hash = deps.rpc.crypto.sha256 end
    if not deps.hash and config.update.hashAddress then
      local card = assert(component.proxy(config.update.hashAddress))
      deps.hash = assert(card.sha256, "SHA256 component required")
    end
    deps.hasInternet = function()
      for address in component.list("internet") do
        local ok, available = pcall(function() return component.proxy(address).isHttpEnabled() end)
        if ok and available then return true end
      end
      return false
    end
    if config.update.enabled or config.update.versioned then
      deps.updateSource = require("spacecross.update.github").new(deps.request, config.update.repository)
    end
  end
  if config.terminal and config.terminal.enabled then
    deps.terminalRunner = require("spacecross.terminal.openos_runner").new()
    deps.widthOf = require("unicode").wlen
  end
  return deps
end
return M
