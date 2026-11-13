local util = require("spacecross.core.util")
local codec = require("spacecross.core.codec")
local M = {}

local function validRoute(route)
  if type(route) ~= "table" or #route == 0 or #route > 256 then return nil, "INVALID_ROUTE" end
  for _, point in ipairs(route) do
    if not require("spacecross.autopilot.autopilot_core").validPosition(point) then return nil, "INVALID_WAYPOINT" end
  end
  return true
end

function M.new(deps, config)
  config = config or {}
  assert(deps.autopilot and deps.clock and deps.event and deps.deploy and deps.provisionComputer and deps.confirm)
  assert((config.interval or 1) > 0 and (config.interval or 1) <= 60)
  assert(type(config.program) == "string" and config.program:match("^[%w_.%-]+$"), "configured structure program required")
  assert((config.navigationTimeout or 180) > 0 and (config.navigationTimeout or 180) <= 3600)
  local self = {running = false, state = "idle", phase = "idle", route = {}, index = 1}
  local function publish(code)
    if deps.log then deps.log(self.state == "error" and "error" or "info", code, self:snapshot()) end
  end
  local function fail(err)
    if self.phase == "travel" then pcall(deps.autopilot.cancel, deps.autopilot) end
    self.state, self.phase, self.error = "error", "idle", tostring(err or "DEPLOYMENT_FAILED")
    publish("STRUCTURE_DEPLOYMENT_FAILED")
    return nil, self.error
  end
  function self:snapshot()
    return {running = self.running, state = self.state, phase = self.phase,
      index = self.index, count = #self.route, target = util.copy(self.route[self.index]),
      error = self.error, program = config.program}
  end
  function self:start(route)
    if not self.running then return nil, "ENOTRUNNING" end
    if self.state == "running" then return nil, "EBUSY" end
    if route == nil then
      if config.route then route = util.copy(config.route)
      elseif config.routePath then
        local data, err = deps.fs.read(config.routePath)
        if not data then return nil, err or "ROUTE_UNAVAILABLE" end
        route, err = codec.decode(data, config.maxRouteBytes or 65536)
        if not route then return nil, err or "INVALID_ROUTE" end
      end
    end
    local ok, err = validRoute(route)
    if not ok then return nil, err end
    self.route, self.index = util.copy(route), 1
    self.state, self.phase, self.error = "running", "navigate", nil
    publish("STRUCTURE_DEPLOYMENT_STARTED")
    return true
  end
  function self:stop()
    if self.state == "running" and self.phase == "travel" then deps.autopilot:cancel() end
    if self.state == "running" then self.state, self.phase = "stopped", "idle" end
    return true
  end
  local function runAdapter(fn, ...)
    local ok, value, err = pcall(fn, ...)
    if not ok then return nil, tostring(value) end
    if value == false then return nil, err or "ADAPTER_FAILED" end
    if value == nil and err ~= "PENDING" then return nil, err or "ADAPTER_FAILED" end
    return value, err
  end
  function self:tick()
    if not self.running or self.state ~= "running" or self.ticking then return false end
    self.ticking = true
    local ok, value, err = pcall(function()
      local target = self.route[self.index]
      if not target then self.state, self.phase = "done", "idle"; publish("STRUCTURE_DEPLOYMENT_COMPLETE"); return true end
      if self.phase == "navigate" then
        local accepted, navErr = deps.autopilot:navigate(target, config.controller)
        if not accepted then return fail(navErr) end
        self.travelStarted = deps.clock()
        self.phase = "travel"
      elseif self.phase == "travel" then
        local status = deps.autopilot:snapshot()
        if type(status) ~= "table" or type(status.state) ~= "string" then return fail("INVALID_NAVIGATION_STATUS") end
        if status.state == "error" then return fail(status.error or "NAVIGATION_FAILED") end
        if status.state == "cancelled" or status.state == "stopped" then return fail("NAVIGATION_CANCELLED") end
        if status.state == "done" then self.phase, self.travelStarted = "deploy", nil
        elseif status.state == "planning" or status.state == "waiting" then
          if deps.clock() - self.travelStarted >= (config.navigationTimeout or 180) then return fail("NAVIGATION_TIMEOUT") end
        else return fail("INVALID_NAVIGATION_STATE") end
      elseif self.phase == "deploy" then
        local deployed, deployErr = runAdapter(deps.deploy, util.copy(target), self.index)
        if not deployed then if deployErr == "PENDING" then return true end; return fail(deployErr) end
        self.receipt = type(deployed) == "table" and util.copy(deployed) or nil
        self.phase = "provision"
      elseif self.phase == "provision" then
        local provisioned, provisionErr = runAdapter(deps.provisionComputer, util.copy(target), config.program, self.index, util.copy(self.receipt))
        if not provisioned then if provisionErr == "PENDING" then return true end; return fail(provisionErr) end
        self.phase = "confirm"
      elseif self.phase == "confirm" then
        local confirmed, confirmErr = runAdapter(deps.confirm, util.copy(target), self.index, util.copy(self.receipt))
        if not confirmed then if confirmErr == "PENDING" then return true end; return fail(confirmErr) end
        self.index = self.index + 1
        self.receipt, self.travelStarted = nil, nil
        self.phase = "navigate"
        publish("STRUCTURE_WAYPOINT_CONFIRMED")
      end
      return true
    end)
    self.ticking = false
    if not ok then return fail(value) end
    return value, err
  end
  function self:activate()
    if self.running then return false end
    local ok, timer = pcall(deps.event.timer, config.interval or 1, function() self:tick() end, math.huge)
    if not ok or type(timer) ~= "number" then return nil, tostring(timer) end
    self.timer, self.running = timer, true
    return true
  end
  function self:deactivate()
    self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    self.running = false
    return true
  end
  return self
end
return M
