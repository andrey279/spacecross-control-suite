local util = require("spacecross.core.util")
local codec = require("spacecross.core.codec")
local M = {}
local function ratio(value) return type(value) == "number" and value == value and value >= 0 and value <= 1 end
function M.new(deps, config)
  config = config or {}
  local low, high = config.startBelow or 0.3, config.stopAbove or 0.8
  local thresholds = config.shedBelow or {0.3, 0.2, 0.1}
  assert(ratio(low) and ratio(high) and low < high, "invalid generation thresholds")
  assert(#thresholds == 3 and ratio(thresholds[1]) and ratio(thresholds[2]) and ratio(thresholds[3])
    and thresholds[1] >= thresholds[2] and thresholds[2] >= thresholds[3], "invalid shedding thresholds")
  assert((config.interval or 2) > 0)
  local loads, ids = util.copy(config.loads or {}), {}
  for _, load in ipairs(loads) do
    assert(type(load.id) == "string" and not ids[load.id] and type(load.address) == "string", "invalid load")
    ids[load.id] = true
    assert(load.group == 1 or load.group == 2 or load.group == 3, "invalid load priority")
    for _, action in ipairs({"on", "off"}) do
      assert(type(load[action]) == "table" and type(load[action].method) == "string", "load action required")
    end
  end
  table.sort(loads, function(a, b) return a.group < b.group or a.group == b.group and a.id < b.id end)
  local owners = {}
  for _, name in ipairs(config.owners or {}) do owners[name:lower()] = true end
  local self = {running = false, disabled = {}, telemetry = {}, faults = {}}
  local function addresses(configured, kind)
    if configured then return configured end
    local out = {}
    for _, instance in ipairs(deps.hal.registry:list(kind)) do out[#out + 1] = instance.address end
    return out
  end
  local function ownerState()
    if next(owners) == nil then return false, true end
    if not deps.watcher then return false, false end
    local snapshot = deps.watcher:snapshot()
    for _, entity in ipairs(snapshot.entities or {}) do if owners[entity.name:lower()] then return true, true end end
    return false, snapshot.complete == true
  end
  local function loadAction(load, action)
    local command = load[action]
    return deps.hal:call(load.address, command.method, table.unpack(command.args or {}))
  end
  local function fault(address, err)
    self.faults[#self.faults + 1] = {address = address, error = tostring(err)}
  end
  function self:snapshot()
    return {generating = self.generating, disabled = util.copy(self.disabled), telemetry = util.copy(self.telemetry),
      faults = util.copy(self.faults), running = self.running, lastError = self.lastError}
  end
  local function tick()
    local stored, capacity, complete = 0, 0, true
    self.faults = {}
    local buffers = addresses(config.buffers, "buffer")
    if #buffers == 0 then complete = false; fault("buffers", "NO_ENERGY_BUFFER") end
    for _, address in ipairs(buffers) do
      local level, err = deps.hal:call(address, "getEnergyLevel")
      if type(level) == "table" and type(level.stored) == "number" and type(level.capacity) == "number"
          and level.stored == level.stored and level.capacity == level.capacity and level.capacity > 0
          and level.capacity < math.huge and level.stored >= 0 and level.stored <= level.capacity then
        stored, capacity = stored + level.stored, capacity + level.capacity
      else complete = false; fault(address, err or "INVALID_ENERGY") end
    end
    local sources = addresses(config.sources, "power")
    -- Maintain generators even when buffer telemetry has failed; each instance is isolated.
    for _, address in ipairs(sources) do
      local level, err = deps.hal:call(address, "getEnergyLevel")
      if not level then fault(address, err) end
    end
    local fraction = capacity > 0 and stored / capacity or nil
    local now = deps.clock()
    local deficit = self.previousStored and now > self.previousTime and math.max(0, (self.previousStored - stored) / (now - self.previousTime)) or 0
    self.telemetry = {stored = stored, capacity = capacity, fraction = fraction, complete = complete, time = now, deficit = deficit}
    local present, presenceKnown = ownerState()
    self.telemetry.ownerPresent, self.telemetry.ownerPresenceKnown = present, presenceKnown
    if complete then
      if fraction < low then self.generating = true elseif fraction >= high then self.generating = false end
      for _, address in ipairs(sources) do
        if self.generating ~= nil then
          local ok, err = deps.hal:call(address, self.generating and "turn_on" or "turn_off")
          if not ok then fault(address, err) end
        end
      end
      for _, load in ipairs(loads) do
        local needsShedding = fraction < thresholds[load.group]
        -- Group 2 can only be shed after a complete scan proves no owner is present.
        if load.group == 2 and (present or not presenceKnown) then needsShedding = false end
        if needsShedding and not self.disabled[load.id] then
          local ok, err = loadAction(load, "off")
          if ok then self.disabled[load.id] = true else fault(load.address, err) end
        end
      end
      self.previousStored, self.previousTime = stored, now
    else self.previousStored, self.previousTime = nil, nil end
    -- Restore only controller-shed loads. Owner return restores group 2 even
    -- if a separate buffer has failed; that owner's presence is still known.
    for index = #loads, 1, -1 do
      local load = loads[index]
      if self.disabled[load.id] and (complete and fraction >= high or load.group == 2 and present) then
        local ok, err = loadAction(load, "on")
        if ok then self.disabled[load.id] = nil else fault(load.address, err) end
      end
    end
    local snapshot = self:snapshot()
    if deps.bus then deps.bus:publish({proto_version = 1, msg_type = "event", port = config.port or 27103, payload = codec.encode(snapshot)}) end
    if deps.log then deps.log(#self.faults > 0 and "warning" or "info", "POWER_TELEMETRY", snapshot) end
    return snapshot
  end
  function self:tick()
    if self.ticking then return nil, "EBUSY" end
    self.ticking = true
    local ok, value = pcall(tick)
    self.ticking = false
    if not ok then
      self.lastError = tostring(value)
      if deps.log then pcall(deps.log, "error", "ERR_POWER_CONTROL", {error = self.lastError}) end
      return nil, self.lastError
    end
    self.lastError = nil
    return value
  end
  function self:start()
    if self.running then return false end
    self.timer = deps.event.timer(config.interval or 2, function() self:tick() end, math.huge)
    self.running = true
    self:tick()
    return true
  end
  function self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    self.running = false
    return true
  end
  return self
end
return M
