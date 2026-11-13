local Mutex = require("spacecross.core.mutex")
local P = require("tests.stubs.platform")
local H = require("tests.support")
local function live_process_is_busy_and_dead_lock_is_reclaimed()
  local p = P.new(); p.fs.mkdir("/tmp")
  local a, b = Mutex.new(p, "/tmp/mutex-live.lock"), Mutex.new(p, "/tmp/mutex-live.lock")
  assert(a:acquire() and p.files["/tmp/mutex-live.lock"] == "1")
  p.processId, p.liveProcesses[2] = 2, true
  local ok, err = b:acquire(); assert(not ok and err == "EBUSY")
  p.liveProcesses[1] = nil
  assert(b:acquire() and p.files["/tmp/mutex-live.lock"] == "2")
  assert(not a:release())
  assert(b:release())
  return H.truth(not p.fs.exists("/tmp/mutex-live.lock"))
end
local function malformed_or_unreadable_lock_is_not_overwritten()
  local p = P.new(); p.fs.mkdir("/tmp")
  local path = "/tmp/mutex-corrupt.lock"
  p.files[path] = "unknown owner"
  local lock = Mutex.new(p, path)
  local ok, err = lock:acquire()
  assert(not ok and err == "ECORRUPT_LOCK" and p.files[path] == "unknown owner")
  p.files[path] = "1"
  p.fail = function(operation) return operation == "read" end
  assert(not lock:acquire())
  p.fail = nil; p.files[path] = nil
  assert(lock:acquire()); assert(lock:release())
  return H.success()
end
local function reserves_before_yielding_disk_io()
  local p = P.new(); p.fs.mkdir("/tmp")
  local path = "/tmp/mutex-reentrant.lock"
  local a, b = Mutex.new(p, path), Mutex.new(p, path)
  local attempted = false
  p.fail = function(operation)
    if operation == "read" and not attempted then
      attempted = true
      local ok, err = b:acquire(); assert(not ok and err == "EBUSY")
    end
  end
  assert(a:acquire()); assert(a:release())
  return H.truth(attempted)
end
local all_tests = {
  {test_name = "live_process_is_busy_and_dead_lock_is_reclaimed", test = live_process_is_busy_and_dead_lock_is_reclaimed},
  {test_name = "malformed_or_unreadable_lock_is_not_overwritten", test = malformed_or_unreadable_lock_is_not_overwritten},
  {test_name = "reserves_before_yielding_disk_io", test = reserves_before_yielding_disk_io},
}
return all_tests
