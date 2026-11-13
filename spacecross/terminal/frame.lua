local Cell = require("spacecross.terminal.cell")
local Text = require("spacecross.terminal.text")
local M = {}
local function u16(n) return string.char(math.floor(n / 256), n % 256) end
local function read16(data, offset)
  local a, b = data:byte(offset, offset + 1); assert(a and b, "truncated frame"); return a * 256 + b
end
function M.encode(gpu)
  local width, height = gpu.getResolution()
  local result = {"SCT1", u16(width), u16(height)}
  for i = 1, 16 do
    local value = gpu.getPaletteColor(i - 1)
    result[#result + 1] = string.char(math.floor(value / 65536), math.floor(value / 256) % 256, value % 256)
  end
  local index = 1
  while index <= width * height do
    local cell, count = gpu.cells[index], 1
    while count < 65535 and index + count <= width * height and gpu.cells[index + count] == cell do count = count + 1 end
    result[#result + 1] = u16(count) .. cell
    index = index + count
  end
  return table.concat(result)
end
function M.decode(data, limits, widthOf)
  limits = limits or {}
  local ok, result = pcall(function()
    assert(type(data) == "string" and #data <= (limits.maxBytes or 600000) and data:sub(1, 4) == "SCT1", "invalid frame")
    local width, height = read16(data, 5), read16(data, 7)
    assert(width >= 1 and height >= 1 and width <= (limits.maxWidth or 160) and height <= (limits.maxHeight or 50)
      and width * height <= (limits.maxCells or 8000), "frame dimensions exceed limit")
    local frame, pos = {width = width, height = height, palette = {}, cells = {}}, 9
    for i = 1, 16 do
      local a, b, c = data:byte(pos, pos + 2); assert(c, "truncated palette")
      frame.palette[i] = a * 65536 + b * 256 + c; pos = pos + 3
    end
    while pos <= #data do
      local count, length = read16(data, pos), data:byte(pos + 2)
      assert(length and length <= 64 and count > 0 and #frame.cells + count <= width * height, "invalid run")
      local cell = data:sub(pos + 2, pos + 9 + length)
      local glyph, fg, bg, flags = Cell.unpack(cell)
      if flags % 2 == 1 then assert(fg <= 15, "invalid palette index") end
      if math.floor(flags / 2) % 2 == 1 then assert(bg <= 15, "invalid palette index") end
      if flags >= 4 then assert(glyph == "", "invalid wide continuation")
      else assert(#Text.characters(glyph) >= 1, "empty glyph") end
      for _ = 1, count do frame.cells[#frame.cells + 1] = cell end
      pos = pos + 10 + length
    end
    assert(#frame.cells == width * height, "incomplete frame")
    local continuation
    for i, cell in ipairs(frame.cells) do
      local glyph, fg, bg, flags = Cell.unpack(cell)
      if flags >= 4 then
        assert(continuation and continuation == Cell.pack("", fg, bg, flags), "orphan wide continuation")
        continuation = nil
      else
        assert(not continuation, "missing wide continuation")
        local characters = Text.characters(glyph)
        local size = widthOf and widthOf(characters[1].text) or Text.width(characters[1])
        assert(size == 1 or size == 2, "invalid base glyph")
        for k = 2, #characters do assert((widthOf and widthOf(characters[k].text) or Text.width(characters[k])) == 0, "multiple base glyphs") end
        if size == 2 then
          assert(i % width ~= 0, "wide glyph at right edge")
          continuation = Cell.pack("", fg, bg, flags + 4)
        end
      end
    end
    assert(not continuation, "missing final continuation")
    return frame
  end)
  if not ok then return nil, tostring(result) end
  return result
end
return M
