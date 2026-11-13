-- Protocol tests only. Deliberately not cryptography; never installed as a provider.
local M = {}
function M.new(key)
  local counter = 0
  return {
    sha256 = function(data)
      local state = 7
      for i = 1, #data do state = (state * 131 + data:byte(i)) % 2147483647 end
      local out = {}
      for i = 1, 32 do state = (state * 131 + i) % 2147483647; out[i] = string.char(state % 256) end
      return table.concat(out)
    end,
    sign = function(data) return "TESTSIG:" .. key .. ":" .. data end,
    verify = function(public, data, signature) return signature == "TESTSIG:" .. public .. ":" .. data end,
    random = function(length)
      counter = counter + 1
      return (key .. ":" .. counter .. string.rep("~", length)):sub(1, length)
    end,
  }
end
return M
