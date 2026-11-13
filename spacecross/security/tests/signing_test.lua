local V = require("spacecross.security.tests.stubs.rpc_vectors")
local Card = require("spacecross.security.signing_card")
local Certificates = require("spacecross.security.certificates")
local Protocol = require("spacecross.rpc.protocol")
local codec = require("spacecross.core.codec")
local P = require("tests.stubs.platform")
local H = require("tests.support")
local function hex(data) return (data:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function bytes(data) return (data:gsub("..", function(c) return string.char(tonumber(c, 16)) end)) end
local function python_ecdsa_vectors_match_lua_envelope_and_card_call_contract()
  local p = P.new(); p.files["/private.der"] = bytes(V.client_private)
  local card = {type = "data"}
  card.deserializeKey = function(data, kind)
    assert(kind == "ec-private" or kind == "ec-public")
    return {data = data, kind = kind}
  end
  card.sha256 = function(data) return bytes(assert(V.hashes[hex(data)], "unexpected SHA256 input")) end
  card.random = function(length) return string.rep("r", length) end
  card.ecdsa = function(data, key, signature)
    if not signature then
      assert(key.kind == "ec-private" and hex(key.data) == V.client_private and hex(data) == V.signing_input)
      return bytes(V.signature)
    end
    assert(key.kind == "ec-public")
    return (hex(key.data) == V.ca_public and hex(data) == V.certificate_input and hex(signature) == V.certificate_signature)
      or (hex(key.data) == V.client_public and hex(data) == V.signing_input and hex(signature) == V.signature)
  end
  p.components.card = card
  local crypto = Card.new(p, {address = "card", privateKeyFile = "/private.der"})
  local trust = Certificates.new(crypto, {authorities = {root = bytes(V.ca_public)}})
  local body = assert(codec.decode(bytes(V.body)))
  local wire = Protocol.sign(crypto, bytes(V.certificate), body)
  assert(hex(wire) == V.wire)
  local verified = assert(Protocol.verify(crypto, trust, wire, "client", "server", 27016, 98304))
  assert(verified.certificate.subject == "Owner")
  local bad, err = Protocol.verify(crypto, trust, bytes(V.bad_wire), "client", "server", 27016, 98304)
  return H.truth(bad == nil and err == "INVALID_RPC_SIGNATURE")
end
local all_tests = {
  {test_name = "python_ecdsa_vectors_match_lua_envelope_and_card_call_contract", test = python_ecdsa_vectors_match_lua_envelope_and_card_call_contract},
}
return all_tests
