local arguments = rawget(_G, "arg") or {...}
local root = arguments[1] or "."
local list = assert(io.open(root .. "/install.list", "r"))
local count = 0
for path in list:lines() do
  assert(loadfile(root .. "/" .. path, "t", {}))
  count = count + 1
end
list:close()
print("Syntax OK: " .. count .. " Lua files")
