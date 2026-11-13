-- Copy to /etc/spacecross.lua; configuration stays outside update generations.
return {
  owners = {"YourMinecraftNickname"},
  admins = {},
  drivers = {
    -- RFTools Shield Projector (component type shield_projector). Configure an
    -- explicit redstone output for on/off; omit devices for read-only/status use.
    -- "spacecross.hal.drivers.redstone",
    -- {module = "spacecross.hal.drivers.rftools_shield", options = {devices = {
    --   ["shield-projector-address"] = {controlAddress = "redstone-address", side = 3,
    --     activationMode = "On", onValue = 15, offValue = 0},
    -- }}},
    -- OMT adapter requires explicit component types from the installed 1.7.10 build.
    -- Only toggle()/setMode() are assumed; optional telemetry method names are configurable.
    -- {module = "spacecross.hal.drivers.omt_turret", options = {
    --   types = {"verified-omt-component-type"}, activeMethod = "verifiedActiveMethod",
    --   currentEnergyMethod = "verifiedCurrentEnergyMethod", maxEnergyMethod = "verifiedCapacityMethod",
    --   getModeMethod = "verifiedGetModeMethod", modes = {0, 1}, -- only confirmed mode values
    -- }},
  },
  logging = {root = "/var/lib/spacecross/logs", interval = 1, maxQueue = 256},
  -- No cryptography configured: RAM queue only, never plaintext files.
  -- crypto = {module = "spacecross.security.data_card", address = "data-card-address",
  --   publicKeyFile = "/etc/spacecross-log-public.key"},
  panels = {
    -- {id = "main", gpu = "gpu-component-address", screen = "screen-component-address",
    --  player = "YourMinecraftNickname"},
  },
  uiInterval = 2,
  watcher = {enabled = false, range = 32, interval = 2, ttl = 6},
  -- Computronics Radar is optional. The upstream 1.7.10 contract is type radar,
  -- getPlayers(distance), records with name/x/y/z/distance.
  -- {module = "spacecross.hal.drivers.computronics_radar", options = {
  --   -- Defaults are types={"radar"}, method="getPlayers", passRange=true,
  --   -- nameField="name". Override only for a fork with a different contract.
  -- }},
  shields = {enabled = false}, -- enables authenticated model/UI; all changes require an Owner
  turrets = {enabled = false}, -- enables owner-only OMT model/UI; configure driver type before enabling
  -- Component callbacks are bound through explicit hardware method configuration below.
  satellite = {enabled = false, id = "satellite-1", mode = "jump", heartbeatInterval = 10,
    range = 128, modeScan = true, autoAttack = true,
    cachePath = "/var/lib/spacecross/whitelist.enc",
    -- Separate operator-provisioned secret (>=32 random bytes) plus Tier 3 Data Card.
    -- cacheCard = "data-card-address", cacheKeyFile = "/etc/spacecross-cache.key",
    -- Component names/methods are explicit and must match the installed legacy mod build.
    -- hardware = {radar = {address = "radar-address", scan = "verifiedScanMethod"},
    --   ship = {address = "ship-controller-address", jump = "verifiedJumpMethod", position = "verifiedPositionMethod"},
    --   charges = {auxiliary = {address = "aux-address", method = "verifiedActivateMethod"},
    --     central = {address = "central-charge-address", method = "verifiedDetonateMethod"}}},
  },
  -- To use these modules also add to drivers:
  -- "spacecross.hal.drivers.opensecurity_detector", "spacecross.hal.drivers.redstone"
  defense = {enabled = false, armed = false, intrusion = true,
    scorchedEarth = false, heartbeatTimeout = 60, interval = 1,
    channels = {
      -- {address = "redstone-component-address", side = 1, value = 15},
    }},
  -- Add "spacecross.hal.drivers.warpdrive_ship" to drivers for navigation.
  coreDaemon = {enabled = false, retryInterval = 1,
    -- controllers = {"ship-controller-address"}, -- omit to manage all navigation instances
  },
  autopilot = {enabled = false, controller = "ship-controller-address", interval = 1,
    lockPath = "/tmp/autopilot.lock", jumpTimeout = 180,
    target = {x = 0, y = 64, z = 0}},
  -- Requires explicit hardware bindings below or host-injected deployment adapters.
  structures = {enabled = false, interval = 1, program = "spacecross-mine", routePath = "/etc/spacecross-route.dat",
    navigationTimeout = 180,
    -- hardware = {builder = {address = "builder-address", deploy = "verifiedDeployMethod", confirm = "verifiedConfirmMethod"},
    --   computer = {addressField = "computerAddress", provision = "verifiedProvisionMethod"}},
  },
  -- Configurable drivers share the standard RF component types; bind each address once:
  -- {module = "spacecross.hal.drivers.enderio_capacitor",
  --   options = {devices = {["capacitor-address"] = {}}}},
  -- "spacecross.hal.drivers.enan_reactor",
  -- {module = "spacecross.hal.drivers.nc_reactor", options = {devices = {
  --   ["nc-rf-address"] = {controlAddress = "redstone-address", side = 1}}}},
  -- {module = "spacecross.hal.drivers.thermal_generator", options = {devices = {
  --   ["thermal-rf-address"] = {controlAddress = "redstone-address", side = 2}}}},
  -- NC requires redstone HIGH to run. Set the Thermal machine's redstone mode to
  -- match its configured onValue/offValue. Both use the registered redstone driver.
  power = {enabled = false, interval = 2, startBelow = 0.3, stopAbove = 0.8,
    buffers = {"capacitor-address"}, sources = {"reactor-address"},
    shedBelow = {0.3, 0.2, 0.1},
    loads = {
      -- {id = "expensive-production", group = 1, address = "redstone-address",
      --  off = {method = "setOutput", args = {3, 0}}, on = {method = "setOutput", args = {3, 15}}},
      -- group 2 = main production without owners; group 3 = cloak/secondary systems.
    }},
  network = {enabled = false, port = 27015,
    -- Omit cards to discover all modem/tunnel components, or bind selected cards:
    -- cards = {["modem-address"] = {strength = 64}, ["tunnel-address"] = {}},
    maxMessage = 131072, maxFragments = 256, maxPending = 16, maxPeerPending = 4,
    maxBuffered = 524288, fragmentTTL = 5, seenTTL = 30, maxSeen = 512,
    discovery = {host_name = "SpaceCross", interval = 10, ttl = 35, maxHosts = 128,
      -- type = {"reactors_controller", "capacitors_controller"},
      -- Omit type to advertise the installed model names. No implicit trust.
    },
    bus = {enabled = false,
      outbound = {forwardLocal = true, whitelist = {ports = {27101, 27102, 27103}, msg_types = {"event"}}},
      inbound = {whitelist = {ports = {27101, 27102, 27103}, msg_types = {"event"}}},
      cards = {
        -- ["private-card"] = false, -- disable this card for the bus bridge only
        -- ["public-card"] = {outbound = {blacklist = {ports = {27102}}}},
      },
    }},
  rpc = {enabled = false, port = 27016, timeout = 8, challengeTTL = 10, retryInterval = 1,
    cacheTTL = 30, maxSessions = 32, maxPeer = 4, maxBytes = 524288, maxFrame = 98304,
    -- Explicit provider: official OpenSecurity 1.7.10 has no RSA/ECC API.
    crypto = {module = "spacecross.security.signing_card", address = "tier3-data-card-address",
      privateKeyFile = "/etc/spacecross-node-private.der"},
    certificateFile = "/etc/spacecross-node.cert",
    authorities = {root = "/etc/spacecross-ca-public.der"},
    revoked = {}, -- map certificate serial -> true; issuer revocation is configured locally
    identities = {
      -- Additional actor-bound client identities on a UI computer:
      -- {certificateFile = "/etc/spacecross-owner.cert", crypto = {
      --   module = "spacecross.security.signing_card", address = "tier3-data-card-address",
      --   privateKeyFile = "/etc/spacecross-owner-private.der"}},
    }},
  -- Full OS shell is owner-only, also requires terminal action grants in the client certificate.
  terminal = {enabled = false, program = "/bin/sh", maxWidth = 160, maxHeight = 50,
    maxSessions = 4, maxPerOwner = 2, maxCells = 16000, idleTTL = 120,
    maxQueue = 256, maxInputBytes = 32768, maxFrameBytes = 600000, frameInterval = 0.1},
  cnc = {enabled = false, address = "internet-card-address", host = "control.example.org", serverPort = 27016,
    peer = "cnc-server", peerCertificateFile = "/etc/spacecross-cnc.cert", actor = "Ship",
    interval = 0.2, heartbeatInterval = 10, connectTimeout = 10, maxBackoff = 30},
  -- Ship RPC cert: client+server usage, internet card address, grants
  -- {_cnc={"heartbeat","whitelist","alert"}, _logs={"put"}}.
  -- cnc.actor is the SHIP cert subject.
  -- Incoming commands use the pinned CnC cert's subject (e.g. Owner);
  -- its grants and the ship model's owner/admin ACL are both enforced.
  update = {enabled = false, versioned = true, root = "/var/lib/spacecross/system", repository = "OWNER/REPOSITORY",
    -- hashAddress = "data-card-address", -- optional when RPC crypto already supplies SHA256
    -- components = {"Core", "Autopilot", "Power", "Entity", "Defense"}, -- omit: retain installed profile, initially all
    -- actor = "Ship", -- defaults to this node certificate subject (requires client usage)
    peers = {"Ship"}, -- machine subjects permitted to request this publisher's files
    publishers = {
      -- ["publisher-modem-address"] = "UpdatePublisher", -- pinned address/subject; cert also needs _update.publish
    },
    -- cards = {"modem-address"}, -- omit: broadcast on every LAN card
    -- checkInterval = 3600, -- optional scheduled main check; local Check/remote model command also work
    interval = 0.1, collectTime = 3, quietTime = 1, maxCollectTime = 30,
    timeout = 120, maxClients = 64, maxRepairRounds = 3, repairInterval = 2},
}
