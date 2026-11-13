# Structure deployment

`spacecross.structures.deployer` sequences a validated route through the existing
autopilot API. At each waypoint it waits for navigation to finish, calls the
deployment adapter, provisions the configured program on the structure's own
computer, then waits for an explicit confirmation before advancing. Adapters may
return `nil, "PENDING"` while asynchronous construction or provisioning runs;
errors stop the route without claiming the waypoint succeeded. Route input is
bounded to 256 integer-coordinate points.

Enable `structures.enabled` only with `autopilot.enabled`. For direct component
access, configure `structures.hardware` with a builder address and exact deploy
and mandatory confirmation method names, plus either a fixed computer address or the
receipt field that contains the newly built computer's address and its exact
provision method. The adapter passes the program ID and waypoint to provisioning;
it uses the deployment receipt to resolve the new computer address and passes
the receipt to confirmation. The host may instead inject `structureDeploy`,
`structureProvision`, and `structureConfirm` adapters.

The provisioner must verify the destination computer identity and installed
program generation, and retries should be idempotent for each waypoint. Component names and method signatures remain explicit; no
drone, builder, or computer API is guessed. Physical deployment and remote
computer provisioning remain in-game integration gates.
