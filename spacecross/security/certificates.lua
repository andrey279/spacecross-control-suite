local codec = require("spacecross.core.codec")
local util = require("spacecross.core.util")
local protocol = require("spacecross.network.protocol")
local M = {domain = "SpaceCross certificate v1\0"}
local function label(value, limit)
  return type(value) == "string" and #value > 0 and #value <= limit and not value:find("[%z\1-\31\127]")
end
local function array(values, maximum, validate)
  if type(values) ~= "table" or #values > maximum then return false end
  local count, seen = 0, {}
  for index, value in pairs(values) do
    if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #values or not validate(value) or seen[value] then return false end
    seen[value], count = true, count + 1
  end
  return count == #values
end
function M.bound(certificate, address)
  for _, value in ipairs(certificate.addresses) do if value == address then return true end end
  return false
end
function M.granted(certificate, model, action)
  for _, name in ipairs({model, "*"}) do
    for _, allowed in ipairs(certificate.grants[name] or {}) do if allowed == action or allowed == "*" then return true end end
  end
  return false
end
function M.new(crypto, config)
  config = config or {}
  local authorities, revoked, cache = util.copy(assert(config.authorities)), util.copy(config.revoked or {}), {}
  local maximum, maxCache = config.maxCertificate or 8192, config.maxCache or 32
  assert(maximum > 0 and maxCache >= 1)
  local self = {}
  function self:revoke(serial) revoked[serial] = true; cache = {} end
  function self:verify(encoded, usage, address)
    if type(encoded) ~= "string" or #encoded > maximum then return nil, "INVALID_CERTIFICATE" end
    local certificate = cache[encoded]
    if not certificate then
      local outer = codec.decode(encoded, maximum)
      if type(outer) ~= "table" or type(outer.body) ~= "string" or type(outer.signature) ~= "string"
          or #outer.signature == 0 or #outer.signature > 256 then return nil, "INVALID_CERTIFICATE" end
      local value = codec.decode(outer.body, maximum)
      if type(value) ~= "table" or value.v ~= 1 or not label(value.issuer, 64) or not label(value.serial, 128)
          or not label(value.subject, 64) or type(value.public_key) ~= "string" or #value.public_key > 2048
          or #value.public_key == 0 or not array(value.addresses, 32, protocol.address) or #value.addresses == 0
          or not array(value.usage, 2, function(v) return v == "client" or v == "server" end) or #value.usage == 0
          or type(value.grants) ~= "table" then return nil, "INVALID_CERTIFICATE" end
      local fields = {v = true, issuer = true, serial = true, subject = true, public_key = true, addresses = true, usage = true, grants = true}
      for key in pairs(value) do if not fields[key] then return nil, "UNKNOWN_CERTIFICATE_FIELD" end end
      local count = 0
      for model, actions in pairs(value.grants) do
        count = count + 1
        if not label(model, 64) or not array(actions, 64, function(v) return label(v, 64) end) or count > 64 then return nil, "INVALID_GRANTS" end
      end
      local authority = authorities[value.issuer]
      if type(authority) ~= "string" then return nil, "UNKNOWN_ISSUER" end
      local ok, valid = pcall(function() return crypto.verify(authority, M.domain .. crypto.sha256(outer.body), outer.signature) end)
      if not ok or valid ~= true then return nil, "INVALID_CERTIFICATE_SIGNATURE" end
      if revoked[value.serial] then return nil, "REVOKED_CERTIFICATE" end
      local size = 0; for _ in pairs(cache) do size = size + 1 end
      if size >= maxCache then cache = {} end
      certificate = value; cache[encoded] = value
    end
    if revoked[certificate.serial] then return nil, "REVOKED_CERTIFICATE" end
    if usage then
      local permitted = false
      for _, value in ipairs(certificate.usage) do if value == usage then permitted = true end end
      if not permitted then return nil, "WRONG_CERTIFICATE_USAGE" end
    end
    if address and not M.bound(certificate, address) then return nil, "CERTIFICATE_ADDRESS_MISMATCH" end
    return util.copy(certificate)
  end
  return self
end
return M
