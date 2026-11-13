local M = {}
function M.pair()
  local a, b = {buffer = "", closed = false, writes = 0}, {buffer = "", closed = false, writes = 0}
  local function endpoint(own, other)
    local s = {}
    function s.finishConnect() return not own.connecting end
    function s.close() own.closed = true end
    function s.read(n)
      if #own.buffer == 0 and other.closed then return nil end
      local size = math.min(n, own.readSize or 8192, #own.buffer)
      local value = own.buffer:sub(1, size); own.buffer = own.buffer:sub(size + 1); return value
    end
    function s.write(data)
      assert(not own.closed and not other.closed, "socket closed")
      local size = math.min(#data, own.writeSize or 8192)
      other.buffer = other.buffer .. data:sub(1, size); own.writes = own.writes + 1; return size
    end
    return s
  end
  return endpoint(a, b), endpoint(b, a), a, b
end
return M
