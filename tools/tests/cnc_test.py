import asyncio
import hashlib
import hmac
import io
import json
import os
import re
import secrets
import struct
import tempfile
import time
import unittest
from unittest import mock
from urllib.error import HTTPError
from pathlib import Path
from cryptography.hazmat.primitives import hashes, padding, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from tools.sc_codec import encode, decode
from server.crypto import CERT_DOMAIN, Trust, public_bytes, unseal
from server.rpc import Peer
from server.store import Store, RetryAfter
from server.main import Server, read_frame, webhook_sender


def certificate(ca, key, subject, host, grants):
    raw = encode(dict(v=1, issuer='root', serial=subject, subject=subject, public_key=public_bytes(key),
                      addresses=[host], usage=['client', 'server'], grants=grants))
    return encode(dict(body=raw, signature=ca.sign(CERT_DOMAIN + hashlib.sha256(raw).digest(), ec.ECDSA(hashes.SHA256()))))


def seal(recipient, plaintext):
    ephemeral = ec.generate_private_key(ec.SECP256R1())
    public = public_bytes(ephemeral)
    key_id = hashlib.sha256(public_bytes(recipient)).digest()
    material = HKDF(hashes.SHA256(), 48, b'SpaceCross sealed logs v1', public + key_id).derive(ephemeral.exchange(ec.ECDH(), recipient.public_key()))
    iv = secrets.token_bytes(16)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(plaintext) + padder.finalize()
    cipher = Cipher(algorithms.AES(material[:16]), modes.CBC(iv)).encryptor()
    raw = encode(dict(version=1, algorithm='ECDH-HKDF-SHA256-AES128CBC-HMACSHA256', key_id=key_id,
                      ephemeral=public, iv=iv, ciphertext=cipher.update(padded) + cipher.finalize()))
    return encode(dict(body=raw, mac=hmac.digest(material[16:], raw, 'sha256')))


class Fixture:
    def __init__(self, directory):
        self.ca, self.owner, self.ship, self.logs = [ec.generate_private_key(ec.SECP256R1()) for _ in range(4)]
        self.control_cert = certificate(self.ca, self.owner, 'Owner', 'control', {'*': ['*']})
        self.ship_cert = certificate(self.ca, self.ship, 'Ship', 'internet',
                                     {'_cnc': ['heartbeat', 'whitelist', 'alert'], '_logs': ['put']})
        self.trust = Trust({'root': public_bytes(self.ca)})
        self.root = Path(directory)
        values = {'ca.der': public_bytes(self.ca), 'control.cert': self.control_cert, 'ship.cert': self.ship_cert,
                  'owner.der': self.owner.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()),
                  'logs.der': self.logs.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())}
        for name, raw in values.items():
            (self.root / name).write_bytes(raw)
        self.config = dict(address='control', privateKeyFile=str(self.root / 'owner.der'), certificateFile=str(self.root / 'control.cert'),
                           logPrivateKeyFile=str(self.root / 'logs.der'), authorities={'root': str(self.root / 'ca.der')},
                           nodes={'internet': str(self.root / 'ship.cert')}, database=str(self.root / 'state.db'), bind='127.0.0.1', port=0)
        self.record = encode(dict(level='critical', code='TEST_EVENT', time=12, fields=dict(secret='confidential', player='@everyone')))


class StorageTests(unittest.TestCase):
    def test_discord_wait_receipt_and_retry_after(self):
        response = mock.MagicMock()
        response.__enter__.return_value.status = 200
        opener = mock.Mock(); opener.open.return_value = response
        with mock.patch('urllib.request.build_opener', return_value=opener):
            send = webhook_sender('https://discord.com/api/webhooks/EXAMPLE/TEST?wait=false')
            send(b'{"content":"test","allowed_mentions":{"parse":[]}}')
            request = opener.open.call_args.args[0]
            self.assertIn('wait=true', request.full_url)
            self.assertEqual(request.get_method(), 'POST')
            self.assertEqual(request.get_header('Content-type'), 'application/json')
            opener.open.side_effect = HTTPError(request.full_url, 429, 'rate limited', {}, io.BytesIO(b'{"retry_after":3.5}'))
            with self.assertRaises(RetryAfter) as error:
                send(b'{}')
            self.assertEqual(error.exception.seconds, 3.5)
        with self.assertRaises(ValueError):
            webhook_sender('http://example.invalid/hook')

    def test_existing_lua_envelope_fixture_decrypts(self):
        source = Path('spacecross/security/tests/stubs/vectors.lua').read_text()
        def value(name):
            return bytes.fromhex(re.search(r'  ' + name + r' = "([0-9a-f]+)"', source).group(1))
        key = serialization.load_der_private_key(value('recipient_private'), None)
        self.assertEqual(unseal(key, value('envelope')), b'spacecross encryption test')

    def test_durable_receipt_conflict_rollback_and_discord_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory); store = Store(f.config['database'])
            sealed = seal(f.logs, f.record)
            store.db.executescript("CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'disk failure'); END;")
            with self.assertRaises(Exception):
                store.put('internet', b'ship-1.sealed', sealed, 'Ship', f.logs)
            self.assertEqual(store.db.execute('SELECT count(*) FROM logs').fetchone()[0], 0)
            store.db.execute('DROP TRIGGER fail_outbox')
            receipt = store.put('internet', b'ship-1.sealed', sealed, 'Ship', f.logs)
            self.assertEqual(receipt['digest'], hashlib.sha256(sealed).digest())
            store.close(); store = Store(f.config['database'])
            self.assertEqual(store.put('internet', b'ship-1.sealed', sealed, 'Ship', f.logs), receipt)
            with self.assertRaises(ValueError):
                store.put('internet', b'ship-1.sealed', seal(f.logs, f.record), 'Ship', f.logs)
            outer = decode(sealed); outer['mac'] = b'0' * 32
            with self.assertRaises(ValueError):
                store.put('internet', b'ship-2.sealed', encode(outer), 'Ship', f.logs)
            self.assertEqual(store.db.execute('SELECT count(*) FROM outbox').fetchone()[0], 1)
            def rate_limited(_):
                raise RetryAfter(4)
            self.assertTrue(store.notify_one(rate_limited, 100))
            store.close(); store = Store(f.config['database'])
            delivered = []
            self.assertFalse(store.notify_one(delivered.append, 103))
            self.assertTrue(store.notify_one(delivered.append, 104))
            self.assertEqual(json.loads(delivered[0])['allowed_mentions'], {'parse': []})
            self.assertFalse(store.notify_one(delivered.append, 200))
            self.assertEqual(os.stat(f.config['database']).st_mode & 0o777, 0o600)
            ident = store.enqueue('internet', 'power', 'snapshot', {})
            self.assertEqual(store.claim('internet')[0], ident)
            store.recover(); self.assertEqual(store.command(ident)['state'], 'unknown')
            self.assertIsNone(store.claim('internet'))
            store.close()

    def test_rpc_replay_restart_and_certificate_revocation(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory); executed = []
            ship = Peer(f.ship, f.ship_cert, f.trust, 'internet', 'control', f.control_cert, lambda *args: {})
            control = Peer(f.owner, f.control_cert, f.trust, 'control', 'internet', f.ship_cert, lambda *args: executed.append(args) or {'alive': True})
            ident, hello = ship.begin('_cnc', 'heartbeat', {}, 0)
            challenge = control.receive(hello, 0)[0]
            invoke = ship.receive(challenge, 0.1)[0]
            result = control.receive(invoke, 0.2)[0]
            ship.receive(result, 0.3)
            self.assertTrue(ship.calls[ident]['value']['alive'])
            self.assertEqual(control.receive(invoke, 0.4)[0], result)
            self.assertEqual(len(executed), 1)
            restarted = Peer(f.owner, f.control_cert, f.trust, 'control', 'internet', f.ship_cert, lambda *args: executed.append(args))
            with self.assertRaises(ValueError):
                restarted.receive(invoke, 0.5)
            f.trust.revoked.add('Ship')
            with self.assertRaises(ValueError):
                control.receive(invoke, 0.6)
            self.assertEqual(len(executed), 1)


class SocketTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_tcp_bootstrap_upload_and_owner_command(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory); server = Server(f.config)
            await server.start()
            reader, writer = await asyncio.open_connection('127.0.0.1', server.listener.sockets[0].getsockname()[1])
            executed = []
            def command(model, action, args, subject):
                executed.append((model, action, args, subject)); return {'count': 2}
            peer = Peer(f.ship, f.ship_cert, f.trust, 'internet', 'control', f.control_cert, command)
            ident = server.store.enqueue('internet', 'hardware', 'snapshot', {})
            async def send(wire, partial=False):
                framed = struct.pack('!I', len(wire)) + wire
                if partial:
                    for byte in framed[:4]:
                        writer.write(bytes([byte])); await writer.drain(); await asyncio.sleep(0)
                    framed = framed[4:]
                writer.write(framed); await writer.drain()
            async def exchange(call):
                deadline = time.monotonic() + 4
                while not peer.calls[call].get('done'):
                    self.assertLess(time.monotonic(), deadline)
                    wire = await asyncio.wait_for(read_frame(reader), 2)
                    for reply in peer.receive(wire, time.monotonic()):
                        await send(reply)
            try:
                heartbeat, hello = peer.begin('_cnc', 'heartbeat', {}, time.monotonic())
                await send(hello, True); await exchange(heartbeat)
                self.assertTrue(peer.calls[heartbeat]['value']['alive'])
                upload, hello = peer.begin('_logs', 'put', {'id': 'ship-1.sealed', 'data': seal(f.logs, f.record)}, time.monotonic())
                await send(hello); await exchange(upload)
                self.assertEqual(peer.calls[upload]['value']['receipt'], b'ship-1.sealed')
                # The control request may interleave with the upload exchange.
                pending_read = asyncio.create_task(read_frame(reader))
                try:
                    deadline = time.monotonic() + 3
                    while server.store.command(ident)['state'] != 'done':
                        self.assertLess(time.monotonic(), deadline)
                        done, _ = await asyncio.wait({pending_read}, timeout=0.05)
                        if done:
                            for reply in peer.receive(pending_read.result(), time.monotonic()):
                                await send(reply)
                            pending_read = asyncio.create_task(read_frame(reader))
                finally:
                    pending_read.cancel()
                    await asyncio.gather(pending_read, return_exceptions=True)
                self.assertEqual(executed[0][3], 'Owner')
                self.assertEqual(server.store.command(ident)['state'], 'done')
                self.assertEqual(server.store.db.execute('SELECT record FROM logs').fetchone()[0], f.record)
                unknown = server.store.enqueue('internet', 'hardware', 'snapshot', {})
                deadline = time.monotonic() + 3
                while len(executed) < 2:
                    self.assertLess(time.monotonic(), deadline)
                    incoming = await asyncio.wait_for(read_frame(reader), 2)
                    replies = peer.receive(incoming, time.monotonic())
                    # Lose the result after the simulated ship already executed.
                    if len(executed) < 2:
                        for reply in replies:
                            await send(reply)
                writer.close(); await writer.wait_closed()
                while server.store.command(unknown)['state'] == 'running':
                    self.assertLess(time.monotonic(), deadline)
                    await asyncio.sleep(0.02)
                self.assertEqual(server.store.command(unknown)['state'], 'unknown')
                self.assertIsNone(server.store.claim('internet'))
            finally:
                writer.close(); await writer.wait_closed(); await server.close()


if __name__ == '__main__':
    unittest.main()
