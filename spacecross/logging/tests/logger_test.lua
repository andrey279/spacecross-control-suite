local P = require("tests.stubs.platform")
local Logger = require("spacecross.logging.logger")
local Crypto = require("spacecross.logging.tests.stubs.crypto")
local H = require("tests.support")
local function offline_queue_is_encrypted_and_acknowledged()
  local p = P.new(); p.crypto = Crypto
  p.upload = function() return nil end
  local logger = Logger.new(p, {root = "/logs"}); logger:start()
  logger:write("critical", "ALERT", {secret = "captured player"})
  assert(next(p.files) == nil)
  p:advance(1)
  local name
  for _, entry in ipairs(p.fs.list("/logs")) do if entry:match("%.sealed$") then name = entry end end
  assert(name and p.files["/logs/" .. name]:sub(1, 12) == "TEST-SEALED:")
  assert(not p.files["/logs/" .. name]:find("captured player", 1, true))
  logger:stop()
  -- Simulate restart: persistent spool is rediscovered, not kept only in RAM.
  local restarted = Logger.new(p, {root = "/logs"})
  p.upload = function(id) return "wrong-id" end
  restarted:flush(); assert(p.files["/logs/" .. name])
  p.upload = function(id) return id end
  restarted:flush()
  return H.equal(#p.fs.list("/logs"), 1) -- non-secret monotonic sequence metadata
end
local function no_card_never_writes_plaintext()
  local p = P.new(); local logger = Logger.new(p, {root = "/logs", maxQueue = 2})
  logger:write("info", "ONE"); logger:write("info", "TWO")
  local ok, err = logger:write("info", "THREE")
  assert(not ok and err == "ENOBUFS" and logger.dropped == 1)
  local flushed, reason = logger:flush()
  assert(not flushed and reason == "ENCRYPTION_UNAVAILABLE")
  assert(next(p.files) == nil and #logger.queue == 2)
  p.crypto = Crypto; assert(logger:flush())
  return H.equal(#p.fs.list("/logs"), 3)
end
local function disk_failure_retains_record()
  local p = P.new(); p.crypto = Crypto
  local logger = Logger.new(p, {root = "/logs"})
  logger:write("error", "FAULT")
  p.fail = function(operation) return operation == "rename" end
  assert(not logger:flush() and #logger.queue == 1)
  p.fail = nil; assert(logger:flush())
  assert(#logger.queue == 0)
  local sealed = 0
  for _, name in ipairs(p.fs.list("/logs")) do if name:match("%.sealed$") then sealed = sealed + 1 end end
  return H.equal(sealed, 1)
end
local function uploader_reentrancy_does_not_resend_or_delete_wrong_file()
  local p = P.new(); p.crypto = Crypto
  local logger = Logger.new(p, {root = "/logs"})
  local uploads = 0
  p.upload = function(id)
    uploads = uploads + 1
    local ok, err = logger:flush()
    assert(not ok and err == "EBUSY")
    return id
  end
  logger:write("info", "EVENT"); assert(logger:flush())
  return H.equal(uploads, 1)
end
local function async_pending_filename_precedes_new_lexical_neighbors()
  local p = P.new(); p.crypto = Crypto
  local logger = Logger.new(p, {root = "/logs"})
  local pending, acknowledged = nil, false
  p.upload = function(name)
    if not pending then pending = name; return nil end
    assert(name == pending, "pending upload was starved by a new file")
    acknowledged = true; return name
  end
  p.files["/logs/node-2.sealed"] = "sealed old data"
  logger:flush(); assert(pending == "node-2.sealed")
  p.files["/logs/node-10.sealed"] = "sealed new data"
  logger:flush(nil, 1)
  assert(acknowledged and not p.files["/logs/node-2.sealed"] and p.files["/logs/node-10.sealed"])
  return H.success()
end
local function timer_flush_work_is_bounded_but_explicit_flush_drains()
  local p = P.new(); p.crypto = Crypto
  local logger = Logger.new(p, {root = "/logs", maxRecordsPerTick = 2})
  for _ = 1, 7 do logger:write("info", "EVENT") end
  logger:start(); p:advance(1)
  assert(#logger.queue == 5)
  assert(logger:flush() and #logger.queue == 0); logger:stop()
  return H.success()
end
local all_tests = {
  {test_name = "offline_queue_is_encrypted_and_acknowledged", test = offline_queue_is_encrypted_and_acknowledged},
  {test_name = "no_card_never_writes_plaintext", test = no_card_never_writes_plaintext},
  {test_name = "disk_failure_retains_record", test = disk_failure_retains_record},
  {test_name = "uploader_reentrancy_does_not_resend_or_delete_wrong_file", test = uploader_reentrancy_does_not_resend_or_delete_wrong_file},
  {test_name = "async_pending_filename_precedes_new_lexical_neighbors", test = async_pending_filename_precedes_new_lexical_neighbors},
  {test_name = "timer_flush_work_is_bounded_but_explicit_flush_drains", test = timer_flush_work_is_bounded_but_explicit_flush_drains},
}
return all_tests
