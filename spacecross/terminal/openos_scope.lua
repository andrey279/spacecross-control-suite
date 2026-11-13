-- Compatibility with the stock OpenOS PTY and thread scheduler. No disk patches.
local M = {}
local installed = setmetatable({}, {__mode = "k"})
-- Lua 5.2 has table.unpack but not table.pack; preserve nils and arity.
local pack = table.pack or function(...)
  return {n = select("#", ...), ...}
end
function M.isolateKeyboard(keyboard, process)
  if installed[keyboard] then return end
  for _, field in ipairs({"pressedChars", "pressedCodes"}) do
    local physical = keyboard[field]
    local function target()
      local info = process.info()
      local private = info and info.data.sc_terminal_keys
      return private and private[field] or physical
    end
    keyboard[field] = setmetatable({}, {
      __index = function(_, k) return target()[k] end,
      __newindex = function(_, k, v) target()[k] = v end,
      __pairs = function() return pairs(target()) end,
    })
  end
  installed[keyboard] = true
end
function M.openWindow(native, gpu, width, height, keyboard)
  assert(native.term.internal and native.term.internal.open, "OpenOS PTY API unavailable")
  local root, saved = native.tty.window, {}
  assert(type(root) == "table", "OpenOS root terminal unavailable")
  for k, v in pairs(root) do saved[k] = v end
  -- term.internal.open also works headless when its temporary root GPU is virtual.
  -- All GPU methods here are in memory; this critical section does not yield.
  local ok, window = pcall(function()
    native.term.bind(gpu)
    return native.term.internal.open(0, 0, width, height)
  end)
  for k in pairs(root) do root[k] = nil end
  for k, v in pairs(saved) do root[k] = v end
  if not ok then error(window, 0) end
  window.gpu, window.keyboard = gpu, keyboard
  return window
end
local inputNames = {key_down = true, key_up = true, clipboard = true,
  touch = true, drag = true, drop = true, scroll = true, interrupted = true}
function M.privatePull(native, session, original, keys)
  return function(tbl, timeout)
    local deadline = native.computer.uptime() + (timeout or math.huge)
    while true do
      local signal = session:pull()
      if signal then
        if signal[1] == "key_down" or signal[1] == "key_up" then
          local down = signal[1] == "key_down" and true or nil
          keys.pressedChars[signal[3]], keys.pressedCodes[signal[4]] = down, down
          local ctrl = keys.pressedCodes[29] or keys.pressedCodes[157]
          if down and (signal[3] == 3 or ctrl and keys.pressedCodes[46]) then
            -- Native event would push Ctrl+C globally. Deliver it only here.
            keys.pressedCodes[46] = nil
            keys.pressedChars[3], keys.pressedChars[99], keys.pressedChars[67] = nil, nil, nil
            return "interrupted", native.computer.uptime()
          end
        end
        return table.unpack(signal)
      end
      local remaining = deadline - native.computer.uptime()
      if remaining < 0 then return end
      local event = pack(original(tbl, remaining))
      if not event[1] then return end
      if not inputNames[event[1]] and event[1] ~= "spacecross_terminal_wake" then return table.unpack(event, 1, event.n) end
      -- Physical keyboard and other sessions' input never enter this process.
    end
  end
end
function M.component(native, session)
  local source, gpu = native.component, session.gpu
  local screen = {address = gpu.getScreen(), type = "screen", getKeyboards = function() return {session.keyboard} end,
    isOn = function() return true end, turnOn = function() return true end, turnOff = function() return true end}
  local keyboard = {address = session.keyboard, type = "keyboard"}
  local proxies = {[gpu.address] = gpu, [screen.address] = screen, [session.keyboard] = keyboard}
  local wrapper = setmetatable({gpu = gpu, screen = screen, keyboard = keyboard}, {__index = source})
  function wrapper.proxy(address) return proxies[address] or source.proxy(address) end
  function wrapper.getPrimary(kind) if kind == "gpu" then return gpu elseif kind == "screen" then return screen elseif kind == "keyboard" then return keyboard end; return source.getPrimary(kind) end
  function wrapper.isAvailable(kind) return kind == "gpu" or kind == "screen" or kind == "keyboard" or source.isAvailable(kind) end
  function wrapper.invoke(address, method, ...) if proxies[address] then return assert(proxies[address][method], "unsupported virtual method")(...) end; return source.invoke(address, method, ...) end
  function wrapper.type(address) return proxies[address] and proxies[address].type or source.type(address) end
  function wrapper.list(filter, exact)
    local list = {}
    for address, kind in source.list(filter, exact) do if kind ~= "gpu" and kind ~= "screen" and kind ~= "keyboard" then list[address] = kind end end
    for address, proxy in pairs(proxies) do
      if not filter or (exact and proxy.type == filter or not exact and proxy.type:find(filter, 1, true)) then list[address] = proxy.type end
    end
    local key
    return setmetatable(list, {__call = function() key = next(list, key); if key then return key, list[key] end end})
  end
  return wrapper
end
return M
