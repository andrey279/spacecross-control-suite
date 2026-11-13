-- Terminal lifecycle/transport stub, not a shell or an OpenOS compatibility claim.
local M = {}
function M.new()
  local self = {sessions = {}}
  function self:start(s)
    self.sessions[s.id] = s; s.gpu.set(1, 1, "ready")
    local handle = {closed = false}
    function handle:status() return self.closed and "closed" or "running" end
    function handle:resize(w, h) s.gpu.setResolution(w, h) end
    function handle:wake() end
    function handle:close() self.closed = true end
    return handle
  end
  return self
end
return M
