local util = require("spacecross.core.util")
local M = {}

function M.new()
  local self = {time = 0, listeners = {}, queue = {}, timers = {}, nextTimer = 0,
    files = {}, directories = {["/"] = true}, components = {}, errors = {}, operations = {}}
  self.clock = function() return self.time end
  self.processId, self.liveProcesses = 1, {[1] = true}
  self.processes = {pid = function() return self.processId end,
    alive = function(pid) return self.liveProcesses[pid] == true end}
  local event = {}
  function event.listen(name, fn)
    self.listeners[name] = self.listeners[name] or {}
    for _, old in ipairs(self.listeners[name]) do if old == fn then return false end end
    table.insert(self.listeners[name], fn)
    return true
  end
  function event.ignore(name, fn)
    for i, old in ipairs(self.listeners[name] or {}) do
      if old == fn then table.remove(self.listeners[name], i); return true end
    end
    return false
  end
  function event.push(...)
    self.queue[#self.queue + 1] = {n = select("#", ...), ...}
    return true
  end
  function event.timer(interval, callback, times)
    self.nextTimer = self.nextTimer + 1
    self.timers[self.nextTimer] = {interval = interval, callback = callback, times = times or 1, at = self.time + interval}
    return self.nextTimer
  end
  function event.cancel(id) self.timers[id] = nil; return true end
  function self:pump()
    local count = 0
    while #self.queue > 0 do
      count = count + 1
      assert(count <= 10000, "event loop runaway")
      local signal = table.remove(self.queue, 1)
      local listeners = {}
      for _, fn in ipairs(self.listeners[signal[1]] or {}) do listeners[#listeners + 1] = fn end
      for _, fn in ipairs(listeners) do fn(table.unpack(signal, 1, signal.n)) end
    end
  end
  function self:advance(seconds)
    local target = self.time + seconds
    while true do
      local nextId, at
      for id, timer in pairs(self.timers) do
        if timer.at <= target and (not at or timer.at < at) then nextId, at = id, timer.at end
      end
      if not nextId then break end
      self.time = at
      local timer = self.timers[nextId]
      timer.times = timer.times - 1
      if timer.times <= 0 then self.timers[nextId] = nil else timer.at = timer.at + timer.interval end
      timer.callback()
      self:pump()
    end
    self.time = target
    self:pump()
  end
  self.event = event
  self.component = {}
  function self.component.list(filter)
    local keys, pos = util.sortedKeys(self.components), 0
    return function()
      while pos < #keys do
        pos = pos + 1
        local value = self.components[keys[pos]]
        if not filter or value.type == filter then return keys[pos], value.type end
      end
    end
  end
  function self.component.proxy(address)
    assert(self.components[address], "component removed")
    return self.components[address]
  end
  function self.log(level, code, fields)
    self.errors[#self.errors + 1] = {level = level, code = code, fields = fields}
  end
  local fs = {}
  local function fail(operation, path)
    self.operations[#self.operations + 1] = {operation, path}
    return self.fail and self.fail(operation, path)
  end
  function fs.mkdir(path)
    if fail("mkdir", path) then return nil, "disk full" end
    local current = path:sub(1, 1) == "/" and "" or nil
    for part in path:gmatch("[^/]+") do
      current = current and current .. "/" .. part or part
      self.directories[current] = true
    end
    return true
  end
  function fs.exists(path) return self.files[path] ~= nil or self.directories[path] == true end
  function fs.isDirectory(path) return self.directories[path] == true end
  function fs.read(path)
    if fail("read", path) then return nil, "read failed" end
    if self.files[path] == nil then return nil, "not found" end
    return self.files[path]
  end
  function fs.write(path, data)
    if fail("write", path) then return nil, "write failed" end
    local parent = path:match("^(.*)/")
    if parent and not self.directories[parent] then return nil, "missing directory" end
    self.files[path] = data
    return true
  end
  function fs.rename(from, to)
    if fail("rename", to) then return nil, "rename failed" end
    if self.files[from] == nil then return nil, "not found" end
    self.files[to], self.files[from] = self.files[from], nil
    return true
  end
  function fs.remove(path)
    if fail("remove", path) then return nil, "remove failed" end
    if self.files[path] == nil then return nil, "not found" end
    self.files[path] = nil
    return true
  end
  function fs.list(root)
    local names = {}
    for path in pairs(self.files) do
      local name = path:sub(#root + 2)
      if path:sub(1, #root + 1) == root .. "/" and not name:find("/", 1, true) then names[#names + 1] = name end
    end
    for path in pairs(self.directories) do
      local name = path:sub(#root + 2)
      if path:sub(1, #root + 1) == root .. "/" and name ~= "" and not name:find("/", 1, true) then names[#names + 1] = name end
    end
    table.sort(names)
    return names
  end
  function fs.atomicWrite(path, data)
    local ok, err = fs.write(path .. ".new", data)
    if not ok then return nil, err end
    return fs.rename(path .. ".new", path)
  end
  self.fs = fs
  return self
end
return M
