# RFTools Shield Projector

`spacecross.hal.drivers.rftools_shield` registers `shield_projector` components
as HAL kind `shield`. Its status snapshot contains active/composed state and the
configured redstone mode. The exposed hardware callbacks do not provide shield
integrity or durability telemetry; `getEnergyLevel()` therefore returns
`nil, "ENOTSUP"`, and health is reported as unavailable.

Shield composition is a separate Owner command because it forms or breaks the
shield geometry. Turning a composed shield on/off uses an explicitly configured
OpenComputers redstone output and sets the projector to redstone `On` or `Off`
activation mode first. The binding must refer to a registered `redstone` HAL
driver. No output is changed if that binding is absent. Without a binding, the
driver still reports state and supports explicit compose/decompose and
redstone-mode operations, but `turn_on`/`turn_off` return `ENOTSUP`.

```lua
drivers = {
  "spacecross.hal.drivers.redstone",
  {module = "spacecross.hal.drivers.rftools_shield", options = {devices = {
    ["shield-projector-address"] = {controlAddress = "redstone-address", side = 3,
      activationMode = "On", onValue = 15, offValue = 0},
  }}}
}
shields = {enabled = true}
```

The `shields` model and UI combine multiple controller snapshots. Every change
is Owner-only on the target controller, including over authenticated RPC. The
UI refreshes state each time its tab is selected; it does not cache inactive
snapshots. Unit tests use component and redstone stubs. Verify callback names,
redstone response, and composition behavior in the actual 1.7.10 modpack before
enabling this control in-world.
