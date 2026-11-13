local M = {}
function M.success() return {status = true} end
function M.equal(actual, expected, message)
  if actual ~= expected then return {status = false, error_code = (message or "not equal") ..
    ": expected " .. tostring(expected) .. ", got " .. tostring(actual)} end
  return M.success()
end
function M.truth(value, message)
  return value and M.success() or {status = false, error_code = message or "expected truthy value"}
end
return M
