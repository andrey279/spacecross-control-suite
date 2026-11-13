local GPU = require("spacecross.terminal.gpu")
local Frame = require("spacecross.terminal.frame")
local Cell = require("spacecross.terminal.cell")
local Renderer = require("spacecross.terminal.renderer")
local H = require("tests.support")
local function unicode_colors_overlap_and_clipping()
  local g = GPU.new({width = 8, height = 3})
  g.setPaletteColor(2, 0x123456); g.setForeground(2, true); g.setBackground(0x123)
  g.set(1, 1, "A界éБ")
  local glyph, fg, bg, palette = g.get(2, 1)
  assert(glyph == "界" and fg == 0x123456 and bg == 0x123 and palette == 2)
  assert(g.get(4, 1) == "é" and g.get(5, 1) == "Б")
  g.set(3, 1, "x"); assert(g.get(2, 1) == " " and g.get(3, 1) == "x")
  g.set(1, 2, "12345678"); g.copy(1, 2, 7, 1, 1, 0)
  assert(g.get(2, 2) == "1" and g.get(8, 2) == "7")
  -- Huge requested rectangles are clipped before looping, including both offsets.
  g.copy(-1000000, -1000000, 2000000, 2000000, 0, 0)
  g.fill(1, 3, 3, 1, "界"); assert(g.get(1, 3) == "界" and g.get(3, 3) == " " and g.get(4, 3) == " ")
  assert(Frame.decode(Frame.encode(g)))
  return H.success()
end
local function cropped_wide_copy_and_resize_remain_valid()
  local g = GPU.new({width = 8, height = 2})
  g.set(2, 1, "界"); g.copy(3, 1, 1, 1, 2, 0)
  assert(g.get(5, 1) == " " and Frame.decode(Frame.encode(g)))
  g.copy(2, 1, 1, 1, 4, 0); assert(g.get(6, 1) == " " and Frame.decode(Frame.encode(g)))
  g.set(7, 2, "界"); g.setResolution(7, 2)
  assert(g.get(7, 2) == " " and Frame.decode(Frame.encode(g)))
  g.setResolution(8, 2); g.set(7, 2, "界"); g.copy(1, 2, 7, 1, 1, 0)
  assert(Frame.decode(Frame.encode(g)))
  return H.success()
end
local function full_screen_rle_and_malformed_frames()
  local g = GPU.new({width = 160, height = 50})
  assert(#Frame.encode(g) < 80)
  for y = 1, 50 do for x = 1, 160 do g.setForeground(x * 160 + y); g.set(x, y, x % 2 == 0 and "Ж" or "A") end end
  local data = Frame.encode(g); assert(#data > 80000)
  local f = assert(Frame.decode(data)); assert(#f.cells == 8000 and f.width == 160)
  assert(not Frame.decode(data, {maxBytes = 1000}))
  assert(not Frame.decode(data .. "x"))
  assert(not Frame.decode(data:sub(1, -2)))
  for n = 0, 66 do assert(not Frame.decode(data:sub(1, n))) end
  local single = GPU.new({width = 1, height = 1})
  single.cells[1] = Cell.pack("ab", 1, 0, 0); assert(not Frame.decode(Frame.encode(single)))
  single.cells[1] = Cell.pack("", 1, 0, 4); assert(not Frame.decode(Frame.encode(single)))
  single.cells[1] = Cell.pack("x", 17, 0, 1); assert(not Frame.decode(Frame.encode(single)))
  assert(not pcall(g.set, 1, 1, "\192\128"))
  assert(not pcall(g.set, 1, 1, "\237\160\128"))
  return H.success()
end
local function renderer_validates_first_and_restores_local_screen()
  local target = GPU.new({width = 8, height = 3})
  target.set(1, 1, "local"); target.setForeground(3, true); target.setBackground(0x222222)
  local r = Renderer.new(target); local saved = r:capture()
  local calls = 0; local original = target.set
  target.set = function(...) calls = calls + 1; return original(...) end
  assert(not r:render("bad frame") and calls == 0)
  local remote = GPU.new({width = 5, height = 2})
  remote.setPaletteColor(2, 0x123456); remote.setForeground(2, true); remote.set(1, 1, "界abc")
  assert(r:render(Frame.encode(remote)))
  local glyph, color = target.get(1, 1); assert(glyph == "界" and color == 0x123456)
  assert(r:restore(saved)); assert(target.getResolution() == 8 and target.get(1, 1) == "l" and target.get(5, 1) == "l")
  local fg, pal = target.getForeground(); assert(fg == 3 and pal and target.getBackground() == 0x222222)
  return H.success()
end
local all_tests = {
  {test_name = "unicode_colors_overlap_and_clipping", test = unicode_colors_overlap_and_clipping},
  {test_name = "cropped_wide_copy_and_resize_remain_valid", test = cropped_wide_copy_and_resize_remain_valid},
  {test_name = "full_screen_rle_and_malformed_frames", test = full_screen_rle_and_malformed_frames},
  {test_name = "renderer_validates_first_and_restores_local_screen", test = renderer_validates_first_and_restores_local_screen},
}
return all_tests
