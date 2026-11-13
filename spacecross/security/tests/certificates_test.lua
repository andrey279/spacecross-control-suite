local Certificates = require("spacecross.security.certificates")
local Fake = require("spacecross.rpc.tests.stubs.crypto")
local System = require("spacecross.rpc.tests.stubs.system")
local H = require("tests.support")
local function certificate_role_address_grants_and_cache_are_enforced()
  local trust = Certificates.new(Fake.new("unused"), {authorities = {root = "root"}})
  local wire = System.certificate("key", "Owner", {"card"}, {"client"}, {power = {"snapshot"}})
  local cert = assert(trust:verify(wire, "client", "card"))
  assert(Certificates.granted(cert, "power", "snapshot") and not Certificates.granted(cert, "power", "off"))
  assert(not trust:verify(wire, "server", "card") and not trust:verify(wire, "client", "other"))
  cert.grants.power[1] = "off"
  assert(trust:verify(wire, "client").grants.power[1] == "snapshot")
  assert(not trust:verify(System.certificate("key", "Owner", {"card"}, {}, {})))
  trust:revoke("key")
  local result, err = trust:verify(wire, "client", "card")
  return H.truth(result == nil and err == "REVOKED_CERTIFICATE")
end
local all_tests = {
  {test_name = "certificate_role_address_grants_and_cache_are_enforced", test = certificate_role_address_grants_and_cache_are_enforced},
}
return all_tests
