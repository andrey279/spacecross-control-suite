-- Explicit alternate crypto provider for official OpenSecurity builds lacking RSA/ECC.
-- ECIES-style envelope: ephemeral ECDH, HKDF-SHA256, AES-128-CBC, HMAC-SHA256.
-- Only the server public key is stored on a ship; decrypting needs its private key.
local codec = require("spacecross.core.codec")
local hmac = require("spacecross.security.hmac")
local M = {}
local context = "SpaceCross sealed logs v1"

function M.new(deps, config)
  local card = assert(deps.component.proxy(assert(config.address)), "crypto card missing")
  for _, method in ipairs({"sha256", "random", "generateKeyPair", "deserializeKey", "ecdh", "encrypt"}) do
    assert(type(card[method]) == "function", "Tier 3 Data Card required: " .. method)
  end
  local publicBytes = assert(deps.fs.read(assert(config.publicKeyFile)))
  local recipient = card.deserializeKey(publicBytes, "ec-public")
  local keyId = card.sha256(publicBytes)
  local self = {}
  function self.seal(plaintext)
    local public, private = card.generateKeyPair(256)
    local ephemeral = public.serialize()
    local material = hmac.derive(card.sha256, card.ecdh(private, recipient), context, ephemeral .. keyId, 48)
    local iv = card.random(16)
    assert(type(iv) == "string" and #iv == 16, "invalid random IV")
    local envelope = {version = 1, algorithm = "ECDH-HKDF-SHA256-AES128CBC-HMACSHA256",
      key_id = keyId, ephemeral = ephemeral, iv = iv, ciphertext = card.encrypt(plaintext, material:sub(1, 16), iv)}
    local body = codec.encode(envelope)
    return codec.encode({body = body, mac = hmac.mac(card.sha256, material:sub(17), body)})
  end
  return self
end
return M
