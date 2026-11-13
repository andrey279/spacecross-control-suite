local codec = require("spacecross.core.codec")
local network = require("spacecross.network.protocol")
local M = {domain = "SpaceCross RPC v1\0"}
function M.hex(data) return (data:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
function M.token(value) return type(value) == "string" and #value == 64 and value:match("^%x+$") ~= nil end
function M.sign(crypto, certificate, body)
  local encoded = codec.encode(body)
  return codec.encode({body = encoded, certificate = certificate, signature = crypto.sign(M.domain .. crypto.sha256(encoded))})
end
function M.verify(crypto, trust, wire, source, destination, port, maximum)
  local outer = codec.decode(wire, maximum)
  if type(outer) ~= "table" or type(outer.body) ~= "string" or type(outer.signature) ~= "string"
      or #outer.signature == 0 or #outer.signature > 256 then return nil, "INVALID_RPC_FRAME" end
  local body = codec.decode(outer.body, maximum)
  if type(body) ~= "table" or body.v ~= 1 or not M.token(body.id) or not M.token(body.client_nonce)
      or body.src ~= source or body.dst ~= destination or body.port ~= port
      or not network.address(source) or not network.address(destination) then return nil, "INVALID_RPC_BINDING" end
  local usage
  if body.kind == "hello" or body.kind == "invoke" then usage = "client"
  elseif body.kind == "challenge" or body.kind == "result" then usage = "server"
  else return nil, "INVALID_RPC_KIND" end
  local cert, err = trust:verify(outer.certificate, usage, source)
  if not cert then return nil, err end
  if crypto.verify(cert.public_key, M.domain .. crypto.sha256(outer.body), outer.signature) ~= true then return nil, "INVALID_RPC_SIGNATURE" end
  if body.kind ~= "hello" and (not M.token(body.challenge) or type(body.hello_digest) ~= "string" or #body.hello_digest ~= 32) then return nil, "INVALID_CHALLENGE_BINDING" end
  return {body = body, certificate = cert, certificateWire = outer.certificate, bodyWire = outer.body}
end
return M
