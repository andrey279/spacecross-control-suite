local hmac = require("spacecross.security.hmac")
local Card = require("spacecross.security.data_card")
local P = require("tests.stubs.platform")
local V = require("spacecross.security.tests.stubs.vectors")
local H = require("tests.support")
local function hex(data) return (data:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function unhex(data) return (data:gsub("..", function(c) return string.char(tonumber(c, 16)) end)) end
local function sha(data)
  return unhex(assert(V.hashes[hex(data)], "SHA256 call differs from independent vector"))
end
local function rfc_hmac_and_hkdf_vectors()
  assert(hex(hmac.mac(sha, string.rep("\11", 20), "Hi There")) == V.hmac1)
  assert(hex(hmac.mac(sha, "Jefe", "what do ya want for nothing?")) == V.hmac2)
  assert(hex(hmac.mac(sha, string.rep("\170", 131), "Test Using Larger Than Block-Size Key - Hash Key First")) == V.hmac_long)
  local salt, info = "", ""
  for i = 0, 12 do salt = salt .. string.char(i) end
  for i = 240, 249 do info = info .. string.char(i) end
  return H.equal(hex(hmac.derive(sha, string.rep("\11", 22), salt, info, 42)), V.hkdf1)
end
local function data_card_envelope_matches_independent_crypto()
  local p = P.new()
  p.files["/public.key"] = unhex(V.recipient)
  local card = {type = "data", sha256 = sha}
  card.deserializeKey = function(bytes, kind)
    assert(hex(bytes) == V.recipient and kind == "ec-public"); return "recipient"
  end
  card.generateKeyPair = function(bits)
    assert(bits == 256)
    return {serialize = function() return unhex(V.ephemeral) end}, "ephemeral-private"
  end
  card.ecdh = function(private, public)
    assert(private == "ephemeral-private" and public == "recipient"); return unhex(V.shared)
  end
  card.random = function(length)
    assert(length == 16)
    local out = ""; for i = 0, 15 do out = out .. string.char(i) end
    return out
  end
  card.encrypt = function(plaintext, key, iv)
    assert(plaintext == "spacecross encryption test" and hex(key) == V.aes_key and #iv == 16)
    return unhex(V.ciphertext)
  end
  p.components.card = card
  local crypto = Card.new(p, {address = "card", publicKeyFile = "/public.key"})
  local encrypted = crypto.seal("spacecross encryption test")
  return H.equal(hex(encrypted), V.envelope)
end
local function rejects_insufficient_hardware()
  local p = P.new(); p.components.card = {type = "data", sha256 = sha}
  return H.equal(pcall(Card.new, p, {address = "card", publicKeyFile = "/key"}), false)
end
local function local_cache_uses_authenticated_aes_envelope_and_rejects_tampering()
  local p, Fake = P.new(), require("spacecross.rpc.tests.stubs.crypto").new("cache")
  p.files["/cache.key"] = string.rep("K", 32)
  local card = {sha256 = Fake.sha256, random = function(n) assert(n == 16); return string.rep("I", 16) end,
    encrypt = function(data, key, iv) assert(#key == 16 and #iv == 16); return data:reverse() end,
    decrypt = function(data, key, iv) assert(#key == 16 and #iv == 16); return data:reverse() end}
  p.component.proxy = function(address) assert(address == "card"); return card end
  local Cache = require("spacecross.security.local_cache")
  local cache = Cache.new({component = p.component, fs = p.fs}, {address = "card", keyFile = "/cache.key"})
  local encrypted = cache:encrypt("trusted,friend")
  assert(not encrypted:find("trusted,friend", 1, true))
  assert(cache:decrypt(encrypted) == "trusted,friend")
  local corrupt = encrypted:sub(1, -2) .. string.char((encrypted:byte(-1) + 1) % 256)
  local plain, err = cache:decrypt(corrupt)
  assert(plain == nil and err == "CACHE_AUTH_FAILED")
  return H.truth(true)
end
local all_tests = {
  {test_name = "rfc_hmac_and_hkdf_vectors", test = rfc_hmac_and_hkdf_vectors},
  {test_name = "data_card_envelope_matches_independent_crypto", test = data_card_envelope_matches_independent_crypto},
  {test_name = "rejects_insufficient_hardware", test = rejects_insufficient_hardware},
  {test_name = "local_cache_uses_authenticated_aes_envelope_and_rejects_tampering", test = local_cache_uses_authenticated_aes_envelope_and_rejects_tampering},
}
return all_tests
