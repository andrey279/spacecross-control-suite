local GPU = require("spacecross.terminal.gpu")
local Frame = require("spacecross.terminal.frame")
local codec = require("spacecross.core.codec")
local M = {}
local function integer(n, low, high) return type(n) == "number" and n % 1 == 0 and n >= low and n <= high end
local function failure(code) return nil, code end
function M.new(deps, config)
  config = config or {}
  local self = {sessions = {}, running = false}
  local timer, count, cells, busy = nil, 0, 0, false
  local reservation = (config.maxWidth or 160) * (config.maxHeight or 50)
  local function log(code, actor) if deps.log then deps.log("info", code, {actor = actor}) end end
  local function owner(actor) return type(actor) == "string" and deps.isOwner(actor) end
  local function remove(s)
    if not self.sessions[s.id] then return end
    self.sessions[s.id] = nil; count = count - 1; cells = cells - reservation
    if s.handle then pcall(s.handle.close, s.handle) end
    s.queue, s.frame = {}, nil; log("TERMINAL_CLOSED", s.actor)
  end
  function self:sweep()
    if busy then return end
    local now = deps.clock()
    for _, s in pairs(self.sessions) do
      if now - s.touched >= (config.idleTTL or 120) or not owner(s.actor) then remove(s) end
    end
  end
  local function session(actor, args)
    if not self.running then return failure("ESHUTDOWN") end
    if not owner(actor) then return failure("EACCES") end
    self:sweep()
    local s = type(args.id) == "string" and self.sessions[args.id]
    if not s or s.actor:lower() ~= actor:lower() then return failure("ENOENT_SESSION") end
    s.touched = deps.clock(); return s
  end
  local function dimensions(args)
    return integer(args.width, 1, config.maxWidth or 160) and integer(args.height, 1, config.maxHeight or 50)
  end
  local function dispatch(action, actor, args)
    args = args or {}
    if not self.running then return failure("ESHUTDOWN") end
    if not owner(actor) then return failure("EACCES") end
    self:sweep()
    if action == "open" then
      if not dimensions(args) then return failure("EINVAL_SIZE") end
      local owned = 0
      for _, s in pairs(self.sessions) do if s.actor:lower() == actor:lower() then owned = owned + 1 end end
      if count >= (config.maxSessions or 4) or owned >= (config.maxPerOwner or 2)
        or cells + reservation > (config.maxCells or 16000) then return failure("EBUSY") end
      local id = assert(deps.id())
      if not self.running then return failure("ESHUTDOWN") end
      if not owner(actor) then return failure("EACCES") end
      if self.sessions[id] then return failure("EID_COLLISION") end
      local s = {id = id, actor = actor, width = args.width, height = args.height,
        touched = deps.clock(), queue = {}, queuedBytes = 0, sequence = 0}
      s.gpu = GPU.new({width = s.width, height = s.height, maxWidth = config.maxWidth or 160,
        maxHeight = config.maxHeight or 50, screen = id .. ":screen", address = id .. ":gpu"}, deps.widthOf)
      s.keyboard = id .. ":keyboard"
      function s:pull()
        if self.resizePending then local signal = self.resizePending; self.resizePending = nil; return signal end
        local entry = table.remove(self.queue, 1)
        if not entry then return end
        self.queuedBytes = self.queuedBytes - entry.bytes
        return entry.signal
      end
      self.sessions[id] = s; count = count + 1; cells = cells + reservation
      local ok, handle = pcall(deps.runner.start, deps.runner, s, config.program or "/bin/sh")
      if not ok or not handle then remove(s); return failure("ERR_TERMINAL_START: " .. tostring(handle)) end
      s.handle = handle; log("TERMINAL_OPENED", actor)
      if not self.running or not self.sessions[id] then pcall(handle.close, handle); return failure("ESHUTDOWN") end
      return {id = id, width = s.width, height = s.height, sequence = 0}
    end
    local s, err = session(actor, args); if not s then return nil, err end
    if action == "close" then remove(s); return true end
    if action == "frame" then
      -- One immutable frame per session. An input or output change does not mutate it.
      local now = deps.clock()
      if s.frameAt and now - s.frameAt < (config.frameInterval or 0.1) then return failure("EAGAIN") end
      local data = Frame.encode(s.gpu)
      if #data > (config.maxFrameBytes or 600000) then return failure("EFRAME_TOO_LARGE") end
      local token = deps.id()
      if not self.running or not self.sessions[s.id] then return failure("ESHUTDOWN") end
      s.frame, s.token, s.frameAt = data, token, now
      local w, h = s.gpu.getResolution()
      return {token = s.token, bytes = #data, width = w, height = h,
        generation = s.gpu.generation, status = s.handle:status(), sequence = s.sequence}
    end
    if action == "chunk" then
      if not s.frame or args.token ~= s.token then return failure("ESTALE_FRAME") end
      if not integer(args.offset, 1, #s.frame) or not integer(args.length, 1, 4096) then return failure("EINVAL_CHUNK") end
      return s.frame:sub(args.offset, args.offset + args.length - 1)
    end
    if action == "resize" then
      if not dimensions(args) then return failure("EINVAL_SIZE") end
      -- The runner updates its viewport; no remote method names are evaluated.
      local ok, resizeErr = pcall(s.handle.resize, s.handle, args.width, args.height)
      if not ok then return failure("ERR_RESIZE: " .. tostring(resizeErr)) end
      s.width, s.height = args.width, args.height; s.frame, s.token = nil, nil
      return true
    end
    if action == "input" then
      if not integer(args.sequence, 1, 2147483647) or type(args.events) ~= "table" or #args.events < 1 or #args.events > 32 then return failure("EINVAL_INPUT") end
      local encoded = codec.encode(args.events)
      if #encoded > (config.maxInputBytes or 32768) then return failure("EINPUT_TOO_LARGE") end
      if args.sequence == s.sequence then
        if encoded == s.lastInput then return {sequence = s.sequence} end
        return failure("ESEQUENCE_CONFLICT")
      end
      if args.sequence ~= s.sequence + 1 then return failure("ESEQUENCE") end
      local pending, bytes = {}, 0
      for _, e in ipairs(args.events) do
        if type(e) ~= "table" then return failure("EINVAL_EVENT") end
        local signal
        if e.name == "key_down" or e.name == "key_up" then
          if not integer(e.char, 0, 1114111) or e.char >= 55296 and e.char <= 57343 or not integer(e.code, 0, 255) then return failure("EINVAL_KEY") end
          signal = {e.name, s.keyboard, e.char, e.code, actor}
        elseif e.name == "clipboard" then
          if type(e.text) ~= "string" or #e.text > 4096 then return failure("EINVAL_CLIPBOARD") end
          signal = {e.name, s.keyboard, e.text, actor}
        elseif e.name == "touch" or e.name == "drag" or e.name == "drop" or e.name == "scroll" then
          local w, h = s.gpu.getResolution()
          if not integer(e.x, 1, w) or not integer(e.y, 1, h) or not integer(e.button, e.name == "scroll" and -1 or 0, e.name == "scroll" and 1 or 2)
            or e.name == "scroll" and e.button == 0 then return failure("EINVAL_POINTER") end
          signal = {e.name, s.gpu.getScreen(), e.x, e.y, e.button, actor}
        else return failure("EINVAL_EVENT") end
        local size = #codec.encode(signal)
        pending[#pending + 1] = {signal = signal, bytes = size}; bytes = bytes + size
      end
      if #s.queue + #pending > (config.maxQueue or 256) or s.queuedBytes + bytes > (config.maxInputBytes or 32768) then return failure("EINPUT_FULL") end
      for _, entry in ipairs(pending) do s.queue[#s.queue + 1] = entry end
      s.queuedBytes, s.sequence, s.lastInput = s.queuedBytes + bytes, args.sequence, encoded
      s.handle:wake()
      return {sequence = s.sequence}
    end
    return failure("ENOTSUP")
  end
  function self:request(action, actor, args)
    -- Data Card entropy and native process startup can yield to another RPC.
    if busy then return failure("EBUSY") end
    self:sweep(); busy = true
    local ok, result, err = pcall(dispatch, action, actor, args)
    busy = false
    if not ok then return failure("ERR_TERMINAL: " .. tostring(result)) end
    return result, err
  end
  function self:start()
    if self.running then return false end
    self.running = true
    timer = deps.event.timer(1, function() self:sweep() end, math.huge); return true
  end
  function self:stop()
    if timer then deps.event.cancel(timer); timer = nil end
    for _, s in pairs(self.sessions) do remove(s) end
    self.running = false
  end
  return self
end
return M
