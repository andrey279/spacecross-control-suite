return function(endpoint, panelId)
  local targets = {}
  return {id = "network", endpoints = {endpoint}, deactivate = function() targets = {} end,
    draw = function(gpu, rows, failures, width, height)
    targets = {}
    local y = 3
    local function line(value)
      if y < height then gpu.set(2, y, value:sub(1, width - 2)); y = y + 1 end
    end
    line("Network")
    if #rows ~= 1 then line("Unavailable"); return end
    local data = rows[1].data
    line("Cards: " .. #data.cards .. " Hosts: " .. #data.hosts)
    line("Discovery: unverified")
    -- Display component addresses, which are validated ASCII routing identities.
    for _, host in ipairs(data.hosts) do
      for _, model in ipairs(host.type or {}) do
        if require("spacecross.ui.remote_views").supported(model) and y < height then
          targets[y] = {host = host.address, model = model}
          line(model .. " @ " .. host.address)
        end
      end
    end
  end, input = function(signal, command)
    if signal[1] ~= "touch" or not targets[signal[4]] then return nil, "ENOTSUP" end
    local target = targets[signal[4]]
    return command(endpoint, "openRemote", {panel = panelId, host = target.host, model = target.model})
  end}
end
