local util = require("spacecross.core.util")
local M = {}
local leases = setmetatable({}, {__mode = "k"})
local function namespace(fs) return fs.lockIdentity or fs end
function M.reserve(fs, root, processes)
  local identity = namespace(fs)
  leases[identity] = leases[identity] or {}
  local old = leases[identity][root]
  if old and (not old.processes or old.processes.alive(old.pid)) then return nil, "EBUSY" end
  local token = {processes = processes, pid = processes and processes.pid()}
  leases[identity][root] = token
  return token
end
function M.release(fs, root, token)
  local entries = leases[namespace(fs)]
  if not entries or entries[root] ~= token then return nil, "EOWNER_UPDATE_LEASE" end
  entries[root] = nil; return true
end

-- Immutable generations on the same HDD, published by one active-pointer rename.
-- Interruptions before publication leave the previously active tree intact.
function M.new(deps, config)
  local self = {busy = false}
  local root = assert(config.root)
  local function active() assert(not deps.cancelled or not deps.cancelled(), "UPDATE_CANCELLED") end
  local function install(revision, files, options)
    options = options or {}
    active()
    assert(type(revision) == "string" and revision:match("^[%w%-_]+$") and #revision <= 80, "invalid revision")
    assert(type(files) == "table" and #files > 0 and #files <= 4096, "invalid file list")
    local release = root .. "/releases/" .. revision
    local seen, ready = {}, deps.fs.exists(release .. "/READY")
    assert(deps.fs.read(root .. "/active") ~= revision, "EALREADY_INSTALLED")
    if ready then
      assert(deps.fs.read(release .. "/READY") == table.concat(files, "\n") .. "\n", "EEXIST_RELEASE")
    end
    util.check(deps.fs.mkdir(release))
    for _, path in ipairs(files) do
      assert(util.relativePath(path) and not seen[path] and path ~= "READY" and path ~= "COMPONENTS" and path ~= "PROFILE", "unsafe/duplicate path")
      seen[path] = true
      local data, err = deps.fetch(revision, path)
      active()
      assert(type(data) == "string", err or "download failed")
      assert(#data <= (config.maxFileSize or 1024 * 1024), "file too large")
      if path:match("%.lua$") then
        local chunk, syntaxErr = load(data, "@" .. path, "t", {})
        assert(chunk, syntaxErr)
      end
      local parent = path:match("^(.*)/")
      if parent then util.check(deps.fs.mkdir(release .. "/" .. parent)) end
      if ready then
        assert(deps.fs.read(release .. "/" .. path) == data, "CORRUPT_STAGED_RELEASE")
      else
        util.check(deps.fs.write(release .. "/" .. path, data))
      end
    end
    for _, required in ipairs(config.required or {"spacecross/app.lua"}) do
      assert(seen[required], "missing required file: " .. required)
    end
    for name, data in pairs(options.metadata or {}) do
      assert((name == "COMPONENTS" or name == "PROFILE") and type(data) == "string" and #data <= 131072, "invalid release metadata")
      if ready then assert(deps.fs.read(release .. "/" .. name) == data, "CORRUPT_RELEASE_METADATA")
      else util.check(deps.fs.write(release .. "/" .. name, data)) end
    end
    active()
    if not ready then util.check(deps.fs.write(release .. "/READY", table.concat(files, "\n") .. "\n")) end
    util.check(deps.fs.write(root .. "/active.new", revision))
    active()
    util.check(deps.fs.rename(root .. "/active.new", root .. "/active"))
    return revision
  end
  function self:install(revision, files, options)
    if self.busy then return nil, "EBUSY" end
    local lease, own = options and options.lease, false
    if lease then
      if not leases[namespace(deps.fs)] or leases[namespace(deps.fs)][root] ~= lease then return nil, "EOWNER_UPDATE_LEASE" end
    else
      local err; lease, err = M.reserve(deps.fs, root, deps.processes)
      if not lease then return nil, err end
      own = true
    end
    self.busy = true
    local ok, result = pcall(install, revision, files, options)
    self.busy = false
    if own then M.release(deps.fs, root, lease) end
    if not ok then return nil, tostring(result) end
    if deps.reboot and not (options and options.deferReboot) then deps.reboot() end
    return result
  end
  function self:latest()
    if not deps.latest or not deps.files then return nil, "ENOTSUP" end
    local revision, err = deps.latest()
    if not revision then return nil, err end
    local files, fileErr = deps.files(revision)
    if not files then return nil, fileErr end
    return self:install(revision, files)
  end
  return self
end
return M
