-- Pure client-side association/actor filter. The server supplies its own actor.
local M = {}
function M.new(actor, screen, keyboards)
  local allowed, codes = {}, {}
  for _, address in ipairs(keyboards) do allowed[address] = true end
  return function(signal)
    local name, source = signal[1], signal[2]
    local keyboard = name == "key_down" or name == "key_up" or name == "clipboard"
    local pointer = name == "touch" or name == "drag" or name == "drop" or name == "scroll"
    if not keyboard and not pointer or keyboard and not allowed[source] or pointer and source ~= screen then return end
    local player = signal[name == "clipboard" and 4 or keyboard and 5 or 6]
    if type(player) ~= "string" or player:lower() ~= actor:lower() then return end
    if name == "key_down" or name == "key_up" then
      codes[signal[4]] = name == "key_down" and true or nil
      if (codes[29] or codes[157]) and (codes[56] or codes[184]) and signal[4] == 16 then return nil, "detach" end
      return {name = name, char = signal[3], code = signal[4]}
    elseif name == "clipboard" then return {name = name, text = signal[3]} end
    return {name = name, x = signal[3], y = signal[4], button = signal[5]}
  end
end
return M
