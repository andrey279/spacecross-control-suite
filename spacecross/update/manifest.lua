local codec = require("spacecross.core.codec")
local util = require("spacecross.core.util")
local M = {}
local function sha(value) return type(value) == "string" and #value == 40 and value:match("^%x+$") end
local function array(value, maximum)
  assert(type(value) == "table" and #value <= maximum, "invalid array")
  local n, seen = 0, {}
  for i, v in pairs(value) do
    assert(type(i) == "number" and i % 1 == 0 and i >= 1 and i <= #value and type(v) == "string" and not seen[v], "invalid array entry")
    seen[v], n = true, n + 1
  end
  assert(n == #value, "sparse array"); return value
end
function M.digest(hash, data)
  local raw = hash(data)
  assert(type(raw) == "string" and #raw == 32, "SHA256 provider must return 32 raw bytes")
  return (raw:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
function M.decode(raw, revision)
  local ok, value = pcall(function()
    local m = assert(codec.decode(raw, 131072))
    assert(m.v == 1 and sha(m.revision) and (not revision or revision == m.revision), "invalid manifest revision")
    assert(type(m.components) == "table" and type(m.files) == "table", "invalid manifest maps")
    for k in pairs(m) do assert(k == "v" or k == "revision" or k == "components" or k == "files", "unknown manifest field") end
    local owned, total, count, components = {}, 0, 0, 0
    for name, c in pairs(m.components) do
      components = components + 1
      assert(type(name) == "string" and #name <= 64 and name:match("^[%w_-]+$") and type(c) == "table" and sha(c.version), "invalid component")
      for k in pairs(c) do assert(k == "version" or k == "files" or k == "requires", "unknown component field") end
      array(c.files, 4096); array(c.requires, 64)
      for _, path in ipairs(c.files) do assert(not owned[path], "file owned twice"); owned[path] = name end
    end
    assert(components >= 1 and components <= 64 and m.components.Core, "Core component required")
    for path, f in pairs(m.files) do
      count = count + 1
      assert(util.relativePath(path) and path:match("%.lua$") and owned[path] and type(f) == "table", "invalid manifest path")
      assert(type(f.size) == "number" and f.size % 1 == 0 and f.size >= 0 and f.size <= 1048576
        and type(f.sha256) == "string" and #f.sha256 == 64 and f.sha256:match("^[0-9a-f]+$"), "invalid file hash/size")
      for k in pairs(f) do assert(k == "size" or k == "sha256", "unknown file field") end
      total = total + f.size
    end
    assert(count >= 1 and count <= 4096 and total <= 16777216, "manifest resource limit")
    for path in pairs(owned) do assert(m.files[path], "missing file metadata") end
    local visiting, done = {}, {}
    local function visit(name)
      assert(m.components[name], "unknown dependency")
      assert(not visiting[name], "dependency cycle")
      if done[name] then return end
      visiting[name] = true
      for _, dep in ipairs(m.components[name].requires) do visit(dep) end
      visiting[name], done[name] = nil, true
    end
    for name in pairs(m.components) do visit(name) end
    return m
  end)
  if not ok then return nil, tostring(value) end
  return value
end
function M.select(m, roots)
  roots = roots or util.sortedKeys(m.components)
  array(roots, 64)
  local chosen, paths = {}, {}
  local function add(name)
    local c = assert(m.components[name], "unknown selected component: " .. tostring(name))
    if chosen[name] then return end
    chosen[name] = true
    for _, dep in ipairs(c.requires) do add(dep) end
    for _, path in ipairs(c.files) do paths[path] = true end
  end
  add("Core")
  for _, name in ipairs(roots) do add(name) end
  return util.sortedKeys(chosen), util.sortedKeys(paths)
end
function M.verify(hash, metadata, data)
  return type(data) == "string" and #data == metadata.size and M.digest(hash, data) == metadata.sha256
end
function M.current(fs, root)
  local generation, err = fs.read(root .. "/active")
  if not generation then assert(not fs.exists(root .. "/active"), err or "unreadable active pointer"); return {} end
  assert(#generation <= 80 and generation:match("^[%w_-]+$"), "invalid active generation")
  local directory = root .. "/releases/" .. generation
  local raw = fs.read(directory .. "/COMPONENTS")
  local result = {generation = generation, directory = directory}
  if raw then
    result.manifest = assert(M.decode(raw))
    result.selected = array(assert(codec.decode(assert(fs.read(directory .. "/PROFILE")))), 64)
  else assert(not fs.exists(directory .. "/COMPONENTS"), "unreadable installed manifest") end
  return result
end
return M
