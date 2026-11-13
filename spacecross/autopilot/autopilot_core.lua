local util = require("spacecross.core.util")
local codec = require("spacecross.core.codec")
local Mutex = require("spacecross.core.mutex")
local M = {}
local function position(value)
  if type(value) ~= "table" then return false end
  for _, axis in ipairs({"x", "y", "z"}) do
    local v = value[axis]
    if type(v) ~= "number" or v ~= v or math.abs(v) > 30000000 or v % 1 ~= 0 then return false end
  end
  return true
end
local function same(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
M.validPosition = position
function M.new(deps, config)
  config = config or {}
  assert((config.interval or 1) > 0 and (config.jumpTimeout or 180) > 0)
  local lock = Mutex.new(deps, config.lockPath)
  local self = {running = false, state = "idle", controllers = {}, route = {}, index = 1}
  local function publish(code)
    local data = self:snapshot()
    if deps.log then deps.log(self.state == "error" and "error" or "info", code, data) end
    if deps.bus then deps.bus:publish({proto_version = 1, msg_type = "event", port = config.port or 27102, payload = codec.encode(data)}) end
  end
  local function fail(err)
    self.state, self.error = "error", tostring(err)
    deps.coreDaemon:setActive(nil) -- a cooling core stays pending in the independent daemon
    publish("AUTOPILOT_FAILED")
    return nil, self.error
  end
  function self:snapshot()
    return {state = self.state, error = self.error, controller = self.controller, route = util.copy(self.route),
      index = self.index, position = util.copy(self.position), running = self.running, cores = deps.coreDaemon:snapshot()}
  end
  function self:registerController(name, handler)
    assert(type(name) == "string" and not self.controllers[name] and type(handler) == "function")
    self.controllers[name] = handler
  end
  function self:control(name, args)
    local handler = self.controllers[name]
    if not handler then return nil, "UNKNOWN_AUTOPILOT_PLUGIN" end
    return handler(self, util.copy(args or {}))
  end
  function self:setRoute(route, address)
    if not self.running then return nil, "ENOTRUNNING" end
    if self.state == "planning" or self.state == "waiting" then return nil, "EBUSY" end
    if type(route) ~= "table" or #route == 0 or #route > 1024 then return nil, "INVALID_ROUTE" end
    for _, target in ipairs(route) do if not position(target) then return nil, "INVALID_TARGET" end end
    address = address or config.controller
    if not address then
      for _, instance in ipairs(deps.hal.registry:list("navigation")) do
        if deps.coreDaemon:manages(instance.address) then address = instance.address; break end
      end
    end
    if not address or not deps.coreDaemon:manages(address) then return nil, "UNKNOWN_CONTROLLER" end
    self.route, self.index, self.controller = util.copy(route), 1, address
    self.state, self.error = "planning", nil
    publish("AUTOPILOT_ROUTE")
    return true
  end
  function self:navigate(target, address) return self:setRoute({target}, address) end
  function self:cancel()
    local ok, err = deps.coreDaemon:setActive(nil)
    self.state, self.error = "cancelled", ok and nil or err
    publish("AUTOPILOT_CANCELLED")
    return ok, err
  end
  function self:tick()
    if self.ticking then return nil, "EBUSY" end
    self.ticking = true
    local ok, result, err = pcall(function()
      if self.state ~= "planning" and self.state ~= "waiting" then return true end
      if not deps.coreDaemon:manages(self.controller) then return fail("CONTROLLER_REMOVED") end
      if self.state == "waiting" then
        if deps.clock() - self.jumpStarted > (config.jumpTimeout or 180) then return fail("JUMP_TIMEOUT") end
        if deps.coreDaemon.cooling[self.controller] then return true end
      end
      local current, posErr = deps.hal:call(self.controller, "getPosition")
      if not current then return fail(posErr) end
      self.position = current
      if self.state == "waiting" and same(current, self.beforeJump) then return fail("JUMP_NO_PROGRESS") end
      self.state = "planning"
      while self.route[self.index] and same(current, self.route[self.index]) do self.index = self.index + 1 end
      local target = self.route[self.index]
      if not target then
        local released, releaseErr = deps.coreDaemon:setActive(nil)
        if not released then return fail(releaseErr) end
        self.state = "done"; publish("AUTOPILOT_ARRIVED"); return true
      end
      local selected, selectErr = deps.coreDaemon:setActive(self.controller)
      if not selected then
        if selectErr == "EBUSY_COOLDOWN" then return true end
        return fail(selectErr)
      end
      local prepared, prepareErr = deps.hal:call(self.controller, "prepare")
      if not prepared then return fail(prepareErr) end
      local delta = {x = target.x - current.x, y = target.y - current.y, z = target.z - current.z}
      local maximum, maxErr = deps.hal:call(self.controller, "getMaxDistance", delta)
      if not maximum then return fail(maxErr) end
      local scale = math.min(1, maximum / math.max(math.abs(delta.x), math.abs(delta.y), math.abs(delta.z)))
      for axis, value in pairs(delta) do
        delta[axis] = value >= 0 and math.floor(value * scale) or math.ceil(value * scale)
      end
      self.beforeJump, self.jumpStarted = current, deps.clock()
      assert(deps.coreDaemon:markCooling(self.controller))
      local jumped, jumpErr = deps.hal:call(self.controller, "jump", delta)
      if not jumped then deps.coreDaemon:abort(self.controller); return fail(jumpErr) end
      self.state = "waiting"; publish("AUTOPILOT_JUMP")
      return true
    end)
    self.ticking = false
    if not ok then return fail(result) end
    return result, err
  end
  function self:start()
    if self.running then return nil, "EBUSY" end
    if not deps.coreDaemon.running then return nil, "CORE_DAEMON_NOT_RUNNING" end
    local ok, err = lock:acquire()
    if not ok then self.error = err; return nil, err end
    local created, timer = pcall(deps.event.timer, config.interval or 1, function() self:tick() end, math.huge)
    if not created or type(timer) ~= "number" then lock:release(); return nil, tostring(timer) end
    self.timer, self.running = timer, true
    return true
  end
  function self:stop()
    if not self.running and not lock.held then return false end
    if self.running then self:cancel() end
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    self.running = false
    local released, err = lock:release()
    if not released then return nil, err end
    return true
  end
  return self
end
return M
