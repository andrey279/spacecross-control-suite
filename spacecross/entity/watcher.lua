local util = require("spacecross.core.util")
local codec = require("spacecross.core.codec")
local M = {}
function M.new(deps, config)
  config = config or {}
  assert((config.interval or 2) > 0 and (config.ttl or 6) > 0)
  assert(type(config.range) == "number" and config.range >= 1 and config.range % 1 == 0, "detector range required")
  local self = {sources = {}, running = false, last = nil}
  function self:poll()
    local alive, errors = {}, {}
    for _, detector in ipairs(deps.hal.registry:list("detector")) do
      alive[detector.address] = true
      local entities, err = deps.hal:call(detector.address, "scanPlayers", config.range)
      if type(entities) == "table" then
        self.sources[detector.address] = {entities = entities, time = deps.clock(), healthy = true}
      else
        if self.sources[detector.address] then self.sources[detector.address].healthy = false end
        errors[#errors + 1] = {address = detector.address, error = err}
      end
    end
    for address in pairs(self.sources) do if not alive[address] then self.sources[address] = nil end end
    self.last = self:snapshot()
    self.last.errors = errors
    if deps.bus then deps.bus:publish({proto_version = 1, msg_type = "event", port = config.port or 27101,
      payload = codec.encode(self.last)}) end
    if deps.onSnapshot then deps.onSnapshot(util.copy(self.last)) end
    return util.copy(self.last)
  end
  function self:snapshot()
    local names, healthy, expected = {}, 0, #deps.hal.registry:list("detector")
    for address, source in pairs(self.sources) do
      if deps.clock() - source.time <= (config.ttl or 6) then
        if source.healthy then healthy = healthy + 1 end
        for _, entity in ipairs(source.entities) do
          local name = entity.name:lower()
          local item = names[name]
          if not item then
            item = util.copy(entity); item.sources = {}; names[name] = item
          end
          item.sources[#item.sources + 1] = address
        end
      end
    end
    local entities = {}
    for _, name in ipairs(util.sortedKeys(names)) do
      local entity = names[name]; table.sort(entity.sources); entities[#entities + 1] = entity
    end
    return {entities = entities, count = #entities, time = deps.clock(),
      complete = expected > 0 and healthy == expected, healthySources = healthy, expectedSources = expected}
  end
  local function tick()
    local ok, err = pcall(self.poll, self)
    if not ok and deps.log then deps.log("error", "ERR_WATCHER", {error = tostring(err)}) end
  end
  function self:start()
    if self.running then return false end
    self.running = true
    self.timer = deps.event.timer(config.interval or 2, tick, math.huge)
    tick()
    return true
  end
  function self:stop()
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    self.running = false
  end
  return self
end
return M
