local codec = require("spacecross.core.codec")
local util = require("spacecross.core.util")
local M = {}
local levels = {debug = true, info = true, warning = true, error = true, critical = true}

function M.new(deps, config)
  config = config or {}
  local self = {queue = {}, running = false, dropped = 0, lastError = nil}
  local root, maxQueue = config.root or "/var/lib/spacecross/logs", config.maxQueue or 256
  local sequence, uploadName = 0, nil
  util.check(deps.fs.mkdir(root))
  local savedSequence = deps.fs.read(root .. "/sequence")
  assert(savedSequence or not deps.fs.exists(root .. "/sequence"), "unreadable log sequence")
  if savedSequence then
    assert(savedSequence:match("^%d+$") and tonumber(savedSequence) < 9007199254740991, "corrupt log sequence")
    sequence = tonumber(savedSequence)
  end
  local node = config.nodeId or deps.nodeId or "localhost"
  assert(node:match("^[%w%-]+$"), "invalid log node ID")
  local function seal(record)
    if not deps.crypto then return nil, "ENCRYPTION_UNAVAILABLE" end
    local ok, data, err = pcall(deps.crypto.seal, codec.encode(record))
    if not ok then return nil, data end
    if type(data) ~= "string" then return nil, err or "ENCRYPTION_FAILED" end
    return data
  end
  function self:write(level, code, fields)
    assert(levels[level] and type(code) == "string", "invalid log record")
    if #self.queue >= maxQueue then self.dropped = self.dropped + 1; return nil, "ENOBUFS" end
    self.queue[#self.queue + 1] = {level = level, code = code,
      fields = util.copy(fields or {}), time = deps.clock()}
    return true
  end
  local function flush(recordBudget, uploadBudget)
    self.lastError = nil
    -- Encrypt before any disk write. With no card, retain a bounded RAM queue.
    local processed = 0
    while #self.queue > 0 and processed < (recordBudget or math.huge) do
      local record = self.queue[1]
      local data, err = seal(record)
      if not data then self.lastError = err; break end
      local nextSequence = sequence + 1
      assert(nextSequence < 9007199254740991, "log sequence exhausted")
      local saved, saveErr = deps.fs.atomicWrite(root .. "/sequence", string.format("%.0f", nextSequence))
      if not saved then self.lastError = saveErr; break end
      sequence = nextSequence
      local name = node .. "-" .. string.format("%.0f", sequence) .. ".sealed"
      local ok, writeErr = deps.fs.atomicWrite(root .. "/" .. name, data)
      if not ok then self.lastError = writeErr; break end
      table.remove(self.queue, 1)
      processed = processed + 1
    end
    -- Files survive restart; only a durable matching receipt permits deletion.
    if deps.upload then
      local names = deps.fs.list(root)
      -- New files can sort before a pending asynchronous upload (e.g. 10 vs 2).
      -- Always finish its receipt before starting a different file.
      if uploadName then for i, name in ipairs(names) do if name == uploadName then table.remove(names, i); table.insert(names, 1, name); break end end end
      local uploaded = 0
      for _, name in ipairs(names) do
        if name:match("^[%w%-]+%.sealed$") then
          if uploaded >= (uploadBudget or math.huge) then break end
          local path = root .. "/" .. name
          local data, err = deps.fs.read(path)
          if not data then self.lastError = err; break end
          uploadName = name
          local ok, receipt = pcall(deps.upload, name, data)
          if ok and receipt == name then
            local deleted, removeErr = deps.fs.remove(path)
            if not deleted then self.lastError = removeErr; break end
            uploadName, uploaded = nil, uploaded + 1
          else self.lastError = "UPLOAD_UNACKNOWLEDGED"; break end
        end
      end
    end
    return self.lastError == nil, self.lastError
  end
  function self:flush(recordBudget, uploadBudget)
    if self.flushing then return nil, "EBUSY" end
    self.flushing = true
    local ok, result, err = pcall(flush, recordBudget, uploadBudget)
    self.flushing = false
    if not ok then self.lastError = tostring(result); return false, self.lastError end
    return result, err
  end
  local function tick()
    local ok, err = pcall(self.flush, self, config.maxRecordsPerTick or 8, config.maxUploadsPerTick or 4)
    if not ok then self.lastError = tostring(err) end
  end
  function self:start()
    if self.running then return false end
    self.timer = deps.event.timer(config.interval or 1, tick, math.huge)
    self.running = true
    return true
  end
  function self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    self.running = false
    return self:flush()
  end
  return self
end
return M
