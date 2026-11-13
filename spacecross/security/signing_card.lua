-- Explicit OpenComputers Tier 3 provider; no substitution with hashes/shared secrets.
local M = {}
function M.new(deps, config)
  local card = assert(deps.component.proxy(assert(config.address)))
  for _, method in ipairs({"deserializeKey", "ecdsa", "sha256", "random"}) do
    assert(type(card[method]) == "function", "Tier 3 signing API missing " .. method)
  end
  local private = card.deserializeKey(assert(deps.fs.read(assert(config.privateKeyFile))), "ec-private")
  local self = {}
  function self.sha256(data)
    local result = card.sha256(data)
    assert(type(result) == "string" and #result == 32, "INVALID_SHA256")
    return result
  end
  function self.random(length)
    local result = card.random(length)
    assert(type(result) == "string" and #result == length, "INVALID_SECURE_RANDOM")
    return result
  end
  function self.sign(data)
    local result = card.ecdsa(data, private)
    assert(type(result) == "string" and #result > 0, "SIGNING_FAILED")
    return result
  end
  function self.verify(public, data, signature)
    local ok, result = pcall(function()
      return card.ecdsa(data, card.deserializeKey(public, "ec-public"), signature)
    end)
    return ok and result == true
  end
  return self
end
return M
