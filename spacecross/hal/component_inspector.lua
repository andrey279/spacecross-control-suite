-- Read-only OpenComputers component/method inventory for hardware validation.
local M = {}

local function sortedKeys(values)
  local keys = {}
  for key in pairs(values or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function matches(address, componentType, filters)
  if not filters or #filters == 0 then return true end
  local haystack = (tostring(address) .. " " .. tostring(componentType)):lower()
  for _, filter in ipairs(filters) do
    if haystack:find(tostring(filter):lower(), 1, true) then return true end
  end
  return false
end

function M.collect(component, filters)
  assert(type(component) == "table" and type(component.list) == "function", "OpenComputers component API required")
  local report = {}
  for address, componentType in component.list() do
    if matches(address, componentType, filters) then
      local item = {address = tostring(address), type = tostring(componentType), methods = {}}
      if type(component.methods) == "function" then
        local ok, methods = pcall(component.methods, address)
        if ok and type(methods) == "table" then
          for _, method in ipairs(sortedKeys(methods)) do
            local entry = {name = tostring(method), direct = methods[method] == true}
            if type(component.doc) == "function" then
              local docOk, doc = pcall(component.doc, address, method)
              if docOk and type(doc) == "string" and doc ~= "" then entry.documentation = doc end
            end
            item.methods[#item.methods + 1] = entry
          end
        else
          item.error = "METHOD_ENUMERATION_FAILED: " .. tostring(methods)
        end
      else
        item.error = "METHOD_ENUMERATION_UNAVAILABLE"
      end
      report[#report + 1] = item
    end
  end
  table.sort(report, function(a, b)
    if a.type == b.type then return a.address < b.address end
    return a.type < b.type
  end)
  return report
end

function M.render(report)
  assert(type(report) == "table", "component report required")
  local lines = {"SpaceCross read-only component inventory"}
  if #report == 0 then lines[#lines + 1] = "No matching components." end
  for _, component in ipairs(report) do
    lines[#lines + 1] = "COMPONENT type=" .. component.type .. " address=" .. component.address
    if component.error then lines[#lines + 1] = "  ERROR " .. component.error end
    for _, method in ipairs(component.methods or {}) do
      lines[#lines + 1] = "  METHOD " .. method.name .. " dispatch=" .. (method.direct and "direct" or "invoke")
      if method.documentation then
        for line in (method.documentation .. "\n"):gmatch("(.-)\n") do
          lines[#lines + 1] = "    " .. line
        end
      end
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
