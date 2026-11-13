local M = {}
local valid = {success = true, failed = true, crashed = true}

function M.run(suites, filter)
  local rows, stats = {}, {total = 0, success = 0, failed = 0, crashed = 0}
  local function add(file, name, status, detail)
    assert(valid[status])
    stats.total, stats[status] = stats.total + 1, stats[status] + 1
    rows[#rows + 1] = {file = file, name = name, status = status, detail = tostring(detail)}
  end
  for _, suite in ipairs(suites) do
    if not filter or filter(suite.file) then
      local ok, tests = pcall(suite.load)
      if not ok then add(suite.file, "<load>", "crashed", tests)
      elseif type(tests) ~= "table" or #tests == 0 then
        add(suite.file, "<contract>", "failed", "suite must return nonempty all_tests")
      else
        local names = {}
        for index, item in ipairs(tests) do
          if type(item) ~= "table" or type(item.test_name) ~= "string" or type(item.test) ~= "function"
              or names[item.test_name] then
            add(suite.file, "<contract " .. index .. ">", "failed", "invalid/duplicate test declaration")
          else
            names[item.test_name] = true
            local success, result = pcall(item.test)
            if not success then add(suite.file, item.test_name, "crashed", result)
            elseif type(result) ~= "table" or type(result.status) ~= "boolean"
                or (not result.status and type(result.error_code) ~= "string")
                or (result.status and result.error_code ~= nil) then
              add(suite.file, item.test_name, "failed", "invalid result contract")
            elseif result.status then add(suite.file, item.test_name, "success", "Success")
            else add(suite.file, item.test_name, "failed", result.error_code) end
          end
        end
      end
    end
  end
  return rows, stats
end

function M.print(rows, stats, output, color)
  output = output or io.write
  local colors = {success = "\27[32m", failed = "\27[33m", crashed = "\27[31m"}
  local function clean(value) return tostring(value):gsub("[%z\1-\31\127]", " ") end
  output("File | Test | Status | Detail\n")
  for _, row in ipairs(rows) do
    local status = color and colors[row.status] .. row.status .. "\27[0m" or row.status
    output(clean(row.file) .. " | " .. clean(row.name) .. " | " .. status .. " | " .. clean(row.detail) .. "\n")
  end
  output(string.format("Total: %d; Success: %d; Failed: %d; Crashed: %d\n", stats.total, stats.success, stats.failed, stats.crashed))
end
return M
