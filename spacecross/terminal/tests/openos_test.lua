local Scope = require("spacecross.terminal.openos_scope")
local Runner = require("spacecross.terminal.openos_runner")
local Input = require("spacecross.terminal.input")
local GPU = require("spacecross.terminal.gpu")
local Platform = require("tests.stubs.platform")
local H = require("tests.support")
local function keyboard_state_is_per_process_and_interrupt_is_private()
  local root, current = {data = {}}
  current = root
  local process = {info = function() return current end}
  local kb = {pressedCodes = {[42] = true}, pressedChars = {[120] = true}}
  Scope.isolateKeyboard(kb, process); Scope.isolateKeyboard(kb, process)
  local child = {data = {sc_terminal_keys = {pressedCodes = {}, pressedChars = {}}}}
  current = child; assert(not kb.pressedCodes[42]); kb.pressedCodes[29] = true
  current = root; assert(not kb.pressedCodes[29] and kb.pressedCodes[42])
  local now, physicalCalls = 0, 0
  local native = {computer = {uptime = function() return now end}}
  local queue = {{"key_down", "virtual", 99, 46, "Owner"}, {"key_down", "virtual", 0, 29, "Owner"}}
  local s = {pull = function() return table.remove(queue, 1) end}
  local physical = {{"key_down", "physical", 98, 48, "Stranger"}, {"interrupted", 0}, {"spacecross_terminal_wake", "another"}, {"modem_message", "card"}}
  local pull = Scope.privatePull(native, s, function()
    now, physicalCalls = now + 0.1, physicalCalls + 1
    return table.unpack(table.remove(physical, 1) or {})
  end, child.data.sc_terminal_keys)
  -- C followed by Control is as safe as the normal modifier order.
  child.data.sc_terminal_keys.pressedCodes[29] = nil
  current = child
  assert(pull(nil, 1) == "key_down")
  assert(pull(nil, 1) == "interrupted" and not kb.pressedCodes[46] and kb.pressedCodes[29])
  assert(pull(nil, 1) == "modem_message" and physicalCalls == 4)
  current = root; assert(not kb.pressedCodes[46] and not kb.pressedCodes[29] and kb.pressedCodes[42])
  queue[1] = {"key_down", "virtual", 3, 46, "Owner"}
  current = child; assert(pull(nil, 0) == "interrupted" and not kb.pressedCodes[46])
  return H.success()
end
local function client_filter_requires_actor_association_and_detaches()
  local input = Input.new("Owner", "screen", {"kb"})
  assert(not input({"key_down", "kb", 97, 30, "Admin"}))
  assert(not input({"key_down", "other-kb", 97, 30, "Owner"}))
  assert(not input({"key_down", "kb", 97, 30}))
  assert(not input({"touch", "other-screen", 1, 1, 0, "Owner"}))
  assert(input({"clipboard", "kb", "hi", "owner"}).text == "hi")
  assert(input({"key_down", "kb", 0, 29, "Owner"}))
  assert(input({"key_down", "kb", 0, 56, "Owner"}))
  local e, action = input({"key_down", "kb", 113, 16, "Owner"})
  assert(not e and action == "detach")
  return H.success()
end
local function nativeStub()
  local p = Platform.new()
  local root = {env = _G, data = {window = {gpu = "physical", keyboard = "physical-kb", x = 3, y = 2}}}
  local current, native, threads = root, {}, {}
  native.root, native.threads = root, threads
  native.process = {info = function() return current end, internal = {}}
  native.component = p.component
  native.keyboard = {pressedCodes = {}, pressedChars = {}}
  native.computer = {uptime = p.clock}
  native.event = p.event
  native.tty = setmetatable({}, {__index = function(_, key) if key == "window" then return current.data.window end end})
  native.term = {internal = {}}
  function native.term.bind(gpu) local w = current.data.window; w.gpu, w.keyboard = gpu, nil end
  function native.term.internal.open(_, _, width, height)
    assert(type(current.data.window.gpu) == "table")
    return {width = width, height = height, gpu = current.data.window.gpu, x = 1, y = 1}
  end
  function native.process.load(program, env)
    assert(program == "/bin/sh")
    native.loadedEnvironment = env
    return function()
      local c = env.require("component")
      assert(c.gpu == current.data.window.gpu and c.getPrimary("keyboard").address == current.data.window.keyboard)
      local count = 0
      for _, kind in c.list() do if kind == "gpu" then count = count + 1 end end
      assert(count == 1)
      c.gpu.set(1, 1, "prompt")
      while true do
        local name, _, char = current.data.pull({}, 10)
        if name == "key_down" then c.gpu.set(1, 2, string.char(char))
        elseif name == "interrupted" then c.gpu.set(1, 3, "cancelled") end
      end
    end
  end
  function native.process.internal.continue(child) return child() end
  native.thread = {}
  function native.thread.create(fn)
    local context = {env = current.env, data = setmetatable({pull = function(_, timeout) return coroutine.yield(timeout) end}, {__index = current.data})}
    local co = coroutine.create(fn)
    local t = {context = context}
    function t:resume(...)
      local previous = current; current = context
      local ok, err = coroutine.resume(co, ...); current = previous
      assert(ok, err)
    end
    function t:status() return self.killed and "dead" or coroutine.status(co) end
    function t:kill() self.killed = true end
    threads[#threads + 1] = t; t:resume(); return t
  end
  return native, p
end
local function openos_runner_two_windows_do_not_touch_root_or_each_other()
  local native, p = nativeStub()
  local runner = Runner.new(native)
  local function session(id)
    local s = {id = id, width = 20, height = 4, keyboard = id .. "-kb", queue = {},
      gpu = GPU.new({width = 20, height = 4, address = id .. "-gpu", screen = id .. "-screen"})}
    function s:pull() return table.remove(self.queue, 1) end
    return s
  end
  local a, b = session("a"), session("b")
  local ha, hb = runner:start(a, "/bin/sh"), runner:start(b, "/bin/sh")
  assert(native.root.data.window.gpu == "physical" and native.root.data.window.keyboard == "physical-kb" and native.root.data.window.x == 3)
  assert(not native.root.data.sc_terminal_keys and a.gpu.get(1, 1) == "p" and b.gpu.get(1, 1) == "p")
  a.queue[1] = {"key_down", a.keyboard, 65, 30, "Owner"}; ha:wake()
  native.threads[1]:resume("spacecross_terminal_wake", a.id)
  assert(a.gpu.get(1, 2) == "A" and b.gpu.get(1, 2) == " ")
  a.queue[1] = {"key_down", a.keyboard, 0, 29, "Owner"}
  a.queue[2] = {"key_down", a.keyboard, 3, 46, "Owner"}
  native.threads[1]:resume("spacecross_terminal_wake", a.id)
  assert(a.gpu.get(1, 3) == "c" and b.gpu.get(1, 3) == " ")
  assert(not native.keyboard.pressedCodes[29] and not native.keyboard.pressedCodes[46])
  for _, signal in ipairs(p.queue) do assert(signal[1] == "spacecross_terminal_wake") end
  ha:resize(10, 3); assert(a.gpu.getResolution() == 10 and native.threads[1].context.data.window.width == 10)
  ha:close(); assert(ha:status() == "closed" and hb:status() == "running")
  hb:close(); return H.success()
end
local function failed_pty_initialization_restores_root()
  local native = nativeStub()
  native.term.internal.open = function() error("unsupported OpenOS") end
  assert(not pcall(Scope.openWindow, native, GPU.new(), 80, 25, "kb"))
  assert(native.root.data.window.gpu == "physical" and native.root.data.window.keyboard == "physical-kb" and native.root.data.window.x == 3)
  return H.success()
end
local all_tests = {
  {test_name = "keyboard_state_is_per_process_and_interrupt_is_private", test = keyboard_state_is_per_process_and_interrupt_is_private},
  {test_name = "client_filter_requires_actor_association_and_detaches", test = client_filter_requires_actor_association_and_detaches},
  {test_name = "openos_runner_two_windows_do_not_touch_root_or_each_other", test = openos_runner_two_windows_do_not_touch_root_or_each_other},
  {test_name = "failed_pty_initialization_restores_root", test = failed_pty_initialization_restores_root},
}
return all_tests
