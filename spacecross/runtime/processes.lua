-- Resident numeric IDs for OpenOS processes. Uses public process.info, no OS hooks.
local M = {}
local states, nextId = setmetatable({}, {__mode = "k"}), 0
function M.new(process)
  local records = states[process] or {}
  states[process] = records
  local self = {}
  function self.alive(pid)
    local record = records[pid]
    if not record then return false end
    local ok, info = pcall(process.info, record.thread)
    if not ok or not info or info.data ~= record.data or rawget(info.data, "result") ~= nil then
      records[pid] = nil
      return false
    end
    return true
  end
  function self.pid()
    local info = assert(process.info(), "OpenOS process unavailable")
    for pid, record in pairs(records) do
      if self.alive(pid) and record.data == info.data then return pid end
    end
    nextId = nextId + 1
    records[nextId] = {data = info.data, thread = coroutine.running()}
    return nextId
  end
  return self
end
return M
