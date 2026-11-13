local M = {}

function M.copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  assert(not seen[value], "cyclic table")
  seen[value] = true
  local result = {}
  for k, v in pairs(value) do result[M.copy(k, seen)] = M.copy(v, seen) end
  seen[value] = nil
  return result
end

function M.sortedKeys(value)
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

function M.set(values)
  local result = {}
  for _, value in ipairs(values or {}) do result[value] = true end
  return result
end

function M.relativePath(path)
  if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/"
      or path:find("[^%w_./%-]") or path:find("//", 1, true) then return false end
  for part in path:gmatch("[^/]+") do
    if part == "." or part == ".." then return false end
  end
  return path:sub(-1) ~= "/"
end

function M.check(ok, err)
  if not ok then error(err or "operation failed", 2) end
  return ok
end

return M
