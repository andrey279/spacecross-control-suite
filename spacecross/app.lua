local M = {}
function M.new(deps, config)
  local cnc, cncChannel
  local loggerDeps = {}; for key, value in pairs(deps) do loggerDeps[key] = value end
  if config.cnc and config.cnc.enabled then
    loggerDeps.upload = function(name, data) if cnc then return cnc:upload(name, data) end end
  end
  local logger = require("spacecross.logging.logger").new(loggerDeps, config.logging)
  local function log(level, code, fields) return logger:write(level, code, fields) end
  local serviceDeps = {event = deps.event, component = deps.component, clock = deps.clock, log = log, randomId = deps.randomId}
  local bus = require("spacecross.bus.local_bus").new(serviceDeps)
  local definitions = {}
  for _, entry in ipairs(config.drivers or {}) do
    local definition = require(type(entry) == "string" and entry or entry.module)
    if type(entry) == "table" and entry.options then definition = assert(definition.configure, "driver is not configurable")(entry.options) end
    definitions[#definitions + 1] = definition
  end
  local hal = require("spacecross.hal.hal").new(serviceDeps, definitions)
  local access = require("spacecross.defense.access").new(config)
  local function authorize(player, action) return access:authorize(player, action) end
  local model = require("spacecross.ui.model").new(authorize)
  model:register("hardware", {snapshot = function()
    local instances = {}
    for _, instance in ipairs(hal.registry:list()) do
      instances[#instances + 1] = {address = instance.address, kind = instance.kind}
    end
    return {count = #instances, instances = instances}
  end})
  local watcher, defense, shields, turrets, satellite
  if config.watcher and config.watcher.enabled then
    watcher = require("spacecross.entity.watcher").new({hal = hal, event = deps.event,
      clock = deps.clock, bus = bus, log = log}, config.watcher)
    model:register("entities", {snapshot = function() return watcher:snapshot() end})
  end
  if config.defense and config.defense.enabled then
    assert(watcher, "defense requires an enabled watcher")
    local defenseConfig = require("spacecross.core.util").copy(config.defense)
    defenseConfig.owners, defenseConfig.admins = config.owners, config.admins
    local actuator = require("spacecross.defense.destruct").new({hal = hal, log = log}, config.defense.channels)
    defense = require("spacecross.defense.controller").new({watcher = watcher, actuator = actuator,
      clock = deps.clock, event = deps.event, log = log, verifyHeartbeat = function(proof)
        if config.cnc and config.cnc.enabled then return cnc and cnc:verifyHeartbeat(proof) or false end
        return deps.verifyHeartbeat and deps.verifyHeartbeat(proof) or false
      end}, defenseConfig)
    model:register("defense", {snapshot = function() return defense:snapshot() end,
      command = function(_, action, _, player)
        if action == "arm" then return defense:setArmed(player, true) end
        if action == "disarm" then return defense:setArmed(player, false) end
        return nil, "ENOTSUP"
      end})
  end
  if config.shields and config.shields.enabled then
    shields = require("spacecross.shields.model").new(hal, function(player) return access:role(player) == "owner" end)
    model:register("shields", shields)
  end
  if config.turrets and config.turrets.enabled then
    turrets = require("spacecross.turrets.model").new(hal, function(player) return access:role(player) == "owner" end)
    model:register("turrets", turrets)
  end
  if config.satellite and config.satellite.enabled then
    local satelliteConfig = require("spacecross.core.util").copy(config.satellite)
    local satelliteHardware
    if satelliteConfig.hardware then
      satelliteHardware = require("spacecross.satellite.adapters").new({component = deps.component}, satelliteConfig.hardware)
    end
    local satelliteCrypto = deps.satelliteCrypto
    if not satelliteCrypto and satelliteConfig.cacheKeyFile then
      satelliteCrypto = require("spacecross.security.local_cache").new({component = deps.component, fs = deps.fs},
        {address = assert(satelliteConfig.cacheCard, "satellite cache Data Card address required"),
          keyFile = satelliteConfig.cacheKeyFile})
    end
    local function hardwareMethod(injected, method)
      if injected then return injected end
      if satelliteHardware then return function(...) return satelliteHardware[method](satelliteHardware, ...) end end
    end
    satellite = require("spacecross.satellite.controller").new({
      event = deps.event, clock = deps.clock, fs = deps.fs, codec = require("spacecross.core.codec"),
      crypto = satelliteCrypto,
      sendHeartbeat = function(status)
        if cnc then return cnc:updateSatelliteStatus(status) end
        if deps.satelliteHeartbeat then return deps.satelliteHeartbeat(status) end
        return nil, "CNC_UNAVAILABLE"
      end,
      beginWhitelist = function()
        if cnc then return cnc:beginSatelliteWhitelist() end
        if deps.satelliteBeginWhitelist then return deps.satelliteBeginWhitelist() end
        return nil, "CNC_UNAVAILABLE"
      end,
      pollWhitelist = function(id)
        if cnc then return cnc:pollSatelliteWhitelist(id) end
        if deps.satellitePollWhitelist then return deps.satellitePollWhitelist(id) end
        return nil, "CNC_UNAVAILABLE"
      end,
      fetchWhitelist = deps.satelliteFetchWhitelist,
      sendAttackAlert = function(alert)
        if cnc then return cnc:sendSatelliteAlert(alert) end
        if deps.satelliteAttackAlert then return deps.satelliteAttackAlert(alert) end
        return nil, "CNC_UNAVAILABLE"
      end,
      scan = hardwareMethod(deps.satelliteScan, "scan"),
      position = hardwareMethod(deps.satellitePosition, "position"),
      jumpToTarget = hardwareMethod(deps.satelliteJumpToTarget, "jump"),
      activateAuxiliaryCharges = hardwareMethod(deps.satelliteAuxiliaryCharges, "auxiliary"),
      detonateCentralCharge = hardwareMethod(deps.satelliteDetonateCentral, "central"), log = log,
    }, satelliteConfig)
    model:register("satellite", require("spacecross.satellite.model").new(satellite,
      function(player) return access:role(player) == "owner" end))
  end
  local coreDaemon, autopilot, power, structures
  if config.autopilot and config.autopilot.enabled or config.coreDaemon and config.coreDaemon.enabled then
    coreDaemon = require("spacecross.autopilot.core_daemon").new({hal = hal, event = deps.event, log = log}, config.coreDaemon)
  end
  if config.autopilot and config.autopilot.enabled then
    autopilot = require("spacecross.autopilot.autopilot_core").new({hal = hal, event = deps.event,
      clock = deps.clock, fs = deps.fs, processes = assert(deps.processes, "process adapter required"),
      bus = bus, log = log, coreDaemon = coreDaemon}, config.autopilot)
    model:register("autopilot", require("spacecross.autopilot.model")(autopilot, config.autopilot))
  end
  if config.structures and config.structures.enabled then
    assert(autopilot, "structure deployment requires an enabled autopilot")
    local structureAdapters
    if config.structures.hardware then
      structureAdapters = require("spacecross.structures.adapters").new({component = deps.component}, config.structures.hardware)
    end
    structures = require("spacecross.structures.deployer").new({autopilot = autopilot, clock = deps.clock,
      event = deps.event, fs = deps.fs, log = log,
      deploy = structureAdapters and function(...) return structureAdapters:deploy(...) end
        or assert(deps.structureDeploy, "structure deployment adapter required"),
      provisionComputer = structureAdapters and function(...) return structureAdapters:provision(...) end
        or assert(deps.structureProvision, "structure computer adapter required"),
      confirm = structureAdapters and function(...) return structureAdapters:confirm(...) end
        or assert(deps.structureConfirm, "structure confirmation adapter required")}, config.structures)
    model:register("structures", require("spacecross.structures.model").new(structures,
      function(player) return access:role(player) == "owner" end))
  end
  if config.power and config.power.enabled then
    local powerConfig = require("spacecross.core.util").copy(config.power)
    powerConfig.owners = config.owners
    power = require("spacecross.power.controller").new({hal = hal, event = deps.event, clock = deps.clock,
      watcher = watcher, bus = bus, log = log}, powerConfig)
    model:register("power", {snapshot = function() return power:snapshot() end})
  end
  local terminal
  if config.terminal and config.terminal.enabled then
    assert(config.rpc and config.rpc.enabled and deps.rpc and deps.terminalRunner, "terminal requires authenticated RPC and an OpenOS runner")
    terminal = require("spacecross.terminal.service").new({clock = deps.clock, event = deps.event,
      runner = deps.terminalRunner, widthOf = deps.widthOf, log = log,
      isOwner = function(player) return access:role(player) == "owner" end,
      id = function()
        return (deps.rpc.crypto.random(24):gsub(".", function(c) return string.format("%02x", c:byte()) end))
      end}, config.terminal)
    model:register("terminal", {snapshot = function() return {available = true, ownerOnly = true} end,
      command = function(_, action, args, player) return terminal:request(action, player, args) end})
  end
  local network, discovery, networkBridge, rpc, remoteViews, rpcTrust, updateService
  if config.network and config.network.enabled then
    network = require("spacecross.network.transport").new(serviceDeps, config.network)
    local discoveryConfig = require("spacecross.core.util").copy(config.network.discovery or {})
    if not discoveryConfig.type then
      discoveryConfig.type = model:list()
      discoveryConfig.type[#discoveryConfig.type + 1] = "network"
      if config.update and config.update.enabled then discoveryConfig.type[#discoveryConfig.type + 1] = "update" end
    end
    discovery = require("spacecross.network.discovery").new({network = network, event = deps.event, clock = deps.clock}, discoveryConfig)
    model:register("network", {snapshot = function()
      return {cards = network:listCards(), hosts = discovery:list(), stats = require("spacecross.core.util").copy(network.stats),
        selections = remoteViews and remoteViews:list() or {}, rpcStats = rpc and require("spacecross.core.util").copy(rpc.stats),
        rpcError = rpc and rpc.lastError}
    end, command = function(_, action, args, player)
      if action == "openRemote" and remoteViews then return remoteViews:open(args.panel, args.host, args.model, player) end
      return nil, "ENOTSUP"
    end})
    if config.network.bus and config.network.bus.enabled then
      networkBridge = require("spacecross.bus.network_bridge").new({network = network, bus = bus,
        event = deps.event, clock = deps.clock, log = log}, config.network.bus)
    end
  end
  if config.rpc and config.rpc.enabled then
    assert((network or config.cnc and config.cnc.enabled) and deps.rpc, "RPC requires network/CnC and an explicit crypto identity")
    rpcTrust = require("spacecross.security.certificates").new(deps.rpc.crypto, {authorities = deps.rpc.authorities, revoked = config.rpc.revoked})
    local rpcNetwork = network
    if config.cnc and config.cnc.enabled then
      assert((config.rpc.port or 27016) == 27016, "CnC uses the common RPC logical port 27016")
      local settings = require("spacecross.core.util").copy(config.cnc)
      settings.peerCertificate = assert(deps.cncPeerCertificate, "CnC peer certificate required")
      assert(rpcTrust:verify(settings.peerCertificate, "server", settings.peer))
      cncChannel = require("spacecross.cnc.channel").new({network = network, event = deps.event,
        clock = deps.clock, component = deps.component, log = log}, settings)
      rpcNetwork = cncChannel
    end
    local rpcConfig = require("spacecross.core.util").copy(config.rpc)
    rpcConfig.certificate = deps.rpc.certificate
    rpc = require("spacecross.rpc.service").new({network = rpcNetwork, event = deps.event, clock = deps.clock,
      crypto = deps.rpc.crypto, trust = rpcTrust, wait = deps.wait, log = log,
      dispatch = function(name, action, player, args, context)
        if name == "_system" and action == "models" then return model:catalog(player) end
        if name == "_update" and updateService then return updateService:rpc(action, player, args, context) end
        return model:request(name, action, player, args)
      end}, rpcConfig)
    for _, identity in ipairs(deps.rpc.identities or {}) do assert(rpc:addIdentity(identity.certificate, identity.crypto)) end
    if cncChannel then
      cnc = require("spacecross.cnc.agent").new({rpc = rpc, channel = cncChannel, clock = deps.clock,
        event = deps.event, crypto = deps.rpc.crypto,
        heartbeat = function(proof) if defense then return defense:heartbeat(proof) end end}, config.cnc)
    end
  end
  assert(not (config.cnc and config.cnc.enabled) or cnc, "CnC requires enabled RPC")
  if config.update and config.update.enabled then
    assert(network and rpc and deps.hash and deps.hasInternet, "LAN update requires network, RPC, SHA256 and internet capability adapter")
    assert((config.rpc.port or 27016) == 27016, "LAN update shares logical RPC port 27016")
    local settings = require("spacecross.core.util").copy(config.update)
    settings.actor = settings.actor or assert(rpcTrust:verify(deps.rpc.certificate)).subject
    local peers = require("spacecross.core.util").set(settings.peers)
    updateService = require("spacecross.update.service").new({network = network, rpc = rpc, fs = deps.fs, processes = deps.processes,
      event = deps.event, clock = deps.clock, hash = deps.hash, source = deps.updateSource,
      hasInternet = deps.hasInternet, reboot = deps.reboot, log = log,
      id = function() return require("spacecross.rpc.protocol").hex(deps.rpc.crypto.random(32)) end,
      isOwner = function(actor) return access:role(actor) == "owner" end,
      isPeer = function(actor) return peers[actor] == true end}, settings)
    model:register("update", {snapshot = function() return updateService:snapshot() end,
      command = function(_, action, _, actor) if action == "check" then return updateService:trigger(actor) end; return nil, "ENOTSUP" end})
  end
  local ui = require("spacecross.ui.framework").new({
    authorize = authorize,
    request = function(endpoint, action, player, args)
      if endpoint.host ~= "localhost" then
        if not rpc then return nil, "RPC_UNAVAILABLE" end
        return rpc:request(endpoint.host, endpoint.model, action, player, args, endpoint.card)
      end
      return model:request(endpoint.model, action, player, args)
    end,
    keyboardScreen = function(address)
      for _, panel in pairs(config.panels or {}) do
        local screen = deps.component.proxy(panel.screen)
        for _, keyboard in ipairs(screen.getKeyboards()) do if keyboard == address then return panel.screen end end
      end
    end,
    static = function(gpu, width, height)
      gpu.fill(1, 1, width, 1, "="); gpu.fill(1, height, width, 1, "=")
    end})
  if rpc then remoteViews = require("spacecross.ui.remote_views").new({ui = ui, rpc = rpc}) end
  local self = {logger = logger, bus = bus, hal = hal, model = model, ui = ui,
    watcher = watcher, defense = defense, shields = shields, turrets = turrets, satellite = satellite, structures = structures, autopilot = autopilot, coreDaemon = coreDaemon, power = power,
    update = updateService, cnc = cnc, cncChannel = cncChannel, terminal = terminal, network = network, discovery = discovery, networkBridge = networkBridge, rpc = rpc, rpcTrust = rpcTrust, remoteViews = remoteViews, running = false}
  local inputs, uiTimer = {}, nil
  function self:start()
    if self.running then return false end
    self.running = true
    local started, startErr = xpcall(function()
      logger:start(); bus:start(); hal:start()
      if terminal then terminal:start() end
      if network then network:start(); discovery:start() end
      if networkBridge then networkBridge:start() end
      if rpc then rpc:start() end
      if updateService then updateService:start() end
      if cncChannel then cncChannel:start(); cnc:start() end
      if watcher then watcher:start() end
      if satellite then satellite:start() end
      if defense then defense:start() end
      if power then power:start() end
      if coreDaemon then coreDaemon:start() end
      if autopilot then
        local ok, err = autopilot:start()
        if not ok then log("warning", "AUTOPILOT_UNAVAILABLE", {error = tostring(err)}) end
      end
      if structures then assert(structures:activate()) end
      for _, panel in ipairs(config.panels or {}) do
        ui:addPanel(panel.id, deps.component.proxy(panel.gpu), panel.screen, panel.player)
        local tab = require("spacecross.ui.status_tab")("hardware", {{host = "localhost", model = "hardware"}})
        ui:addTab(panel.id, tab); ui:select(panel.id, tab.id)
        if watcher then ui:addTab(panel.id, require("spacecross.ui.status_tab")("entities", {{host = "localhost", model = "entities"}})) end
        if defense then ui:addTab(panel.id, require("spacecross.ui.defense_tab")({host = "localhost", model = "defense"})) end
        if shields then ui:addTab(panel.id, require("spacecross.ui.shield_tab").new({host = "localhost", model = "shields"})) end
        if turrets then ui:addTab(panel.id, require("spacecross.ui.turret_tab").new({host = "localhost", model = "turrets"})) end
        if autopilot then ui:addTab(panel.id, require("spacecross.ui.autopilot_tab")({host = "localhost", model = "autopilot"})) end
        if power then ui:addTab(panel.id, require("spacecross.ui.power_tab")({{host = "localhost", model = "power"}})) end
        if network then ui:addTab(panel.id, require("spacecross.ui.network_tab")({host = "localhost", model = "network"}, panel.id)) end
        if updateService then ui:addTab(panel.id, require("spacecross.ui.update_tab")({host = "localhost", model = "update"})) end
      end
      for _, name in ipairs({"touch", "drag", "drop", "scroll", "key_down", "key_up", "clipboard"}) do
        local handler = function(...)
          local signal = {...}
          for id in pairs(ui.panels) do
            local ok, result, err = pcall(ui.input, ui, id, signal)
            if not ok then log("error", "ERR_UI_INPUT", {error = tostring(result)})
            elseif not result and err == "EACCES" then log("warning", "ACCESS_DENIED", {event = signal[1]}) end
          end
        end
        inputs[name] = handler; deps.event.listen(name, handler)
      end
      if next(ui.panels) then
        uiTimer = deps.event.timer(config.uiInterval or 2, function()
          for id in pairs(ui.panels) do
            local ok, err = pcall(ui.refresh, ui, id)
            if not ok then log("error", "ERR_UI_RENDER", {error = tostring(err)}) end
          end
        end, math.huge)
      end
      log("info", "SYSTEM_STARTED")
    end, debug.traceback)
    if not started then self:stop(); error(startErr, 0) end
    return true
  end
  function self:stop()
    if not self.running then return false end
    if uiTimer then deps.event.cancel(uiTimer); uiTimer = nil end
    for name, handler in pairs(inputs) do deps.event.ignore(name, handler) end
    inputs = {}
    if terminal then terminal:stop() end
    if updateService then updateService:stop() end
    if cnc then cnc:stop() end
    if rpc then rpc:stop() end
    if cncChannel then cncChannel:stop() end
    if remoteViews then remoteViews.selections = {} end
    if structures then structures:deactivate() end
    if autopilot then
      local ok, err = autopilot:stop()
      if ok == nil then log("error", "AUTOPILOT_STOP_FAILED", {error = tostring(err)}) end
    end
    if coreDaemon then coreDaemon:stop() end
    if power then power:stop() end
    if defense then defense:stop() end
    if watcher then watcher:stop() end
    if satellite then satellite:stop() end
    if networkBridge then networkBridge:stop() end
    if discovery then discovery:stop() end
    if network then network:stop() end
    hal:stop(); bus:stop()
    log("info", "SYSTEM_STOPPED"); logger:stop()
    ui.panels = {}
    self.running = false
    return true
  end
  return self
end
return M
