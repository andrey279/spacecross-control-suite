local codec = require("spacecross.core.codec")
local M = {magic = "SCN1:"}
function M.address(value)
  return type(value) == "string" and #value >= 1 and #value <= 64 and value:match("^[%w%-]+$") ~= nil
end
function M.port(value) return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= 65535 end
function M.service(value)
  return type(value) == "string" and #value >= 1 and #value <= 32 and value:match("^[%w_.%-]+$") ~= nil
end
function M.encode(packet) return M.magic .. codec.encode(packet) end
function M.decode(wire, maximum, maxFragments)
  if type(wire) ~= "string" or #wire + 2 > maximum or wire:sub(1, #M.magic) ~= M.magic then return nil, "INVALID_WIRE" end
  local value, err = codec.decode(wire:sub(#M.magic + 1), maximum)
  if type(value) ~= "table" then return nil, err or "INVALID_HEADER" end
  if value.v ~= 1 or type(value.id) ~= "string" or #value.id < 1 or #value.id > 128
      or not value.id:match("^[%w:._%-]+$") or not M.address(value.src)
      or (value.dst ~= "*" and not M.address(value.dst)) or not M.port(value.port)
      or not M.service(value.service) or type(value.body) ~= "string"
      or type(value.part) ~= "number" or value.part % 1 ~= 0 or value.part < 1
      or type(value.total) ~= "number" or value.total % 1 ~= 0 or value.total < value.part
      or value.total > maxFragments then return nil, "INVALID_HEADER" end
  local fields = {v = true, id = true, src = true, dst = true, port = true, service = true, body = true, part = true, total = true}
  for key in pairs(value) do if not fields[key] then return nil, "UNKNOWN_HEADER_FIELD" end end
  return value
end
return M
