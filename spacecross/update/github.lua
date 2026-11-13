local util = require("spacecross.core.util")
local M = {}
-- request(url, maxBytes) must return body or nil,error after verifying HTTP status.
function M.new(request, repository)
  assert(type(repository) == "string" and repository:match("^[%w_.%-]+/[%w_.%-]+$"), "invalid GitHub repository")
  local self = {}
  function self.latest()
    local body, err = request("https://api.github.com/repos/" .. repository .. "/git/ref/heads/main", 16384)
    if not body then return nil, err end
    -- A branch ref contains one object SHA and avoids potentially huge commit bodies.
    local sha = body:match('"sha"%s*:%s*"(%x+)"')
    if not sha or #sha ~= 40 then return nil, "INVALID_GITHUB_COMMIT" end
    return sha
  end
  function self.fetch(revision, path)
    if type(revision) ~= "string" or #revision ~= 40 or not revision:match("^%x+$")
        or not util.relativePath(path) then return nil, "EINVAL_SOURCE" end
    return request("https://raw.githubusercontent.com/" .. repository .. "/" .. revision .. "/" .. path, 1024 * 1024)
  end
  function self.files(revision)
    local body, err = self.fetch(revision, "install.list")
    if not body then return nil, err end
    local result, seen = {}, {}
    for line in body:gmatch("[^\r\n]+") do
      if not util.relativePath(line) or seen[line] then return nil, "INVALID_INSTALL_LIST" end
      result[#result + 1], seen[line] = line, true
    end
    if #result == 0 then return nil, "EMPTY_INSTALL_LIST" end
    return result
  end
  function self.manifest(revision)
    if type(revision) ~= "string" or #revision ~= 40 or not revision:match("^%x+$") then return nil, "EINVAL_SOURCE" end
    return request("https://github.com/" .. repository .. "/releases/download/spacecross-" .. revision .. "/components.sc", 131072)
  end
  return self
end
return M
