#!/usr/bin/env python3
"""Run Lua with the system shared library when no lua executable is installed.

No third party Python packages. Lua os.exit keeps its normal exit semantics.
Usage: python3 tools/lua.py [--library liblua5.2.so.0] script.lua [args...]
"""
import argparse
import ctypes as c
import ctypes.util
import sys

p = argparse.ArgumentParser()
p.add_argument('--library', default='liblua5.2.so.0')
p.add_argument('script')
p.add_argument('args', nargs=argparse.REMAINDER)
a = p.parse_args()
lua = c.CDLL(a.library)
lua.luaL_newstate.restype = c.c_void_p
for name, args, result in [
    ('luaL_openlibs', [c.c_void_p], None),
    ('luaL_loadfilex', [c.c_void_p, c.c_char_p, c.c_char_p], c.c_int),
    ('lua_pcallk', [c.c_void_p, c.c_int, c.c_int, c.c_int, c.c_ssize_t, c.c_void_p], c.c_int),
    ('lua_tolstring', [c.c_void_p, c.c_int, c.POINTER(c.c_size_t)], c.c_void_p),
    ('lua_createtable', [c.c_void_p, c.c_int, c.c_int], None),
    ('lua_pushlstring', [c.c_void_p, c.c_char_p, c.c_size_t], c.c_void_p),
    ('lua_rawseti', [c.c_void_p, c.c_int, c.c_longlong], None),
    ('lua_setglobal', [c.c_void_p, c.c_char_p], None),
    ('lua_close', [c.c_void_p], None),
]:
    f = getattr(lua, name)
    f.argtypes, f.restype = args, result
state = lua.luaL_newstate()
if not state:
    sys.exit('Cannot allocate Lua state')
lua.luaL_openlibs(state)
lua.lua_createtable(state, len(a.args), 1)
for i, value in enumerate([a.script] + a.args):
    value = value.encode()
    lua.lua_pushlstring(state, value, len(value))
    lua.lua_rawseti(state, -2, i)
lua.lua_setglobal(state, b'arg')
code = lua.luaL_loadfilex(state, a.script.encode(), None)
if not code:
    code = lua.lua_pcallk(state, 0, -1, 0, 0, None)
if code:
    size = c.c_size_t()
    ptr = lua.lua_tolstring(state, -1, c.byref(size))
    print(c.string_at(ptr, size.value).decode(errors='replace') if ptr else 'Lua error', file=sys.stderr)
lua.lua_close(state)
sys.exit(1 if code else 0)
