local M = {}
local kinds = {cmd = true, event = true, heartbeat = true}
function M.validate(message)
  if type(message) ~= "table" or message.proto_version ~= 1 or not kinds[message.msg_type]
      or type(message.payload) ~= "string" or #message.payload > 65536
      or type(message.port) ~= "number" or message.port % 1 ~= 0
      or message.port < 1 or message.port > 65535
      or (message.src_addr ~= nil and type(message.src_addr) ~= "string")
      or (message.dst_addr ~= nil and type(message.dst_addr) ~= "string") then
    return nil, "EINVAL_MESSAGE"
  end
  return true
end

function M.new(deps)
  local self = {subscriptions = {}, running = false, nextId = 0}
  local function dispatch(_, version, kind, source, destination, port, payload)
    local message = {proto_version = version, msg_type = kind, src_addr = source,
      dst_addr = destination, port = port, payload = payload}
    if not M.validate(message) then return end
    -- Snapshot prevents subscribe/unsubscribe during callback from skipping listeners.
    local listeners = {}
    for id, item in pairs(self.subscriptions) do listeners[#listeners + 1] = {id, item} end
    table.sort(listeners, function(a, b) return a[1] < b[1] end)
    for _, pair in ipairs(listeners) do
      local item = pair[2]
      if self.subscriptions[pair[1]] and (not item.port or item.port == port) then
        local copy = {proto_version = version, msg_type = kind, src_addr = source,
          dst_addr = destination, port = port, payload = payload}
        local ok, err = pcall(item.callback, copy)
        if not ok and deps.log then pcall(deps.log, "error", "ERR_BUS_CALLBACK", {error = tostring(err)}) end
      end
    end
  end
  function self:subscribe(port, callback)
    assert(port == nil or (type(port) == "number" and port >= 1 and port <= 65535 and port % 1 == 0))
    assert(type(callback) == "function")
    self.nextId = self.nextId + 1
    self.subscriptions[self.nextId] = {port = port, callback = callback}
    return self.nextId
  end
  function self:unsubscribe(id) self.subscriptions[id] = nil end
  function self:publish(message)
    local ok, err = M.validate(message)
    if not ok then return nil, err end
    if not self.running then return nil, "ENOTRUNNING" end
    return deps.event.push("spacecross_message", 1, message.msg_type, message.src_addr,
      message.dst_addr, message.port, message.payload)
  end
  function self:start()
    if self.running then return false end
    deps.event.listen("spacecross_message", dispatch)
    self.running = true
    return true
  end
  function self:stop()
    deps.event.ignore("spacecross_message", dispatch)
    self.running = false
  end
  return self
end
return M
