local M = {}
local function byte24(value)
  assert(type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 0xffffff, "invalid RGB color")
  return string.char(math.floor(value / 65536), math.floor(value / 256) % 256, value % 256)
end
local function number24(value, offset)
  local a, b, c = value:byte(offset, offset + 2)
  return a * 65536 + b * 256 + c
end
function M.pack(glyph, foreground, background, flags)
  assert(type(glyph) == "string" and #glyph <= 64 and flags >= 0 and flags <= 7, "invalid cell")
  return string.char(#glyph) .. byte24(foreground) .. byte24(background) .. string.char(flags) .. glyph
end
function M.unpack(cell)
  assert(type(cell) == "string" and #cell >= 8 and cell:byte(1) <= 64 and #cell == cell:byte(1) + 8 and cell:byte(8) <= 7, "invalid cell")
  return cell:sub(9), number24(cell, 2), number24(cell, 5), cell:byte(8)
end
return M
