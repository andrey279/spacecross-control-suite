-- Data-only, bounded, length-prefixed format. Never executes received Lua.
local M = {}

function M.encode(value)
  local seen = {}
  local function encode(v, depth)
    assert(depth < 32, "maximum depth")
    local kind = type(v)
    if kind == "nil" then return "z" end
    if kind == "boolean" then return v and "t" or "f" end
    if kind == "number" then
      assert(v == v and math.abs(v) < math.huge, "nonfinite number")
      local s = string.format("%.17g", v)
      return "n" .. #s .. ":" .. s
    end
    if kind == "string" then return "s" .. #v .. ":" .. v end
    assert(kind == "table" and getmetatable(v) == nil and not seen[v], "unsupported value")
    seen[v] = true
    local entries = {}
    for k, item in pairs(v) do
      assert(type(k) == "string" or type(k) == "number", "invalid key")
      entries[#entries + 1] = {encode(k, depth + 1), encode(item, depth + 1)}
    end
    table.sort(entries, function(a, b) return a[1] < b[1] end)
    local out = {"a", tostring(#entries), ":"}
    for _, entry in ipairs(entries) do out[#out + 1] = entry[1] .. entry[2] end
    seen[v] = nil
    return table.concat(out)
  end
  return encode(value, 0)
end

function M.decode(data, limit)
  limit = limit or 65536
  if type(data) ~= "string" or #data > limit then return nil, "invalid size" end
  local pos, nodes = 1, 0
  local function count()
    local colon = data:find(":", pos, true)
    assert(colon and colon - pos <= 9, "invalid length")
    local raw = data:sub(pos, colon - 1)
    assert(raw:match("^%d+$"), "invalid length")
    pos = colon + 1
    return tonumber(raw)
  end
  local function parse(depth)
    nodes = nodes + 1
    assert(depth < 32 and nodes <= 8192, "too complex")
    local tag = data:sub(pos, pos)
    pos = pos + 1
    if tag == "z" then return nil end
    if tag == "t" then return true end
    if tag == "f" then return false end
    if tag == "s" or tag == "n" then
      local len = count()
      assert(pos + len - 1 <= #data, "truncated value")
      local value = data:sub(pos, pos + len - 1)
      pos = pos + len
      if tag == "s" then return value end
      value = tonumber(value)
      assert(value and value == value and math.abs(value) < math.huge, "invalid number")
      return value
    end
    assert(tag == "a", "invalid tag")
    local size, value, seen = count(), {}, {}
    assert(size <= 4096, "too many entries")
    for _ = 1, size do
      local key = parse(depth + 1)
      assert(type(key) == "string" or type(key) == "number", "invalid key")
      assert(not seen[key], "duplicate key")
      seen[key] = true
      local item = parse(depth + 1)
      assert(item ~= nil, "nil entry")
      value[key] = item
    end
    return value
  end
  local ok, value = pcall(parse, 0)
  if not ok then return nil, tostring(value) end
  if pos ~= #data + 1 then return nil, "trailing bytes" end
  return value
end

return M
