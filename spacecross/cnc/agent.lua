local M = {}
function M.new(deps, config)
  local self = {running = false, lastError = nil, lastHeartbeat = nil, satelliteCalls = {}}
  local heartbeat, upload, timer, due, busy, proof, uploadBusy = nil, nil, nil, 0, false, nil, false
  local satelliteStatus
  local function begin(model, action, args)
    return deps.rpc:begin(config.peer, model, action, config.actor, args, config.address)
  end
  -- A one-use in-process capability. No network field or discovery message is proof.
  function self:verifyHeartbeat(candidate)
    if candidate == nil or candidate ~= proof then return false end
    proof = nil; return true
  end
  function self:updateSatelliteStatus(status)
    if type(status) ~= "table" or (status.mode ~= "jump" and status.mode ~= "charges")
      or type(status.state) ~= "string" or #status.state > 32 then return nil, "INVALID_SATELLITE_STATUS" end
    satelliteStatus = {mode = status.mode, state = status.state}
    if deps.channel.connected then return true end
    return nil, "CNC_DISCONNECTED"
  end
  function self:beginSatelliteWhitelist()
    if not self.running or not deps.channel.connected then return nil, "CNC_DISCONNECTED" end
    return begin("_cnc", "whitelist", {})
  end
  function self:pollSatelliteWhitelist(id)
    local ready, value, err = deps.rpc:poll(id)
    if ready == false then return false end
    if ready then deps.rpc:take(id) end
    if not ready or type(value) ~= "table" or type(value.values) ~= "table" then return nil, err or "INVALID_WHITELIST_RESPONSE" end
    return true, value.values
  end
  function self:sendSatelliteAlert(alert)
    if not self.running or not deps.channel.connected then return nil, "CNC_DISCONNECTED" end
    local id, err = begin("_cnc", "alert", alert)
    if not id then return nil, err end
    self.satelliteCalls[id] = "alert"
    return true
  end
  local function uploadCall(name, data)
    if not self.running then return nil, "ESHUTDOWN" end
    if upload then
      if upload.name ~= name or upload.data ~= data then return nil, "EBUSY" end
      local ready, result, err = deps.rpc:poll(upload.id)
      if ready == false then return nil, "EAGAIN" end
      if ready then deps.rpc:take(upload.id) end
      local expected = upload.digest; upload = nil
      if ready and type(result) == "table" and result.receipt == name and result.digest == expected then return name end
      return nil, err or "INVALID_LOG_RECEIPT"
    end
    if not deps.channel.connected then return nil, "CNC_DISCONNECTED" end
    local id, err = begin("_logs", "put", {id = name, data = data})
    if not id then return nil, err end
    if not self.running then return nil, "ESHUTDOWN" end
    local digest = deps.crypto.sha256(data)
    if not self.running then return nil, "ESHUTDOWN" end
    upload = {id = id, name = name, data = data, digest = digest}
    return nil, "EAGAIN"
  end
  function self:upload(name, data)
    if uploadBusy then return nil, "EBUSY" end
    uploadBusy = true
    local ok, receipt, err = pcall(uploadCall, name, data)
    uploadBusy = false
    if not ok then return nil, tostring(receipt) end
    return receipt, err
  end
  local function tick()
    if heartbeat then
      local ready, value, err = deps.rpc:poll(heartbeat)
      if ready ~= false then
        if ready then deps.rpc:take(heartbeat) end
        heartbeat, due = nil, deps.clock() + (config.heartbeatInterval or 10)
        if ready and type(value) == "table" and value.alive == true then
          self.lastHeartbeat, self.lastError = deps.clock(), nil
          deps.channel:authenticated()
          if deps.heartbeat then proof = {}; deps.heartbeat(proof); proof = nil end
        else self.lastError = err or "INVALID_HEARTBEAT" end
      end
    elseif deps.channel.connected and deps.clock() >= due then
      local id, err = begin("_cnc", "heartbeat", satelliteStatus and {satellite = satelliteStatus} or {})
      if id then heartbeat = id else self.lastError, due = err, deps.clock() + 1 end
    end
  end
  function self:tick()
    if not self.running or busy then return end
    busy = true; local ok, err = pcall(tick); busy = false
    if not ok then self.lastError = tostring(err) end
    for id in pairs(self.satelliteCalls) do
      local ready, _, callErr = deps.rpc:poll(id)
      if ready ~= false then
        deps.rpc:take(id); self.satelliteCalls[id] = nil
        if not ready then self.lastError = callErr or "SATELLITE_ALERT_FAILED" end
      end
    end
  end
  function self:start()
    if self.running then return false end
    self.running, due = true, 0
    timer = deps.event.timer(config.interval or 0.2, function() self:tick() end, math.huge)
    return true
  end
  function self:stop()
    if timer then deps.event.cancel(timer); timer = nil end
    self.running, heartbeat, upload, proof, self.satelliteCalls = false, nil, nil, nil, {}
  end
  return self
end
return M
