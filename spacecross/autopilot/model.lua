local util = require("spacecross.core.util")
local valid = require("spacecross.autopilot.autopilot_core").validPosition
return function(autopilot, config)
  local draft = util.copy((config or {}).target or {x = 0, y = 64, z = 0})
  assert(valid(draft), "invalid configured target")
  return {snapshot = function()
    local value = autopilot:snapshot(); value.draft = util.copy(draft); return value
  end, command = function(_, action, args)
    if action == "setTarget" then
      if not valid(args.target) then return nil, "INVALID_TARGET" end
      draft = util.copy(args.target); return true
    elseif action == "adjustTarget" then
      if args.axis ~= "x" and args.axis ~= "y" and args.axis ~= "z" then return nil, "INVALID_AXIS" end
      if type(args.delta) ~= "number" or args.delta % 1 ~= 0 then return nil, "INVALID_DELTA" end
      local updated = util.copy(draft); updated[args.axis] = updated[args.axis] + args.delta
      if not valid(updated) then return nil, "INVALID_TARGET" end
      draft = updated; return true
    elseif action == "go" then return autopilot:navigate(draft, args.controller)
    elseif action == "navigate" then return autopilot:navigate(args.target, args.controller)
    elseif action == "route" then return autopilot:setRoute(args.route, args.controller)
    elseif action == "cancel" then return autopilot:cancel()
    elseif action == "stopAutopilot" then return autopilot:stop()
    elseif action == "startAutopilot" then return autopilot:start()
    end
    return nil, "ENOTSUP"
  end}
end
