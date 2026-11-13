local util = require("spacecross.core.util")
local M = {}
local plugins = {
  power = function(endpoints) return require("spacecross.ui.power_tab")(endpoints) end,
  hardware = function(endpoints) return require("spacecross.ui.status_tab")("remote_hardware", endpoints) end,
  entities = function(endpoints) return require("spacecross.ui.status_tab")("remote_entities", endpoints) end,
  autopilot = function(endpoints) return require("spacecross.ui.autopilot_tab")(endpoints[1]) end,
  defense = function(endpoints) return require("spacecross.ui.defense_tab")(endpoints[1]) end,
  shields = function(endpoints) return require("spacecross.ui.shield_tab").new(endpoints) end,
  turrets = function(endpoints) return require("spacecross.ui.turret_tab").new(endpoints) end,
  satellite = function(endpoints) return require("spacecross.ui.satellite_tab").new(endpoints) end,
  structures = function(endpoints) return require("spacecross.ui.structures_tab").new(endpoints) end,
  update = function(endpoints) return require("spacecross.ui.update_tab")(endpoints[1]) end,
}
function M.supported(name) return plugins[name] ~= nil end
function M.new(deps)
  local self = {selections = {}}
  function self:open(panelId, host, model, player)
    if not plugins[model] or not deps.ui.panels[panelId] then return nil, "UNSUPPORTED_REMOTE_VIEW" end
    local catalog, err = deps.rpc:request(host, "_system", "models", player, {})
    if not catalog then return nil, err end
    local available = false
    for _, name in ipairs(catalog) do if name == model then available = true end end
    if not available then return nil, "ENOENT_REMOTE_MODEL" end
    local certificate = deps.rpc:peer(host)
    if not certificate then return nil, "UNVERIFIED_REMOTE_HOST" end
    local identity = certificate.public_key .. "\0" .. certificate.subject
    self.selections[panelId] = self.selections[panelId] or {}
    local groups = self.selections[panelId]
    groups[model] = groups[model] or {}
    local selected = groups[model]
    local found
    for index, endpoint in ipairs(selected) do if endpoint.identity == identity or endpoint.host == host then found = index; break end end
    local removedHost = found and selected[found].host
    if found then table.remove(selected, found)
    else selected[#selected + 1] = {host = host, model = model, identity = identity} end
    local tabId = "remote_" .. model
    local panel = deps.ui.panels[panelId]
    if panel.tabs[tabId] then deps.ui:removeTab(panelId, tabId) end
    -- Multi-host status/energy views merge all selected endpoints. Command views
    -- keep a separate tab per selected host so commands always have one target.
    if model == "autopilot" or model == "defense" or model == "update" then
      if removedHost then
        local id = tabId .. "_" .. removedHost
        if panel.tabs[id] then deps.ui:removeTab(panelId, id) end
      end
      if #selected == 0 then return true end
      for _, endpoint in ipairs(selected) do
        local id = tabId .. "_" .. endpoint.host
        if not panel.tabs[id] then
          local tab = plugins[model]({endpoint}); tab.id = id; deps.ui:addTab(panelId, tab)
        end
      end
      local last = selected[#selected]
      return deps.ui:select(panelId, tabId .. "_" .. last.host)
    end
    if #selected == 0 then return true end
    local endpoints = {}
    for _, item in ipairs(selected) do endpoints[#endpoints + 1] = {host = item.host, model = model} end
    local tab = plugins[model](endpoints); tab.id = tabId
    deps.ui:addTab(panelId, tab)
    return deps.ui:select(panelId, tabId)
  end
  function self:list()
    local out = {}
    for panel, groups in pairs(self.selections) do
      out[panel] = {}
      for model, endpoints in pairs(groups) do
        out[panel][model] = {}
        for _, item in ipairs(endpoints) do out[panel][model][#out[panel][model] + 1] = {host = item.host, model = model} end
      end
    end
    return util.copy(out)
  end
  return self
end
return M
