local Service = require("spacecross.terminal.service")
local Client = require("spacecross.terminal.client")
local Renderer = require("spacecross.terminal.renderer")
local GPU = require("spacecross.terminal.gpu")
local Frame = require("spacecross.terminal.frame")
local Runner = require("spacecross.terminal.tests.stubs.runner")
local Platform = require("tests.stubs.platform")
local System = require("spacecross.rpc.tests.stubs.system")
local H = require("tests.support")
local function new(p, config)
  p = p or Platform.new(); local serial = 0
  p.id = function() serial = serial + 1; return "session-" .. serial end
  p.isOwner = function(actor) return actor:lower() == "owner" or actor == "Other" end
  p.runner = Runner.new()
  local s = Service.new(p, config); s:start(); return s, p
end
local function owner_sessions_input_atomicity_and_duplicate_sequence()
  local s, p = new()
  assert(select(2, s:request("open", "Admin", {width = 10, height = 3, player = "Owner"})) == "EACCES")
  local a = assert(s:request("open", "Owner", {width = 10, height = 3}))
  local b = assert(s:request("open", "Other", {width = 10, height = 3}))
  assert(select(2, s:request("close", "Other", a)) == "ENOENT_SESSION")
  local args = {id = a.id, sequence = 1, events = {{name = "key_down", char = 65, code = 30, player = "Other"}, {name = "clipboard", text = "hello"}}}
  assert(s:request("input", "Owner", args)); assert(s:request("input", "Owner", args))
  local session = p.runner.sessions[a.id]
  assert(#session.queue == 2 and #p.runner.sessions[b.id].queue == 0)
  local event = session:pull(); assert(event[5] == "Owner" and event[2] == session.keyboard)
  args.events[1].char = 66
  assert(select(2, s:request("input", "Owner", args)) == "ESEQUENCE_CONFLICT")
  args.sequence = 2; args.events[2] = {name = "shell", command = "bad"}
  assert(select(2, s:request("input", "Owner", args)) == "EINVAL_EVENT" and #session.queue == 1)
  assert(s:request("close", "Owner", a)); assert(session.handle.closed)
  s:stop(); assert(p.runner.sessions[b.id].handle.closed)
  return H.success()
end
local function limits_ttl_revocation_and_pinned_frame()
  local s, p = new(nil, {maxSessions = 1, idleTTL = 4, maxQueue = 1})
  local a = assert(s:request("open", "Owner", {width = 80, height = 25}))
  assert(select(2, s:request("open", "Other", {width = 1, height = 1})) == "EBUSY")
  local meta = assert(s:request("frame", "Owner", a))
  p.runner.sessions[a.id].gpu.set(1, 1, "new output")
  local chunk = assert(s:request("chunk", "Owner", {id = a.id, token = meta.token, offset = 1, length = 4096}))
  local frame = assert(Frame.decode(chunk)); assert(frame.width == 80)
  assert(require("spacecross.terminal.cell").unpack(frame.cells[1]) == "r")
  assert(select(2, s:request("chunk", "Owner", {id = a.id, token = "wrong", offset = 1, length = 1})) == "ESTALE_FRAME")
  local input = {id = a.id, sequence = 1, events = {{name = "clipboard", text = "one"}, {name = "clipboard", text = "two"}}}
  assert(select(2, s:request("input", "Owner", input)) == "EINPUT_FULL" and #p.runner.sessions[a.id].queue == 0)
  p:advance(4); assert(not next(s.sessions) and p.runner.sessions[a.id].handle.closed)
  local b = assert(s:request("open", "Owner", {width = 1, height = 1}))
  p.isOwner = function() return false end; p:advance(1)
  assert(not next(s.sessions) and p.runner.sessions[b.id].handle.closed)
  s:stop(); return H.success()
end
local function rpc_paged_terminal_fresh_frames_and_retry_input()
  local f, a, b = System.new()
  local service, p = new(b)
  b.dispatch = function(model, action, actor, args)
    assert(model == "terminal"); return service:request(action, actor, args)
  end
  local display = GPU.new({width = 80, height = 25})
  local client = Client.new({rpc = a.rpc, renderer = Renderer.new(display)}, {host = "server", actor = "Owner"})
  assert(client:open(80, 25)); assert(client:refresh()); assert(display.get(1, 1) == "r")
  local serverGPU = p.runner.sessions[client.id].gpu
  for y = 1, 25 do for x = 1, 80 do serverGPU.setForeground(x * 80 + y); serverGPU.set(x, y, "Ж") end end
  assert(#Frame.encode(serverGPU) > 20000)
  f:advance(0.2); assert(client:refresh()); assert(display.get(1, 1) == "Ж" and display.get(80, 25) == "Ж")
  local original = a.rpc.request; local lost = true
  a.rpc.request = function(self, host, model, action, actor, args, card)
    local result, err = original(self, host, model, action, actor, args, card)
    if action == "input" and lost then lost = false; return nil, "ETIMEDOUT" end
    return result, err
  end
  assert(not client:input({{name = "key_down", char = 65, code = 30}}))
  assert(client:retryInput() and #service.sessions[client.id].queue == 1)
  assert(client:resize(20, 4)); f:advance(0.2); assert(client:refresh() and display.getResolution() == 20)
  assert(client:close() and not next(service.sessions))
  service:stop(); a.rpc:stop(); b.rpc:stop()
  return H.success()
end
local function yielding_entropy_cannot_overbook_or_survive_shutdown()
  local s, p = new(nil, {maxSessions = 1})
  local id = p.id
  p.id = function()
    assert(select(2, s:request("open", "Owner", {width = 1, height = 1})) == "EBUSY")
    return id()
  end
  local a = assert(s:request("open", "Owner", {width = 10, height = 3}))
  s:request("close", "Owner", a)
  p.id = function() s:stop(); return id() end
  assert(select(2, s:request("open", "Owner", {width = 10, height = 3})) == "ESHUTDOWN" and not next(s.sessions))
  s:start(); p.id = id
  local start = p.runner.start
  p.runner.start = function(runner, session, program)
    local h = start(runner, session, program); s:stop(); return h
  end
  assert(select(2, s:request("open", "Owner", {width = 10, height = 3})) == "ESHUTDOWN")
  for _, session in pairs(p.runner.sessions) do assert(session.handle == nil or session.handle.closed) end
  return H.success()
end
local function broken_frame_transfer_never_draws_partial_output()
  local s, p = new()
  local requests, renderCalls = 0, 0
  local rpc = {request = function(_, _, _, action, actor, args)
    requests = requests + 1
    if action == "chunk" and args.offset > 1 then return nil, "NETWORK_DOWN" end
    return s:request(action, actor, args)
  end}
  local client = Client.new({rpc = rpc, renderer = {render = function() renderCalls = renderCalls + 1 end}}, {host = "ship", actor = "Owner"})
  assert(client:open(80, 25))
  local gpu = p.runner.sessions[client.id].gpu
  for x = 1, 80 do for y = 1, 25 do gpu.setForeground(x * 25 + y); gpu.set(x, y, "x") end end
  local ok, err = client:refresh()
  assert(not ok and err == "NETWORK_DOWN" and renderCalls == 0 and requests >= 4)
  assert(client:close()); s:stop(); return H.success()
end
local all_tests = {
  {test_name = "owner_sessions_input_atomicity_and_duplicate_sequence", test = owner_sessions_input_atomicity_and_duplicate_sequence},
  {test_name = "limits_ttl_revocation_and_pinned_frame", test = limits_ttl_revocation_and_pinned_frame},
  {test_name = "rpc_paged_terminal_fresh_frames_and_retry_input", test = rpc_paged_terminal_fresh_frames_and_retry_input},
  {test_name = "yielding_entropy_cannot_overbook_or_survive_shutdown", test = yielding_entropy_cannot_overbook_or_survive_shutdown},
  {test_name = "broken_frame_transfer_never_draws_partial_output", test = broken_frame_transfer_never_draws_partial_output},
}
return all_tests
