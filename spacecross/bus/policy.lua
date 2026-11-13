local util = require("spacecross.core.util")
local M = {}
local function compile(rule)
  rule = rule or {}
  local out = {forwardLocal = rule.forwardLocal == true}
  for _, category in ipairs({"whitelist", "blacklist"}) do
    if rule[category] then
      out[category] = {}
      for _, field in ipairs({"ports", "msg_types", "peers"}) do
        if rule[category][field] then out[category][field] = util.set(rule[category][field]) end
      end
    end
  end
  return out
end
local function permits(rule, message, peer)
  local values = {ports = message.port, msg_types = message.msg_type, peers = peer}
  for field, value in pairs(values) do
    if rule.blacklist and rule.blacklist[field] and rule.blacklist[field][value] then return false end
    if rule.whitelist and rule.whitelist[field] and not rule.whitelist[field][value] then return false end
  end
  return true
end
function M.new(config)
  config = config or {}
  local global = {inbound = compile(config.inbound), outbound = compile(config.outbound)}
  local cards = {}
  for address, rules in pairs(config.cards or {}) do
    if rules == false then cards[address] = false
    else cards[address] = {inbound = compile(rules.inbound), outbound = compile(rules.outbound)} end
  end
  local self = {}
  function self:allows(direction, card, message, peer)
    assert(direction == "inbound" or direction == "outbound")
    local specific = cards[card]
    if specific == false or not permits(global[direction], message, peer) then return false end
    if specific and not permits(specific[direction], message, peer) then return false end
    if direction == "outbound" and message.dst_addr == nil then
      return global.outbound.forwardLocal or specific and specific.outbound.forwardLocal or false
    end
    return true
  end
  return self
end
return M
