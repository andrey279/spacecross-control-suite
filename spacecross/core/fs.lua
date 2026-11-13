-- All disk I/O is injected; this adapter uses OpenOS filesystem or desktop io.
local M = {}
local function quote(path) return "'" .. path:gsub("'", "'\\''") .. "'" end

function M.new(native)
  local fs = {lockIdentity = native or io}
  function fs.read(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local data, readErr = f:read("*a")
    f:close()
    return data, readErr
  end
  function fs.write(path, data)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    local ok, writeErr = f:write(data)
    local closed, closeErr = f:close()
    if not ok then return nil, writeErr end
    if not closed then return nil, closeErr end
    return true
  end
  if native then
    fs.exists, fs.rename, fs.remove = native.exists, native.rename, native.remove
    fs.mkdir = native.makeDirectory
    fs.isDirectory = native.isDirectory
    function fs.list(path)
      local out = {}
      for name in native.list(path) do out[#out + 1] = name:gsub("/$", "") end
      table.sort(out)
      return out
    end
  else
    function fs.exists(path)
      local f = io.open(path, "rb")
      if f then f:close(); return true end
      return false
    end
    fs.rename, fs.remove = os.rename, os.remove
    function fs.mkdir(path)
      local ok = os.execute("mkdir -p -- " .. quote(path))
      return ok == true or ok == 0
    end
    function fs.list(path)
      local f = assert(io.popen("find " .. quote(path) .. " -mindepth 1 -maxdepth 1 -printf '%f\\n'"))
      local out = {}
      for name in f:lines() do out[#out + 1] = name end
      f:close()
      table.sort(out)
      return out
    end
    function fs.isDirectory(path)
      local ok = os.execute("test -d " .. quote(path))
      return ok == true or ok == 0
    end
  end
  function fs.atomicWrite(path, data)
    local ok, err = fs.write(path .. ".new", data)
    if not ok then return nil, err end
    return fs.rename(path .. ".new", path)
  end
  return fs
end
return M
