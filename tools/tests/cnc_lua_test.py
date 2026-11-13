"""Real Lua application <-> localhost TCP <-> Python server, real ECDSA/AES."""
import asyncio
import ctypes as c
import ctypes.util
import hashlib
import secrets
import socket
import tempfile
import threading
import time
import unittest
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cnc_test import Fixture, seal
from server.crypto import public_bytes, public_key
from server.main import Server
from server.store import Store
from tools.sc_codec import encode, decode


class LuaBridge:
    def __init__(self, fixture, port):
        self.fixture, self.port, self.sockets, self.report, self.errors = fixture, port, {}, None, []
        self.lua = c.CDLL(ctypes.util.find_library('lua5.2'))
        signatures = [
            ('luaL_newstate', [], c.c_void_p), ('luaL_openlibs', [c.c_void_p], None),
            ('lua_gettop', [c.c_void_p], c.c_int), ('lua_tolstring', [c.c_void_p, c.c_int, c.POINTER(c.c_size_t)], c.c_void_p),
            ('lua_pushlstring', [c.c_void_p, c.c_char_p, c.c_size_t], c.c_void_p),
            ('lua_pushcclosure', [c.c_void_p, c.c_void_p, c.c_int], None), ('lua_setglobal', [c.c_void_p, c.c_char_p], None),
            ('luaL_loadfilex', [c.c_void_p, c.c_char_p, c.c_char_p], c.c_int),
            ('lua_pcallk', [c.c_void_p, c.c_int, c.c_int, c.c_int, c.c_ssize_t, c.c_void_p], c.c_int),
            ('lua_close', [c.c_void_p], None)]
        for name, args, result in signatures:
            fn = getattr(self.lua, name); fn.argtypes, fn.restype = args, result
        self.callback = c.CFUNCTYPE(c.c_int, c.c_void_p)(self.invoke)

    def string(self, state, index):
        size = c.c_size_t()
        pointer = self.lua.lua_tolstring(state, index, c.byref(size))
        return c.string_at(pointer, size.value) if pointer else b''

    def invoke(self, state):
        args = [self.string(state, i) for i in range(1, self.lua.lua_gettop(state) + 1)]
        try:
            value = self.operation(args[0].decode(), args[1:])
        except Exception as exc:
            self.errors.append(type(exc).__name__)
            value = {'__error': type(exc).__name__}
        raw = encode(value); self.lua.lua_pushlstring(state, raw, len(raw)); return 1

    def operation(self, name, args):
        f = self.fixture
        if name == 'config':
            return dict(ship=f.ship_cert, control=f.control_cert, ca=public_bytes(f.ca), port=self.port)
        if name == 'clock':
            return time.monotonic()
        if name == 'pause':
            time.sleep(float(args[0])); return True
        if name == 'random':
            return secrets.token_bytes(int(args[0]))
        if name == 'sha256':
            return hashlib.sha256(args[0]).digest()
        if name == 'sign':
            return f.ship.sign(args[0], ec.ECDSA(hashes.SHA256()))
        if name == 'verify':
            try:
                public_key(args[0]).verify(args[2], args[1], ec.ECDSA(hashes.SHA256()))
                return True
            except (InvalidSignature, ValueError):
                return False
        if name == 'seal':
            return seal(f.logs, args[0])
        if name == 'connect':
            sock = socket.create_connection((args[0].decode(), int(args[1])), timeout=1)
            sock.setblocking(False)
            ident = secrets.token_hex(8); self.sockets[ident.encode()] = sock; return ident
        if name == 'read':
            try:
                data = self.sockets[args[0]].recv(int(args[1]))
                return data if data else None
            except BlockingIOError:
                return b''
        if name == 'write':
            try:
                return self.sockets[args[0]].send(args[1])
            except BlockingIOError:
                return 0
        if name == 'close':
            self.sockets[args[0]].close(); return True
        if name == 'report':
            self.report = decode(args[0]); return True
        raise ValueError('unknown bridge operation')

    def run(self):
        state = self.lua.luaL_newstate(); self.lua.luaL_openlibs(state)
        try:
            self.lua.lua_pushcclosure(state, self.callback, 0)
            self.lua.lua_setglobal(state, b'_cnc_test_bridge')
            status = self.lua.luaL_loadfilex(state, b'spacecross/cnc/tests/stubs/real_client.lua', None)
            if not status:
                status = self.lua.lua_pcallk(state, 0, -1, 0, 0, None)
            if status:
                raise AssertionError(self.string(state, -1).decode(errors='replace'))
        finally:
            self.lua.lua_close(state)
            for sock in self.sockets.values():
                sock.close()


class IntegrationTests(unittest.TestCase):
    @unittest.skipUnless(ctypes.util.find_library('lua5.2'), 'Lua 5.2 shared library required for cross-language integration')
    def test_lua_agent_real_crypto_heartbeat_durable_log_and_remote_command(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory)
            loop = asyncio.new_event_loop()
            thread = threading.Thread(target=loop.run_forever, daemon=True); thread.start()
            async def start():
                server = Server(f.config); await server.start(); return server
            server = asyncio.run_coroutine_threadsafe(start(), loop).result(5)
            store = Store(f.config['database'])
            ident = store.enqueue('internet', 'probe', 'configure', {'player': 'Admin', 'value': 42})
            bridge = LuaBridge(f, server.listener.sockets[0].getsockname()[1])
            try:
                bridge.run()
                self.assertEqual(bridge.errors, [])
                self.assertEqual(bridge.report['commands'], 1)
                self.assertTrue(bridge.report['heartbeat'])
                self.assertGreaterEqual(bridge.report['receipts'], 2)
                self.assertEqual(store.command(ident)['state'], 'done')
                self.assertEqual(store.command(ident)['result'], {'actor': 'Owner', 'count': 1, 'value': 42})
                records = [decode(row[0]) for row in store.db.execute('SELECT record FROM logs')]
                self.assertTrue(any(r['code'] == b'REAL_LUA_EVENT' and r['fields']['secret'] == b'confidential-lua' for r in records))
                self.assertEqual(store.db.execute('SELECT count(*) FROM outbox').fetchone()[0], 1)
            finally:
                store.close()
                asyncio.run_coroutine_threadsafe(server.close(), loop).result(5)
                loop.call_soon_threadsafe(loop.stop); thread.join(5); loop.close()


if __name__ == '__main__':
    unittest.main()
