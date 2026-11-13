local Manifest = require("spacecross.update.manifest")
local Updater = require("spacecross.update.updater")
local codec = require("spacecross.core.codec")
local M = {}
function M.new(deps, config)
  local self = {}
  function self:reserve() return Updater.reserve(deps.fs, config.root, deps.processes) end
  function self:release(lease) return Updater.release(deps.fs, config.root, lease) end
  function self:plan(raw, roots)
    local manifest = assert(Manifest.decode(raw))
    local selected, files = Manifest.select(manifest, roots)
    local current = Manifest.current(deps.fs, config.root)
    local profile = codec.encode(selected)
    local generation = manifest.revision .. "-" .. Manifest.digest(deps.hash, profile):sub(1, 32)
    local same = current.manifest and codec.encode(current.selected) == profile
    local missing = {}
    for _, path in ipairs(files) do
      local metadata = manifest.files[path]
      local previous = current.directory and deps.fs.read(current.directory .. "/" .. path)
      if not Manifest.verify(deps.hash, metadata, previous) then missing[#missing + 1] = path; same = false end
    end
    for _, name in ipairs(selected) do
      local old = current.manifest and current.manifest.components[name]
      if not old or old.version ~= manifest.components[name].version or codec.encode(old.files) ~= codec.encode(manifest.components[name].files) then same = false end
    end
    return {manifest = manifest, raw = raw, selected = selected, files = files, missing = missing,
      current = current, generation = generation, profile = profile, same = same == true}
  end
  function self:install(plan, fetch, deferReboot, lease)
    if plan.same then return {changed = false, generation = plan.current.generation} end
    local updater = Updater.new({fs = deps.fs, reboot = deps.reboot, cancelled = deps.cancelled, processes = deps.processes, fetch = function(_, path)
      local metadata = assert(plan.manifest.files[path])
      local old = plan.current.directory and deps.fs.read(plan.current.directory .. "/" .. path)
      if Manifest.verify(deps.hash, metadata, old) then return old end
      local data, err = fetch(plan.manifest.revision, path)
      assert(Manifest.verify(deps.hash, metadata, data), err or "HASH_MISMATCH: " .. path)
      return data
    end}, config)
    local generation, err = updater:install(plan.generation, plan.files, {deferReboot = deferReboot, lease = lease,
      metadata = {COMPONENTS = plan.raw, PROFILE = plan.profile}})
    if not generation then return nil, err end
    return {changed = true, generation = generation}
  end
  function self:latest(source, roots, deferReboot)
    local revision = assert(source.latest())
    local raw = assert(source.manifest(revision))
    assert(Manifest.decode(raw, revision))
    local plan = self:plan(raw, roots)
    return self:install(plan, source.fetch, deferReboot)
  end
  return self
end
return M
