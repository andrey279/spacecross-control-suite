-- Authenticated local AES cache for offline whitelist use. The key is kept in a
-- separate operator-provisioned file; it is never written beside the cache.
local codec = require("spacecross.core.codec")
local hmac = require("spacecross.security.hmac")
local M = {}
local context = "SpaceCross satellite whitelist cache v1"

function M.new(deps, config)
  local card = assert(deps.component.proxy(assert(config.address)), "cache Data Card unavailable")
  for _, method in ipairs({"sha256", "random", "encrypt", "decrypt"}) do
    assert(type(card[method]) == "function", "Data Card cache API missing " .. method)
  end
  local keyMaterial = assert(deps.fs.read(assert(config.keyFile)), "cache key file unavailable")
  assert(type(keyMaterial) == "string" and #keyMaterial >= 32, "cache key must contain at least 32 bytes")
  local derived = hmac.derive(card.sha256, keyMaterial, context, "AES128CBC+HMACSHA256", 48)
  local self = {}
  function self:encrypt(plaintext)
    assert(type(plaintext) == "string", "cache plaintext must be bytes")
    local iv = card.random(16)
    assert(type(iv) == "string" and #iv == 16, "invalid Data Card IV")
    local ciphertext = card.encrypt(plaintext, derived:sub(1, 16), iv)
    assert(type(ciphertext) == "string" and #ciphertext > 0, "Data Card encryption failed")
    local body = codec.encode({version = 1, iv = iv, ciphertext = ciphertext})
    return codec.encode({body = body, mac = hmac.mac(card.sha256, derived:sub(17, 48), body)})
  end
  function self:decrypt(envelope)
    local outer, err = codec.decode(envelope, 131072)
    if type(outer) ~= "table" or type(outer.body) ~= "string" or type(outer.mac) ~= "string" then return nil, err or "INVALID_CACHE_ENVELOPE" end
    local expected = hmac.mac(card.sha256, derived:sub(17, 48), outer.body)
    if not hmac.equal(outer.mac, expected) then return nil, "CACHE_AUTH_FAILED" end
    local body, bodyErr = codec.decode(outer.body, 131072)
    if type(body) ~= "table" or body.version ~= 1 or type(body.iv) ~= "string" or #body.iv ~= 16
      or type(body.ciphertext) ~= "string" then return nil, bodyErr or "INVALID_CACHE_BODY" end
    local ok, plain = pcall(card.decrypt, body.ciphertext, derived:sub(1, 16), body.iv)
    if not ok or type(plain) ~= "string" then return nil, ok and "CACHE_DECRYPT_FAILED" or tostring(plain) end
    return plain
  end
  return self
end
return M
