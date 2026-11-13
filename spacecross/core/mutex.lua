local M = {}
-- All OpenOS processes share this resident module. Reserve before any yielding I/O.
local reservations = {}
function M.new(deps, path)
  path = path or "/tmp/autopilot.lock"
  local self = {held = false}
  function self:acquire()
    if self.held then return nil, "EBUSY" end
    local pid = deps.processes.pid()
    local old = reservations[path]
    if old and deps.processes.alive(old.pid) then return nil, "EBUSY" end
    local token = {pid = pid}
    reservations[path] = token
    local ok, result, err = pcall(function()
      local contents, readErr = deps.fs.read(path)
      if not contents and deps.fs.exists(path) then return nil, readErr or "EIO_LOCK" end
      if contents then
        local oldPid = tonumber(contents:match("^(%d+)%s*$"))
        if not oldPid then return nil, "ECORRUPT_LOCK" end
        if deps.processes.alive(oldPid) then return nil, "EBUSY" end
      end
      local written, writeErr = deps.fs.atomicWrite(path, tostring(pid))
      if not written then return nil, writeErr end
      self.held, self.pid, self.token = true, pid, token
      return true
    end)
    if not ok or not result then
      if reservations[path] == token then reservations[path] = nil end
      return nil, ok and err or tostring(result)
    end
    return true
  end
  function self:release()
    if not self.held then return false end
    local contents = deps.fs.read(path)
    if reservations[path] ~= self.token or contents ~= tostring(self.pid) then return nil, "EOWNER_LOCK" end
    local ok, err = deps.fs.remove(path)
    if not ok then return nil, err end
    reservations[path] = nil
    self.held, self.token = false, nil
    return true
  end
  return self
end
return M
