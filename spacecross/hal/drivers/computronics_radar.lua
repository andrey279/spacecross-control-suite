local M = {}

local function validMethod(value)
  return type(value) == "string" and value:match("^[%a_][%w_]*$") ~= nil
end

local function validTypes(types)
  assert(type(types) == "table" and #types > 0 and #types <= 16, "configure Computronics Radar component types")
  local seen = {}
  for _, value in ipairs(types) do
    assert(type(value) == "string" and value:match("^[%w_-]+$") and not seen[value], "invalid Computronics Radar component type")
    seen[value] = true
  end
  return types
end

function M.configure(options)
  options = options or {}
  local allowed = {types=true, method=true, passRange=true, nameField=true, nameFromKey=true,
    xField=true, yField=true, zField=true, rangeField=true}
  for key in pairs(options) do assert(allowed[key], "unknown Computronics Radar option: " .. tostring(key)) end
  local types = validTypes(options.types or {"radar"})
  local method = options.method or "getPlayers"
  assert(validMethod(method), "invalid Computronics Radar scan method")
  assert(not (options.nameField and options.nameFromKey), "choose either nameField or nameFromKey")
  local nameField = options.nameField or "name"
  assert((type(nameField) == "string" and nameField ~= "") or options.nameFromKey == true,
    "configure nameField or nameFromKey for radar records")
  for _, key in ipairs({"xField", "yField", "zField", "rangeField"}) do
    if options[key] ~= nil then assert(type(options[key]) == "string" and options[key] ~= "", "invalid " .. key) end
  end
  local passRange = options.passRange
  if passRange ~= nil then assert(type(passRange) == "boolean", "passRange must be boolean") end
  if passRange == nil then passRange = true end

  return {id = "computronics_radar", types = types, kind = "detector", new = function()
    local self = {}
    function self:init(proxy)
      assert(type(proxy[method]) == "function", "configured Computronics Radar method unavailable")
      self.proxy = proxy
      return true
    end
    function self:getEnergyLevel() return nil, "ENOTSUP" end
    function self:turn_off() return nil, "ENOTSUP" end
    function self:isOperational() return type(self.proxy[method]) == "function" end
    function self:scanPlayers(range)
      local raw, err
      if passRange then raw, err = self.proxy[method](range)
      else raw, err = self.proxy[method]() end
      if type(raw) ~= "table" then return nil, err or "SCAN_FAILED" end
      local result = {}
      for key, entry in pairs(raw) do
        if type(entry) ~= "table" then return nil, "INVALID_RADAR_RECORD" end
        local name = options.nameFromKey and key or entry[nameField]
        if type(name) ~= "string" or name == "" then return nil, "INVALID_RADAR_NAME" end
        local item = {name = name}
        for _, field in ipairs({{"xField", "x"}, {"yField", "y"}, {"zField", "z"}, {"rangeField", "range"}}) do
          local source = options[field[1]]
          if source then
            local value = entry[source]
            if type(value) ~= "number" then return nil, "INVALID_RADAR_" .. field[2]:upper() end
            item[field[2]] = value
          end
        end
        result[#result + 1] = item
      end
      return result
    end
    return self
  end}
end

return M
