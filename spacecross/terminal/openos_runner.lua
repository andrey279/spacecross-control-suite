local Scope = require("spacecross.terminal.openos_scope")
local M = {}
function M.new(native)
  native = native or {term = require("term"), tty = require("tty"), thread = require("thread"),
    process = require("process"), keyboard = require("keyboard"), computer = require("computer"),
    event = require("event"), component = require("component")}
  assert(native.process.load and native.process.internal and native.process.internal.continue, "OpenOS process API unavailable")
  Scope.isolateKeyboard(native.keyboard, native.process)
  local self = {}
  function self:start(session, program)
    assert(type(program) == "string" and program:sub(1, 1) == "/", "absolute terminal program path required")
    local window = Scope.openWindow(native, session.gpu, session.width, session.height, session.keyboard)
    local handle, status = {}, "running"
    local thread = native.thread.create(function()
      local data = native.process.info().data
      data.window = window
      for _, field in ipairs({"vars", "aliases"}) do
        local copy = {}
        for key, value in pairs(data[field] or {}) do copy[key] = value end
        data[field] = copy
      end
      data.sc_terminal_keys = {pressedCodes = {}, pressedChars = {}}
      data.pull = Scope.privatePull(native, session, assert(data.pull), data.sc_terminal_keys)
      local env = setmetatable({}, {__index = native.process.info().env or _G})
      local component = Scope.component(native, session)
      function env.require(name) if name == "component" then return component end; return require(name) end
      env._G = env
      local ok, result = pcall(function()
        local child = assert(native.process.load(program, env))
        return native.process.internal.continue(child)
      end)
      if not ok then
        pcall(session.gpu.set, 1, 1, ("Terminal error: " .. tostring(result)):gsub("[\r\n]", " "):sub(1, 140))
        status = "failed"
      elseif result == false or type(result) == "number" and result ~= 0 then status = "failed"
      else status = "exited" end
    end)
    function handle:status()
      if status == "running" and thread:status() == "dead" then return "exited" end
      return status
    end
    function handle:wake() native.event.push("spacecross_terminal_wake", session.id) end
    function handle:resize(width, height)
      session.gpu.setResolution(width, height)
      window.width, window.height = width, height
      window.x, window.y = math.min(window.x or 1, width), math.min(window.y or 1, height)
      session.resizePending = {"screen_resized", session.gpu.getScreen()}
      self:wake()
    end
    function handle:close() if thread:status() ~= "dead" then thread:kill() end; status = "closed" end
    return handle
  end
  return self
end
return M
