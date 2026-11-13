local util = require("spacecross.core.util")
local M = {}

local function validMode(mode)
  return mode == "jump" or mode == "charges"
end
local function validTarget(target)
  return type(target) == "table" and type(target.id or target.name) == "string"
end

function M.new(deps, config)
  config = config or {}
  local interval = config.heartbeatInterval or 10
  assert(interval == 10, "satellite heartbeat interval is fixed at 10 seconds")
  assert(config.modeScan == nil or type(config.modeScan) == "boolean")
  assert(config.autoAttack == nil or type(config.autoAttack) == "boolean")
  assert(not config.autoAttack or config.modeScan == true, "autoAttack requires modeScan")
  local self = {running = false, state = "idle", mode = config.mode or "jump",
    whitelist = {}, whitelistReady = false, whitelistRequest = nil, targets = {}, lastHeartbeat = nil, heartbeatError = nil}
  assert(validMode(self.mode), "invalid satellite mine mode")
  local function log(level, code, fields) if deps.log then deps.log(level, code, fields) end end
  local function persistWhitelist()
    if not deps.fs or not config.cachePath then return true end
    if not deps.crypto or type(deps.crypto.encrypt) ~= "function" then return nil, "ENCRYPTION_UNAVAILABLE" end
    local encoded = deps.codec.encode(util.sortedKeys(self.whitelist))
    local called, sealed, err = pcall(deps.crypto.encrypt, deps.crypto, encoded)
    if not called then return nil, tostring(sealed) end
    if not sealed then return nil, err or "ENCRYPT_FAILED" end
    return deps.fs.atomicWrite(config.cachePath, sealed)
  end
  local function loadWhitelist()
    if not deps.fs or not config.cachePath then return nil, "NO_CACHE" end
    if not deps.crypto or type(deps.crypto.decrypt) ~= "function" then return nil, "ENCRYPTION_UNAVAILABLE" end
    local blob = deps.fs.read(config.cachePath)
    if not blob then return nil, "NO_CACHE" end
    local called, plain, err = pcall(deps.crypto.decrypt, deps.crypto, blob)
    if not called then return nil, tostring(plain) end
    if not plain then return nil, err or "DECRYPT_FAILED" end
    local values, decodeErr = deps.codec.decode(plain)
    if type(values) ~= "table" then return nil, decodeErr or "INVALID_CACHE" end
    if type(values) ~= "table" or #values > 4096 then return nil, "INVALID_CACHE" end
    local nextList = {}
    for _, value in ipairs(values) do
      if type(value) ~= "string" or #value == 0 or #value > 128 then return nil, "INVALID_CACHE" end
      nextList[value] = true
    end
    self.whitelist = nextList
    self.whitelistReady = true
    return true
  end
  local function heartbeat()
    if not deps.sendHeartbeat then return nil, "HEARTBEAT_UNAVAILABLE" end
    local called, ok, err = pcall(deps.sendHeartbeat, {id = config.id, state = self.state, mode = self.mode})
    if not called then ok, err = nil, tostring(ok) end
    if ok then self.lastHeartbeat, self.heartbeatError = deps.clock(), nil; return true end
    self.heartbeatError = tostring(err or "HEARTBEAT_FAILED"); log("warning", "SATELLITE_HEARTBEAT_FAILED", {error = self.heartbeatError}); return nil, self.heartbeatError
  end
  local function refreshWhitelist()
    if deps.fetchWhitelist then
      local values, err = deps.fetchWhitelist()
      if not values then return nil, err or "WHITELIST_UNAVAILABLE" end
      return self:updateWhitelist(values)
    end
    if deps.beginWhitelist and deps.pollWhitelist then
      if not self.whitelistRequest then
        local id, beginErr = deps.beginWhitelist()
        if not id then return nil, beginErr or "WHITELIST_UNAVAILABLE" end
        self.whitelistRequest = id
        return nil, "PENDING"
      end
      local ready, values, pollErr = deps.pollWhitelist(self.whitelistRequest)
      if ready == false then return nil, "PENDING" end
      self.whitelistRequest = nil
      if not ready then return nil, pollErr or "WHITELIST_UNAVAILABLE" end
      return self:updateWhitelist(values)
    end
    return nil, "WHITELIST_UNAVAILABLE"
  end
  local function invoke(fn, ...)
    local ok, value, err = pcall(fn, ...)
    if not ok then return nil, tostring(value) end
    if value == false or value == nil then return nil, err or "ADAPTER_FAILED" end
    return value, err
  end
  function self:snapshot()
    return {running = self.running, state = self.state, mode = self.mode,
      whitelistCount = (function() local n=0; for _ in pairs(self.whitelist) do n=n+1 end; return n end)(),
      whitelistReady = self.whitelistReady,
      targets = util.copy(self.targets), lastHeartbeat = self.lastHeartbeat, heartbeatError = self.heartbeatError,
      attack = util.copy(self.attack)}
  end
  function self:setMode(mode)
    if not validMode(mode) then return nil, "INVALID_MODE" end
    if self.state == "attacking" then return nil, "EBUSY" end
    self.mode = mode; return true
  end
  function self:updateWhitelist(values)
    if type(values) ~= "table" or #values > 4096 then return nil, "INVALID_WHITELIST" end
    local nextList = {}
    for _, value in ipairs(values) do if type(value) ~= "string" or #value == 0 or #value > 128 then return nil, "INVALID_WHITELIST" end; nextList[value] = true end
    self.whitelist = nextList
    self.whitelistReady = true
    local ok, err = persistWhitelist()
    if not ok then return nil, err end
    return true
  end
  function self:scan()
    if not deps.scan then return nil, "RADAR_UNAVAILABLE" end
    local called, found, err = pcall(deps.scan, config.range or 128)
    if not called then return nil, tostring(found) end
    if not found then return nil, err or "SCAN_FAILED" end
    if type(found) ~= "table" or found.complete == false then return nil, "INCOMPLETE_SCAN" end
    self.targets = {}
    for _, target in ipairs(found) do if validTarget(target) then self.targets[#self.targets + 1] = util.copy(target) end end
    return util.copy(self.targets)
  end
  local function allowed(target)
    return self.whitelist[target.id] or self.whitelist[target.name]
  end
  function self:attack(target)
    if not validTarget(target) then return nil, "INVALID_TARGET" end
    if not self.whitelistReady then return nil, "WHITELIST_UNAVAILABLE" end
    if not next(self.whitelist) then return nil, "EMPTY_WHITELIST" end
    if allowed(target) then return nil, "WHITELISTED_TARGET" end
    if self.state == "attacking" then return nil, "EBUSY" end
    self.state = "attacking"
    if deps.sendAttackAlert then pcall(deps.sendAttackAlert, {target = util.copy(target), mode = self.mode}) end
    local ok, err
    if self.mode == "jump" then
      if not deps.jumpToTarget or not deps.detonateCentralCharge then self.state = "error"; return nil, "JUMP_ATTACK_UNAVAILABLE" end
      ok, err = invoke(deps.jumpToTarget, util.copy(target))
      if ok then ok, err = invoke(deps.detonateCentralCharge, util.copy(target)) end
    else
      if not deps.position or not deps.activateAuxiliaryCharges or not deps.detonateCentralCharge then
        self.state = "error"; return nil, "DIRECTIONAL_ATTACK_UNAVAILABLE"
      end
      local origin, positionErr = invoke(deps.position)
      if not origin then self.state = "error"; return nil, positionErr end
      if type(origin) ~= "table" or type(origin.x) ~= "number" or type(origin.y) ~= "number" or type(origin.z) ~= "number"
        or type(target.x) ~= "number" or type(target.y) ~= "number" or type(target.z) ~= "number" then
        self.state = "error"; return nil, "TARGET_VECTOR_UNAVAILABLE"
      end
      local vector = {x = target.x - origin.x, y = target.y - origin.y, z = target.z - origin.z}
      ok, err = invoke(deps.activateAuxiliaryCharges, util.copy(target), vector, 6)
      if ok then ok, err = invoke(deps.detonateCentralCharge, util.copy(target)) end
    end
    if ok then self.attack = {target = util.copy(target), mode = self.mode, at = deps.clock()}; self.state = "armed"; log("critical", "SATELLITE_ATTACK", self.attack); return true end
    self.state, self.attack = "error", nil
    return nil, err or "ATTACK_FAILED"
  end
  function self:tick()
    if not self.running then return false end
    local online = heartbeat()
    if online then refreshWhitelist() end
    if config.modeScan and self.state ~= "attacking" then
      local targets = self:scan()
      if config.autoAttack and targets then
        for _, target in ipairs(targets) do
          if not allowed(target) then self:attack(target); break end
        end
      end
    end
    return true
  end
  function self:start()
    if self.running then return nil, "EBUSY" end
    loadWhitelist()
    self.running = true; self.state = "idle"
    local ok, timer = pcall(deps.event.timer, interval, function() self:tick() end, math.huge)
    if not ok or type(timer) ~= "number" then self.running = false; return nil, tostring(timer) end
    self.timer = timer; self:tick(); return true
  end
  function self:stop()
    if not self.running then return false end
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    self.running, self.state = false, "stopped"; return true
  end
  return self
end
return M
