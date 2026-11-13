return function()
  local self = {width = 40, height = 12, calls = {}}
  function self.bind(address) self.screen = address; return true end
  function self.getResolution() return self.width, self.height end
  function self.fill(...) self.calls[#self.calls + 1] = {"fill", ...}; return true end
  function self.set(...) self.calls[#self.calls + 1] = {"set", ...}; return true end
  return self
end
