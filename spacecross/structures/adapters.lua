-- Exact, configured component bindings for structure build/provision operations.
-- API names and signatures stay configurable across legacy builder mods.
local M = {}
local function address(value, optional)
  if value == nil and optional then return nil end
  assert(type(value) == "string" and value:match("^[%w%-]+$"), "invalid structure component address")
  return value
end
local function method(value, optional)
  if value == nil and optional then return nil end
  assert(type(value) == "string" and value:match("^[%a_][%w_]*$"), "invalid structure component method")
  return value
end

function M.new(deps, config)
  config = config or {}; local component = assert(deps.component)
  local builder = {address = address(config.builder and config.builder.address),
    deploy = method(config.builder and config.builder.deploy), confirm = method(config.builder and config.builder.confirm)}
  local computer = {address = address(config.computer and config.computer.address, true),
    addressField = method(config.computer and config.computer.addressField, true),
    provision = method(config.computer and config.computer.provision)}
  assert(computer.address or computer.addressField, "configure a computer address or receipt field")
  local function proxy(addr, methodName)
    local ok, value = pcall(component.proxy, addr)
    if not ok or not value then return nil, "COMPONENT_UNAVAILABLE" end
    if type(value[methodName]) ~= "function" then return nil, "METHOD_UNAVAILABLE" end
    return value
  end
  local function invoke(addr, methodName, ...)
    local device, err = proxy(addr, methodName); if not device then return nil, err end
    local ok, result, detail = pcall(device[methodName], ...)
    if not ok then return nil, tostring(result) end
    if result == false or result == nil and detail ~= nil then return result, detail or "COMPONENT_REJECTED" end
    if result == nil then return true end -- Void component methods may succeed without a result.
    return result, detail
  end
  local function computerAddress(receipt)
    if computer.address then return computer.address end
    if type(receipt) ~= "table" or type(receipt[computer.addressField]) ~= "string" then return nil end
    return address(receipt[computer.addressField])
  end
  local self = {}
  function self:deploy(target, index)
    return invoke(builder.address, builder.deploy, target, index)
  end
  function self:provision(target, program, index, receipt)
    if type(program) ~= "string" or not program:match("^[%w_.%-]+$") then return nil, "INVALID_PROGRAM" end
    local addr = computerAddress(receipt)
    if not addr then return nil, "STRUCTURE_COMPUTER_UNKNOWN" end
    return invoke(addr, computer.provision, program, target, index)
  end
  function self:confirm(target, index, receipt)
    return invoke(builder.address, builder.confirm, target, index, receipt)
  end
  return self
end
return M
