# HAL adapter for OpenModularTurrets

`spacecross.hal.drivers.omt_turret` provides a `turret` HAL instance for an OMT
component. Configure the component type names reported by the installed
Minecraft 1.7.10 mod build; the project does not guess version-specific names.
The adapter relies only on the `toggle()` and `setMode(mode)` methods named by
the project specification. It exposes `toggle`, `setMode`, and `getMode` through
HAL. `turn_on` and `turn_off` are available only when an active-state method has
been verified and configured, because calling a toggle blindly is not an
idempotent off/on operation.

The authenticated `turrets` model and UI are enabled with `turrets.enabled`.
All commands are Owner-only on the target machine. UI instances from selected
controllers are merged into one view, while each command retains its target
host and component address. The UI always offers `Toggle`; it offers `On` and
`Off` only when an active-state getter is explicitly configured. Mode buttons
appear only when a getter and a confirmed `modes` list are configured.

Optional method mappings enable status and energy telemetry after the exact
component proxy API has been checked in the target modpack:

```lua
{module = "spacecross.hal.drivers.omt_turret", options = {
  types = {"component-type-from-the-installed-build"},
  activeMethod = "verifiedActiveMethod",
  currentEnergyMethod = "verifiedCurrentEnergyMethod",
  maxEnergyMethod = "verifiedCapacityMethod",
  getModeMethod = "verifiedGetModeMethod",
  modes = {0, 1}, -- include only values confirmed for this exact mod build
}}
```

With no telemetry mappings, `getEnergyLevel()` and `getMode()` return
`nil, "ENOTSUP"`. The driver never selects a component by a guessed type name.
The adapter is unit-tested with a proxy stub; it has not been validated against
an in-game OMT 1.7.10 component. Add the verified type and optional method names
to configuration only after inspecting the installed build.

The currently available OMT wiki page labels its API as Minecraft 1.12.2, so it
does not establish 1.7.10 component names or callback signatures. The 1.7.10
adapter therefore leaves component type, state/energy getter names, and allowed
modes configurable, and fails closed when the active-state getter is absent.
