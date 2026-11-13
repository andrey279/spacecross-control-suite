local Text = require("spacecross.terminal.text")
local Cell = require("spacecross.terminal.cell")
local M = {}
local function integer(value) return type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) < math.huge end
function M.new(config, widthOf)
  config = config or {}
  local maxWidth, maxHeight = config.maxWidth or 160, config.maxHeight or 50
  assert(integer(maxWidth) and integer(maxHeight) and maxWidth >= 1 and maxWidth <= 160 and maxHeight >= 1 and maxHeight <= 50)
  local width, height, foreground, background, fgPalette, bgPalette, depth = config.width or 80, config.height or 25, 0xffffff, 0, false, false, 8
  assert(integer(width) and integer(height) and width >= 1 and height >= 1 and width <= maxWidth and height <= maxHeight)
  local viewportWidth, viewportHeight = width, height
  local palette = {0x000000, 0x0000aa, 0x00aa00, 0x00aaaa, 0xaa0000, 0xaa00aa, 0xffaa00, 0xaaaaaa,
    0x555555, 0x5555ff, 0x55ff55, 0x55ffff, 0xff5555, 0xff55ff, 0xffff55, 0xffffff}
  local self = {address = config.address or "spacecross-virtual-gpu", type = "gpu", generation = 0, cells = {}, palette = palette}
  local screen = config.screen or "spacecross-virtual-screen"
  local function flags() return (fgPalette and 1 or 0) + (bgPalette and 2 or 0) end
  local function blank() return Cell.pack(" ", foreground, background, flags()) end
  local function glyphWidth(glyph)
    local n = widthOf and widthOf(glyph) or Text.width(glyph)
    assert(n == 0 or n == 1 or n == 2, "invalid character width"); return n
  end
  local function inside(x, y) return x >= 1 and x <= width and y >= 1 and y <= height end
  local function index(x, y) return (y - 1) * width + x end
  local function clearWide(x, y)
    if not inside(x, y) then return end
    local _, _, _, f = Cell.unpack(self.cells[index(x, y)])
    if f >= 4 and x > 1 then self.cells[index(x - 1, y)] = blank() end
    if x < width then
      local _, _, _, nextFlags = Cell.unpack(self.cells[index(x + 1, y)])
      if nextFlags >= 4 then self.cells[index(x + 1, y)] = blank() end
    end
  end
  local function put(x, y, glyph, glyphWidth)
    if not inside(x, y) then return end
    clearWide(x, y)
    if glyphWidth == 2 and x == width then self.cells[index(x, y)] = blank(); return end
    if glyphWidth == 2 then clearWide(x + 1, y) end
    self.cells[index(x, y)] = Cell.pack(glyph, foreground, background, flags())
    if glyphWidth == 2 then self.cells[index(x + 1, y)] = Cell.pack("", foreground, background, flags() + 4) end
  end
  function self.getScreen() return screen end
  function self.bind(address, reset)
    assert(address == screen, "virtual GPU has one session screen")
    if reset ~= false then self.fill(1, 1, width, height, " ") end
    return true
  end
  function self.maxResolution() return maxWidth, maxHeight end
  function self.getResolution() return width, height end
  function self.getViewport() return viewportWidth, viewportHeight end
  function self.setViewport(w, h)
    assert(integer(w) and integer(h) and w >= 1 and h >= 1 and w <= width and h <= height, "invalid viewport")
    viewportWidth, viewportHeight = w, h; return true
  end
  function self.setResolution(w, h)
    assert(integer(w) and integer(h) and w >= 1 and h >= 1 and w <= maxWidth and h <= maxHeight, "invalid resolution")
    if w == width and h == height then return false end
    local old, oldWidth, oldHeight = self.cells, width, height
    width, height, viewportWidth, viewportHeight = w, h, w, h
    self.cells = {}
    for y = 1, h do for x = 1, w do
      self.cells[index(x, y)] = x <= oldWidth and y <= oldHeight and old[(y - 1) * oldWidth + x] or blank()
    end end
    -- A truncated double-width glyph must not leave a half-cell at the edge.
    for y = 1, height do
      local glyph = Cell.unpack(self.cells[index(width, y)])
      if glyph ~= "" and (widthOf and widthOf(glyph) or Text.width(glyph)) == 2 then self.cells[index(width, y)] = blank() end
    end
    self.generation = self.generation + 1; return true
  end
  function self.maxDepth() return 8 end
  function self.getDepth() return depth end
  function self.setDepth(value) assert(value == 1 or value == 4 or value == 8); local old = depth; depth = value; return old end
  function self.getPaletteColor(i) assert(integer(i) and i >= 0 and i < 16); return palette[i + 1] end
  function self.setPaletteColor(i, value)
    assert(integer(i) and i >= 0 and i < 16 and integer(value) and value >= 0 and value <= 0xffffff)
    local old = palette[i + 1]; palette[i + 1] = value; self.generation = self.generation + 1; return old
  end
  function self.getForeground() return foreground, fgPalette end
  function self.getBackground() return background, bgPalette end
  local function color(value, pal)
    assert(integer(value) and value >= 0 and value <= (pal and 15 or 0xffffff) and not (pal and depth == 1), "invalid color")
    return value, pal == true
  end
  function self.setForeground(value, pal)
    local old, oldPalette = foreground, fgPalette; foreground, fgPalette = color(value, pal); return old, oldPalette
  end
  function self.setBackground(value, pal)
    local old, oldPalette = background, bgPalette; background, bgPalette = color(value, pal); return old, oldPalette
  end
  function self.get(x, y)
    assert(integer(x) and integer(y) and inside(x, y), "invalid coordinates")
    local glyph, fg, bg, f = Cell.unpack(self.cells[index(x, y)])
    local fp, bp = f % 2 == 1, math.floor(f / 2) % 2 == 1
    return glyph == "" and " " or glyph, fp and palette[fg + 1] or fg, bp and palette[bg + 1] or bg, fp and fg or nil, bp and bg or nil
  end
  function self.set(x, y, value, vertical)
    assert(integer(x) and integer(y) and type(value) == "string")
    local previousX, previousY
    for _, character in ipairs(Text.characters(value)) do
      local size = glyphWidth(character.text)
      if size == 0 and previousX and inside(previousX, previousY) then
        local old = Cell.unpack(self.cells[index(previousX, previousY)])
        if #old + #character.text <= 64 then put(previousX, previousY, old .. character.text, glyphWidth(old)) end
      elseif size > 0 then
        put(x, y, character.text, size); previousX, previousY = x, y
        if vertical then y = y + 1 else x = x + size end
      end
    end
    self.generation = self.generation + 1; return true
  end
  function self.fill(x, y, w, h, glyph)
    assert(integer(x) and integer(y) and integer(w) and integer(h))
    assert(#Text.characters(glyph) == 1, "single fill character required")
    local size = glyphWidth(glyph)
    assert(size > 0, "invalid fill width")
    for row = math.max(1, y), math.min(height, y + math.max(0, h) - 1) do
      local right = math.min(width, x + math.max(0, w) - 1)
      for col = math.max(1, x), right, size do put(col, row, size == 2 and col == right and " " or glyph, size == 2 and col == right and 1 or size) end
    end
    self.generation = self.generation + 1; return true
  end
  function self.copy(x, y, w, h, tx, ty)
    assert(integer(x) and integer(y) and integer(w) and integer(h) and integer(tx) and integer(ty))
    local snapshot = {}
    for row = math.max(1, y, 1 - ty), math.min(height, y + math.max(0, h) - 1, height - ty) do
      for col = math.max(1, x, 1 - tx), math.min(width, x + math.max(0, w) - 1, width - tx) do
      if inside(col, row) and inside(col + tx, row + ty) then snapshot[#snapshot + 1] = {index(col + tx, row + ty), self.cells[index(col, row)]} end
    end end
    for _, cell in ipairs(snapshot) do self.cells[cell[1]] = cell[2] end
    -- Copy may crop either half of a wide character. Repair both rectangle edges.
    for row = 1, height do for col = 1, width do
      local i = index(col, row)
      local glyph, _, _, f = Cell.unpack(self.cells[i])
      if f >= 4 then
        local previous, pfColor, pbColor, pf = Cell.unpack(self.cells[index(math.max(1, col - 1), row)])
        if col == 1 or pf >= 4 or glyphWidth(previous) ~= 2 then self.cells[i] = blank()
        else self.cells[i] = Cell.pack("", pfColor, pbColor, pf + 4) end
      elseif glyphWidth(glyph) == 2 then
        local _, _, _, nf = Cell.unpack(self.cells[index(math.min(width, col + 1), row)])
        if col == width or nf < 4 then self.cells[i] = blank() end
      end
    end end
    self.generation = self.generation + 1; return true
  end
  for i = 1, width * height do self.cells[i] = blank() end
  return self
end
return M
