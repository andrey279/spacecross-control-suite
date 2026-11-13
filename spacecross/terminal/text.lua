-- UTF-8 scalar decoding, usable in Lua 5.2 without the 5.3 utf8 library.
local M = {}
function M.characters(text)
  assert(type(text) == "string", "text required")
  local out, index = {}, 1
  while index <= #text do
    local start, a = index, text:byte(index)
    local length, code
    if a < 128 then length, code = 1, a
    elseif a >= 194 and a <= 223 then length, code = 2, a - 192
    elseif a >= 224 and a <= 239 then length, code = 3, a - 224
    elseif a >= 240 and a <= 244 then length, code = 4, a - 240
    else error("invalid UTF-8") end
    for offset = 1, length - 1 do
      local b = text:byte(index + offset)
      assert(b and b >= 128 and b <= 191, "invalid UTF-8 continuation")
      code = code * 64 + b - 128
    end
    assert(not (length == 3 and code < 2048 or length == 4 and code < 65536)
      and not (code >= 55296 and code <= 57343) and code <= 1114111, "invalid Unicode scalar")
    index = index + length
    out[#out + 1] = {text = text:sub(start, index - 1), code = code}
  end
  return out
end
function M.width(character)
  local code = type(character) == "table" and character.code or M.characters(character)[1].code
  if code >= 768 and code <= 879 then return 0 end
  if code >= 4352 and (code <= 4447 or code >= 9001 and code <= 9002 or code >= 11904 and code <= 42191
      or code >= 44032 and code <= 55203 or code >= 63744 and code <= 64255 or code >= 65040 and code <= 65049
      or code >= 65072 and code <= 65376 or code >= 65504 and code <= 65510 or code >= 127744) then return 2 end
  return 1
end
return M
