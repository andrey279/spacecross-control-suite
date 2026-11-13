local Cell = require("spacecross.terminal.cell")
local Frame = require("spacecross.terminal.frame")
local Text = require("spacecross.terminal.text")
local M = {}
function M.new(gpu, widthOf)
  local self = {}
  local function draw(frame)
    local maxW, maxH = gpu.maxResolution()
    assert(frame.width <= maxW and frame.height <= maxH, "CLIENT_SCREEN_TOO_SMALL")
    local w, h = gpu.getResolution()
    if w ~= frame.width or h ~= frame.height then gpu.setResolution(frame.width, frame.height) end
    for y = 1, frame.height do
      local x = 1
      while x <= frame.width do
        local first, fg, bg, flags = Cell.unpack(frame.cells[(y - 1) * frame.width + x])
        if flags >= 4 then x = x + 1
        else
          local start, text = x, {}
          fg = flags % 2 == 1 and frame.palette[fg + 1] or fg
          bg = math.floor(flags / 2) % 2 == 1 and frame.palette[bg + 1] or bg
          while x <= frame.width do
            local glyph, cf, cb, f = Cell.unpack(frame.cells[(y - 1) * frame.width + x])
            cf = f % 2 == 1 and frame.palette[cf + 1] or cf
            cb = math.floor(f / 2) % 2 == 1 and frame.palette[cb + 1] or cb
            if f >= 4 or cf ~= fg or cb ~= bg then break end
            text[#text + 1] = glyph
            x = x + math.max(1, widthOf and widthOf(glyph) or Text.width(glyph))
          end
          gpu.setForeground(fg, false); gpu.setBackground(bg, false)
          gpu.set(start, y, table.concat(text))
        end
      end
    end
  end
  function self:render(data, limits, expected)
    local frame, err = Frame.decode(data, limits, widthOf)
    if not frame then return nil, err end -- Validate everything before a hardware call.
    if expected and (frame.width ~= expected.width or frame.height ~= expected.height) then return nil, "EPROTOCOL" end
    local ok, result = pcall(draw, frame)
    if not ok then return nil, tostring(result) end
    return true
  end
  function self:capture()
    local w, h = gpu.getResolution()
    local state = {width = w, height = h, cells = {}, palette = {}}
    state.foreground, state.fgPalette = gpu.getForeground()
    state.background, state.bgPalette = gpu.getBackground()
    state.depth = gpu.getDepth()
    state.screen = gpu.getScreen()
    if gpu.getViewport then state.viewportWidth, state.viewportHeight = gpu.getViewport() end
    for y = 1, h do
      local x = 1
      while x <= w do
        local glyph, fg, bg = gpu.get(x, y)
        state.cells[(y - 1) * w + x] = Cell.pack(glyph, fg, bg, 0)
        local size = widthOf and widthOf(glyph) or Text.width(glyph)
        if size == 2 and x < w then state.cells[(y - 1) * w + x + 1] = Cell.pack("", fg, bg, 4) end
        x = x + math.max(1, size)
      end
    end
    return state
  end
  function self:restore(state)
    local ok, err = pcall(function()
      if state.screen ~= gpu.getScreen() then gpu.bind(state.screen, false) end
      if gpu.getDepth() ~= state.depth then gpu.setDepth(state.depth) end
      draw(state)
      if state.viewportWidth and gpu.setViewport then gpu.setViewport(state.viewportWidth, state.viewportHeight) end
      gpu.setForeground(state.foreground, state.fgPalette); gpu.setBackground(state.background, state.bgPalette)
    end)
    if not ok then return nil, tostring(err) end
    return true
  end
  return self
end
return M
