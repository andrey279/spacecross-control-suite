local codec = require("spacecross.core.codec")
local util = require("spacecross.core.util")
local M = {}
local function text(value, limit)
  return type(value) == "string" and #value > 0 and #value <= limit and not value:find("[%z\1-\31\127]")
end
local function profile(value)
  if type(value) ~= "table" or not text(value.host_name, 64) then return false end
  if value.description ~= nil and (type(value.description) ~= "string" or #value.description > 256
      or value.description:find("[%z\1-\31\127]")) then return false end
  if value.type ~= nil then
    if type(value.type) ~= "table" or #value.type > 32 then return false end
    local count = 0
    for index, name in pairs(value.type) do
      if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #value.type or not text(name, 64) then return false end
      count = count + 1
    end
    if count ~= #value.type then return false end
  end
  return true
end
function M.new(deps, config)
  config = config or {}
  local port, interval, ttl, maxHosts = config.port or 27014, config.interval or 10, config.ttl or 35, config.maxHosts or 128
  assert(require("spacecross.network.protocol").port(port) and interval > 0 and ttl > interval and maxHosts >= 1)
  local localProfile = {host_name = config.host_name or "spacecross", type = config.type or {}, description = config.description}
  assert(profile(localProfile), "invalid discovery profile")
  local self = {hosts = {}, running = false, queryTimes = {}}
  local function notify(name, address) deps.event.push(name, address) end
  function self:expire()
    local now = deps.clock()
    for address, host in pairs(self.hosts) do
      for card, seen in pairs(host.paths) do if now - seen >= ttl or not deps.network.cards[card] then host.paths[card] = nil end end
      if not next(host.paths) then self.hosts[address] = nil; notify("spacecross_host_lost", address) end
    end
    for address, last in pairs(self.queryTimes) do if now - last >= ttl then self.queryTimes[address] = nil end end
  end
  function self:list(kind)
    self:expire()
    local result = {}
    for _, address in ipairs(util.sortedKeys(self.hosts)) do
      local host, accepted = self.hosts[address], kind == nil
      for _, value in ipairs(host.type or {}) do if value == kind then accepted = true end end
      if accepted then
        result[#result + 1] = {host_name = host.host_name, address = address, type = util.copy(host.type),
          description = host.description, last_seen = host.last_seen, reachable_via = util.sortedKeys(host.paths), verified = false}
      end
    end
    return result
  end
  function self:announce(card, destination)
    local data = util.copy(localProfile)
    data.v, data.action, data.address = 1, "announce", card
    return deps.network:send(destination or "*", port, codec.encode(data), card, "discovery")
  end
  function self:query(card)
    return deps.network:broadcast(port, codec.encode({v = 1, action = "query"}), card, "discovery")
  end
  function self:setProfile(value)
    if not profile(value) then return nil, "INVALID_DISCOVERY_PROFILE" end
    localProfile = {host_name = value.host_name, type = util.copy(value.type), description = value.description}
    if self.running then for _, card in ipairs(deps.network:listCards()) do self:announce(card.address) end end
    return true
  end
  local function onMessage(_, receiver, source, _, messagePort, service, payload)
    if messagePort ~= port or service ~= "discovery" then return end
    local data = codec.decode(payload, 8192)
    if type(data) ~= "table" or data.v ~= 1 then return end
    if data.action == "query" then
      local key = source .. "/" .. receiver
      local last, count = self.queryTimes[key], 0
      for _ in pairs(self.queryTimes) do count = count + 1 end
      if (not last or deps.clock() - last >= 1) and (last or count < maxHosts * 4) then
        self.queryTimes[key] = deps.clock(); self:announce(receiver, source)
      end
    elseif data.action == "announce" and data.address == source and profile(data) then
      self:expire()
      local old = self.hosts[source]
      if not old then
        local count, oldest, oldestTime = 0
        for address, host in pairs(self.hosts) do
          count = count + 1
          if not oldestTime or host.last_seen < oldestTime then oldest, oldestTime = address, host.last_seen end
        end
        if count >= maxHosts then self.hosts[oldest] = nil; notify("spacecross_host_lost", oldest) end
      end
      local host = {host_name = data.host_name, type = util.copy(data.type), description = data.description,
        last_seen = deps.clock(), paths = old and old.paths or {}}
      host.paths[receiver] = deps.clock(); self.hosts[source] = host
      notify("spacecross_host_changed", source)
    elseif data.action == "bye" and data.address == source and self.hosts[source] then
      self.hosts[source] = nil; notify("spacecross_host_lost", source)
    end
  end
  local function added(_, address)
    self:announce(address); self:query(address)
  end
  local function removed() self:expire() end
  function self:start()
    if self.running then return false end
    self.running = true
    deps.event.listen("spacecross_network_message", onMessage)
    deps.event.listen("spacecross_network_card_added", added)
    deps.event.listen("spacecross_network_card_removed", removed)
    self.timer = deps.event.timer(interval, function()
      self:expire()
      for _, card in ipairs(deps.network:listCards()) do self:announce(card.address) end
    end, math.huge)
    for _, card in ipairs(deps.network:listCards()) do self:announce(card.address); self:query(card.address) end
    return true
  end
  function self:stop()
    if self.running then
      for _, card in ipairs(deps.network:listCards()) do
        deps.network:broadcast(port, codec.encode({v = 1, action = "bye", address = card.address}), card.address, "discovery")
      end
    end
    if self.timer then deps.event.cancel(self.timer); self.timer = nil end
    deps.event.ignore("spacecross_network_message", onMessage)
    deps.event.ignore("spacecross_network_card_added", added)
    deps.event.ignore("spacecross_network_card_removed", removed)
    self.running, self.hosts, self.queryTimes = false, {}, {}
  end
  return self
end
return M
