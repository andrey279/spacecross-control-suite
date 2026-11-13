-- HMAC-SHA256 and HKDF (RFC 2104, RFC 5869). SHA-256 is supplied by hardware.
local M = {}
local function xor(a, b)
  local value, bit = 0, 1
  for _ = 1, 8 do
    if a % 2 ~= b % 2 then value = value + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return value
end
function M.mac(sha256, key, data)
  if #key > 64 then key = sha256(key) end
  key = key .. string.rep("\0", 64 - #key)
  local inner, outer = {}, {}
  for i = 1, 64 do
    inner[i], outer[i] = string.char(xor(key:byte(i), 0x36)), string.char(xor(key:byte(i), 0x5c))
  end
  local result = sha256(table.concat(outer) .. sha256(table.concat(inner) .. data))
  assert(type(result) == "string" and #result == 32, "invalid SHA256 provider")
  return result
end
function M.derive(sha256, secret, salt, info, length)
  assert(length > 0 and length <= 255 * 32)
  local prk = M.mac(sha256, salt, secret)
  local previous, result, index = "", "", 0
  while #result < length do
    index = index + 1
    previous = M.mac(sha256, prk, previous .. info .. string.char(index))
    result = result .. previous
  end
  return result:sub(1, length)
end
function M.equal(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
  local different = 0
  for i = 1, #a do different = different + (a:byte(i) == b:byte(i) and 0 or 1) end
  return different == 0
end
return M
