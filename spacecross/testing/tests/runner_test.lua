local Runner = require("spacecross.testing.runner")
local H = require("tests.support")
local function distinguishes_crash_failure_success_and_bad_contract()
  local function good() return {status = true} end
  local function failed() return {status = false, error_code = "expected failure"} end
  local function crashed() error("expected crash") end
  local function malformed() return true end
  local rows, stats = Runner.run({{file = "example.lua", load = function() return {
    {test_name = "good", test = good}, {test_name = "failed", test = failed},
    {test_name = "crashed", test = crashed}, {test_name = "malformed", test = malformed},
  } end}})
  assert(#rows == 4 and stats.success == 1 and stats.failed == 2 and stats.crashed == 1)
  local output = ""
  Runner.print(rows, stats, function(s) output = output .. s end, true)
  assert(output:find(" | \27[32msuccess\27[0m | Success", 1, true))
  assert(output:find(" | \27[33mfailed\27[0m | expected failure", 1, true))
  assert(output:find(" | \27[31mcrashed\27[0m |", 1, true))
  return H.equal(stats.total, 4)
end
local function filters_files_and_reports_load_crash()
  local rows, stats = Runner.run({
    {file = "skip.lua", load = function() error("must not run") end},
    {file = "chosen.lua", load = function() error("broken syntax") end},
  }, function(path) return path == "chosen.lua" end)
  return H.truth(#rows == 1 and stats.crashed == 1 and rows[1].name == "<load>")
end
local all_tests = {
  {test_name = "distinguishes_crash_failure_success_and_bad_contract", test = distinguishes_crash_failure_success_and_bad_contract},
  {test_name = "filters_files_and_reports_load_crash", test = filters_files_and_reports_load_crash},
}
return all_tests
