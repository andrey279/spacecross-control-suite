local M = {}
local inputPlayers = {touch = 6, drag = 6, drop = 6, scroll = 6, key_down = 5, key_up = 5, clipboard = 4}

function M.new(deps)
  local self = {panels = {}}
  function self:addPanel(id, gpu, screen, player)
    assert(not self.panels[id], "duplicate panel")
    for _, panel in pairs(self.panels) do assert(panel.gpu ~= gpu, "GPU already assigned") end
    local ok, err = gpu.bind(screen, false)
    assert(ok, err)
    self.panels[id] = {gpu = gpu, screen = screen, player = player, tabs = {}, tabOrder = {}}
  end
  function self:addTab(panelId, tab)
    local panel = assert(self.panels[panelId])
    assert(not panel.tabs[tab.id] and type(tab.draw) == "function")
    panel.tabs[tab.id] = tab -- only endpoint descriptions and view functions; no model state
    panel.tabOrder[#panel.tabOrder + 1] = tab.id
  end
  function self:removeTab(panelId, tabId)
    local panel = assert(self.panels[panelId])
    local tab = panel.tabs[tabId]
    if not tab then return false end
    if tab.deactivate then tab.deactivate() end
    panel.tabs[tabId] = nil
    for index, id in ipairs(panel.tabOrder) do if id == tabId then table.remove(panel.tabOrder, index); break end end
    if panel.active == tabId then panel.active = panel.tabOrder[1] end
    return true
  end
  local function refresh(panelId)
    local panel = assert(self.panels[panelId])
    local tab = panel.active and panel.tabs[panel.active]
    if not tab then return nil, "ENOENT_TAB" end
    local width, height = panel.gpu.getResolution()
    if width < 4 or height < 4 then return nil, "SCREEN_TOO_SMALL" end
    if panel.width ~= width or panel.height ~= height then
      panel.width, panel.height = width, height
      panel.gpu.fill(1, 1, width, height, " ")
      if deps.static then deps.static(panel.gpu, width, height) end
    end
    local rows, failures = {}, {}
    for _, endpoint in ipairs(tab.endpoints or {}) do
      local ok, result, err = pcall(deps.request, endpoint, "snapshot", panel.player)
      if ok and result ~= nil then
        rows[#rows + 1] = {host = endpoint.host, model = endpoint.model, data = result}
      else failures[#failures + 1] = {host = endpoint.host, error = tostring(ok and err or result)} end
    end
    if self.panels[panelId] ~= panel or panel.tabs[panel.active] ~= tab then return nil, "VIEW_CHANGED" end
    panel.gpu.fill(2, 2, width - 2, height - 2, " ")
    local x = 2
    panel.tabTargets = {}
    local start = 1
    for index, id in ipairs(panel.tabOrder) do if id == panel.active then start = index; break end end
    for offset = 0, #panel.tabOrder - 1 do
      local id = panel.tabOrder[(start + offset - 1) % #panel.tabOrder + 1]
      local label = (id == panel.active and "[" .. id .. "]" or " " .. id .. " ")
      if offset == 0 then label = label:sub(1, width - 2) end
      if x + #label <= width then
        panel.gpu.set(x, 2, label)
        panel.tabTargets[#panel.tabTargets + 1] = {id = id, first = x, last = x + #label - 1}
        x = x + #label + 1
      end
    end
    tab.draw(panel.gpu, rows, failures, width, height)
    -- rows are discarded after drawing. Returning to this tab always queries again.
    return true
  end
  function self:refresh(panelId)
    local panel = assert(self.panels[panelId])
    if panel.refreshing then return nil, "EBUSY" end
    panel.refreshing = true
    local ok, value, err = pcall(refresh, panelId)
    panel.refreshing = false
    if not ok then error(value, 0) end
    return value, err
  end
  function self:select(panelId, tabId)
    local panel = assert(self.panels[panelId])
    if not panel.tabs[tabId] then return nil, "ENOENT_TAB" end
    if panel.active ~= tabId then
      local old = panel.active and panel.tabs[panel.active]
      if old and old.deactivate then old.deactivate() end
    end
    panel.active = tabId
    return self:refresh(panelId)
  end
  function self:input(panelId, signal)
    local index = inputPlayers[signal[1]]
    local player = index and signal[index]
    if type(player) ~= "string" or player == "" or not deps.authorize(player, signal[1]) then
      return nil, "EACCES"
    end
    local panel = assert(self.panels[panelId])
    if signal[1] == "touch" or signal[1] == "drag" or signal[1] == "drop" or signal[1] == "scroll" then
      if signal[2] ~= panel.screen then return nil, "WRONG_SCREEN" end
    elseif deps.keyboardScreen and deps.keyboardScreen(signal[2]) ~= panel.screen then
      return nil, "WRONG_SCREEN"
    end
    local direction
    if signal[1] == "scroll" and signal[4] == 2 then direction = signal[5] > 0 and -1 or 1 end
    if signal[1] == "key_down" and signal[4] == 203 then direction = -1 end
    if signal[1] == "key_down" and signal[4] == 205 then direction = 1 end
    if direction and #panel.tabOrder > 0 then
      for index, id in ipairs(panel.tabOrder) do
        if id == panel.active then return self:select(panelId, panel.tabOrder[(index + direction - 1) % #panel.tabOrder + 1]) end
      end
    end
    if signal[1] == "touch" and signal[4] == 2 then
      for _, target in ipairs(panel.tabTargets or {}) do
        if signal[3] >= target.first and signal[3] <= target.last then return self:select(panelId, target.id) end
      end
    end
    local tab = panel.tabs[panel.active]
    if not tab or not tab.input then return nil, "ENOTSUP" end
    local function command(endpoint, action, args)
      return deps.request(endpoint, action, player, args)
    end
    return tab.input(signal, command)
  end
  return self
end
return M
