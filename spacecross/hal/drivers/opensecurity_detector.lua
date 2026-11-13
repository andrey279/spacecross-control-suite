-- Official OpenSecurity 1.7.10: component os_entdetector, scanPlayers(range,false).
return {id = "opensecurity_detector", types = {"os_entdetector"}, kind = "detector", new = function()
  local self = {}
  function self:init(proxy)
    assert(type(proxy.scanPlayers) == "function", "scanPlayers unavailable")
    self.proxy = proxy
    return true
  end
  function self:getEnergyLevel() return nil, "ENOTSUP" end
  function self:turn_off() return nil, "ENOTSUP" end
  function self:isOperational() return type(self.proxy.scanPlayers) == "function" end
  function self:scanPlayers(range)
    -- Always supply range: this legacy implementation halves its saved range per call.
    local raw, err = self.proxy.scanPlayers(range * 2, false)
    if type(raw) ~= "table" then return nil, err or "SCAN_FAILED" end
    local result = {}
    for _, entry in pairs(raw) do
      assert(type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "", "invalid detector record")
      result[#result + 1] = {name = entry.name, x = entry.x, y = entry.y, z = entry.z, range = entry.range}
    end
    return result
  end
  return self
end}
