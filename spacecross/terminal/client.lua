local M = {}
function M.new(deps, config)
  local self = {sequence = 0}
  local function call(action, args)
    args = args or {}; args.id = self.id
    return deps.rpc:request(config.host, "terminal", action, config.actor, args, config.card)
  end
  function self:open(width, height)
    if self.id then return nil, "EALREADY" end
    local result, err = call("open", {width = width, height = height})
    if not result then return nil, err end
    if type(result.id) ~= "string" or result.width ~= width or result.height ~= height then return nil, "EPROTOCOL" end
    self.id, self.sequence = result.id, result.sequence
    return true
  end
  function self:refresh()
    if not self.id then return nil, "ENOTCONN" end
    local meta, err = call("frame")
    if not meta then return nil, err end
    if type(meta.bytes) ~= "number" or meta.bytes % 1 ~= 0 or meta.bytes < 1 or meta.bytes > (config.maxFrameBytes or 600000)
      or type(meta.token) ~= "string" then return nil, "EPROTOCOL" end
    local parts, offset = {}, 1
    while offset <= meta.bytes do
      local size = math.min(4096, meta.bytes - offset + 1)
      local chunk, chunkErr = call("chunk", {token = meta.token, offset = offset, length = size})
      if type(chunk) ~= "string" then return nil, chunkErr or "EPROTOCOL" end
      if #chunk ~= size then return nil, "ETRUNCATED_FRAME" end
      parts[#parts + 1] = chunk; offset = offset + size
    end
    local data = table.concat(parts)
    -- The renderer validates the complete binary frame once before touching GPU.
    local ok, renderErr = deps.renderer:render(data, {maxBytes = config.maxFrameBytes or 600000}, meta)
    if not ok then return nil, renderErr end
    self.status = meta.status
    return true
  end
  function self:input(events)
    if not self.id then return nil, "ENOTCONN" end
    if self.pending then return nil, "EINPUT_PENDING" end
    self.pending = {sequence = self.sequence + 1, events = require("spacecross.core.util").copy(events)}
    return self:retryInput()
  end
  function self:retryInput()
    if not self.pending then return nil, "ENOENT_PENDING" end
    local result, err = call("input", self.pending)
    if not result then return nil, err end
    if result.sequence ~= self.pending.sequence then return nil, "EPROTOCOL" end
    self.sequence, self.pending = result.sequence, nil
    return true
  end
  function self:resize(width, height) return call("resize", {width = width, height = height}) end
  function self:close()
    if not self.id then return true end
    local result, err = call("close"); self.id = nil
    return result, err
  end
  return self
end
return M
