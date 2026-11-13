local Processes = require("spacecross.runtime.processes")
local H = require("tests.support")
local function process_ids_follow_liveness_not_pid_file()
  local processes, current = {}, nil
  local native = {info = function(thread) return processes[thread or current] end}
  local adapter = Processes.new(native)
  local first, second
  local a = coroutine.create(function() first = adapter.pid(); assert(first == adapter.pid()); coroutine.yield() end)
  local b = coroutine.create(function() second = adapter.pid(); coroutine.yield() end)
  processes[a], processes[b] = {data = {}}, {data = {}}
  current = a; assert(coroutine.resume(a)); current = b; assert(coroutine.resume(b))
  assert(first ~= second and adapter.alive(first) and adapter.alive(second))
  processes[a] = nil
  assert(not adapter.alive(first))
  processes[b].data.result = {true}
  return H.truth(not adapter.alive(second))
end
local function stub_namespace_cannot_invalidate_other_process_provider()
  local data = {}
  local native = {info = function() return {data = data} end}
  local live = Processes.new(native)
  local pid = live.pid()
  local fake = Processes.new({info = function() return {data = {}} end})
  fake.pid()
  return H.truth(live.alive(pid) and live.pid() == pid)
end
local all_tests = {
  {test_name = "process_ids_follow_liveness_not_pid_file", test = process_ids_follow_liveness_not_pid_file},
  {test_name = "stub_namespace_cannot_invalidate_other_process_provider", test = stub_namespace_cannot_invalidate_other_process_provider},
}
return all_tests
