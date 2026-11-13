# Satellite and mine controller

`spacecross.satellite.controller` provides the ten-second heartbeat loop, radar
scan normalization, whitelist filtering, two mine modes, and an Owner-only model.
The CnC RPC agent sends satellite state with its authenticated heartbeat, fetches
the node-scoped server whitelist, and records attack alerts durably on the server.
With `modeScan=true` and `autoAttack=true`, each complete scheduled scan attacks
only targets outside a non-empty loaded whitelist. Missing or empty whitelist
data fails closed.

`spacecross.satellite.adapters` binds configured OpenComputers component
addresses and exact method names to radar, WarpDrive controller, and charge
operations. It does not guess component types or callbacks. In-game inspection
must confirm each configured method and its argument/return shape.

When `cacheCard` and `cacheKeyFile` are configured, `spacecross.security.local_cache`
uses Data Card AES plus HMAC-SHA256 for an authenticated local cache envelope.
The key file must contain at least 32 random bytes, be provisioned separately,
and be protected from users who can read the cache. If encryption is unavailable,
the cache is neither read nor written; current-session whitelist data remains in
memory. The exact legacy Data Card encrypt/decrypt API must be checked in-game.

The `jump` mode delegates navigation and central-charge detonation to the
configured WarpDrive/component adapter. The `charges` mode computes a target
vector from the position adapter, activates exactly six auxiliary charges, and
detonates the central charge only after that step succeeds. The attack alert is
sent through the CnC adapter before either mode runs. Component names, radar result formats, charge
wiring, jump commands, and server authentication are deployment-specific; no
Minecraft 1.7.10 implementation is claimed until those adapters are tested in
the target modpack. Keep mine testing inert until each callback is verified.

Enable `satellite.enabled` only when `satelliteHeartbeat`, an authenticated
`satelliteFetchWhitelist` callback, radar scan, and both selected mode adapters
are provided by the application host. Whitelist entries match a target `id` or
`name`. The model accepts mode changes, scans, attacks, and whitelist changes
from Owners only.
