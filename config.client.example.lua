-- Copy to /etc/spacecross-client.lua. Used only by bin/remote.lua.
return {
  network = {enabled = true, port = 27015,
    -- cards = {["client-modem-address"] = {}},
  },
  rpc = {enabled = true, port = 27016, timeout = 8, retryInterval = 1,
    crypto = {module = "spacecross.security.signing_card", address = "tier3-data-card-address",
      privateKeyFile = "/etc/spacecross-owner-private.der"},
    certificateFile = "/etc/spacecross-owner.cert",
    authorities = {root = "/etc/spacecross-ca-public.der"},
    revoked = {},
  },
}
