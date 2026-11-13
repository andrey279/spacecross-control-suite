"""python3 -m server.main --config /path/to/server.json"""
import argparse
import asyncio
import contextlib
import json
import struct
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from tools.sc_codec import decode
from .crypto import Trust, address, verify, public_bytes, public_key
from .rpc import Peer
from .store import Store, RetryAfter


async def read_frame(reader):
    size = struct.unpack('!I', await reader.readexactly(4))[0]
    if not 1 <= size <= 98304:
        raise ValueError('frame length')
    return await reader.readexactly(size)


def webhook_sender(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != 'https' or parts.username or parts.password or parts.fragment:
        raise ValueError('HTTPS webhook URL required')
    # Redirects must never forward a webhook secret to another service.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args):
            return None
    opener = urllib.request.build_opener(NoRedirect())
    if parts.hostname in ('discord.com', 'canary.discord.com', 'ptb.discord.com'):
        query = dict(urllib.parse.parse_qsl(parts.query)); query['wait'] = 'true'
        url = urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(query)))
    def send(payload):
        request = urllib.request.Request(url, payload, {'Content-Type': 'application/json', 'User-Agent': 'SpaceCross/1'})
        try:
            with opener.open(request, timeout=10) as response:
                if not 200 <= response.status < 300:
                    raise ValueError('webhook rejected')
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                body = json.loads(exc.read(4096))
                raise RetryAfter(body.get('retry_after', exc.headers.get('Retry-After', 1))) from None
            raise
    return send


class Server:
    def __init__(self, config):
        self.config = config
        self.private = serialization.load_der_private_key(Path(config['privateKeyFile']).read_bytes(), None)
        self.certificate = Path(config['certificateFile']).read_bytes()
        self.trust = Trust({k: Path(v).read_bytes() for k, v in config['authorities'].items()}, config.get('revoked', []))
        self.address = address(config['address'].encode())
        own = self.trust.verify(self.certificate, 'server', self.address)
        if own['public_key'] != public_bytes(self.private):
            raise ValueError('server private key mismatch')
        self.nodes = {address(k.encode()): Path(v).read_bytes() for k, v in config['nodes'].items()}
        if not self.nodes:
            raise ValueError('explicit node certificate pins required')
        for node, pin in self.nodes.items():
            self.trust.verify(pin, 'client', node)
        self.log_key = serialization.load_der_private_key(Path(config['logPrivateKeyFile']).read_bytes(), None)
        public_key(public_bytes(self.log_key))
        self.store = Store(config['database'])
        self.connections, self.tasks, self.listener, self.notifier = {}, set(), None, None
        self.last_error = None

    def dispatch_rpc(self, node, session, model, action, args, subject):
        """Dispatch an already certificate/grant-checked RPC for one live connection."""
        if model == '_cnc' and action == 'heartbeat':
            satellite = args.get('satellite')
            if satellite is not None:
                self.store.satellite_heartbeat(node, satellite)
            session['authenticated'] = True
            return dict(alive=True)
        if not session.get('authenticated'):
            raise ValueError('heartbeat required')
        if model == '_cnc' and action == 'whitelist':
            return dict(values=self.store.satellite_whitelist(node))
        if model == '_cnc' and action == 'alert':
            ident = self.store.satellite_alert(node, subject, args)
            return dict(accepted=True, id=ident)
        if model == '_logs' and action == 'put':
            return self.store.put(node, args['id'], args['data'], subject, self.log_key)
        raise ValueError('unsupported method')

    async def start(self):
        self.store.recover()
        self.listener = await asyncio.start_server(self.accept, self.config.get('bind', '127.0.0.1'), self.config.get('port', 27016), limit=110000)
        if self.config.get('discordWebhook'):
            sender = webhook_sender(self.config['discordWebhook'])
            async def notify():
                def once():
                    store = Store(self.config['database'])
                    try:
                        return store.notify_one(sender)
                    finally:
                        store.close()
                while True:
                    await asyncio.to_thread(once)
                    await asyncio.sleep(0.5)
            self.notifier = asyncio.create_task(notify())
        return self

    async def accept(self, reader, writer):
        task = asyncio.current_task()
        if len(self.tasks) >= self.config.get('maxConnections', 32):
            writer.close()
            return
        self.tasks.add(task)
        started, last, peer, node, pending, active = time.monotonic(), time.monotonic(), None, None, None, None
        session = {'authenticated': False}
        read = asyncio.create_task(read_frame(reader))
        async def send(wires):
            for wire in wires:
                if writer.transport.get_write_buffer_size() + len(wire) + 4 > 262144:
                    raise ValueError('write queue full')
                writer.write(struct.pack('!I', len(wire)) + wire)
            await asyncio.wait_for(writer.drain(), 2)
        def dispatch(model, action, args, subject):
            return self.dispatch_rpc(node, session, model, action, args, subject)
        try:
            while True:
                now = time.monotonic()
                if not session['authenticated'] and now - started > 10 or now - last > self.config.get('idleTimeout', 60):
                    break
                done, _ = await asyncio.wait({read}, timeout=0.1)
                if done:
                    wire = read.result(); last = now
                    if peer is None:
                        outer = decode(wire, 98304)
                        body = decode(outer['body'], 98304)
                        node = address(body['src'])
                        pin = self.nodes[node]
                        verify(self.trust, wire, node, self.address, 27016, pin)
                        peer = Peer(self.private, self.certificate, self.trust, self.address, node, pin, dispatch)
                    await send(peer.receive(wire, now))
                    read = asyncio.create_task(read_frame(reader))
                if peer:
                    await send(peer.tick(now))
                if session['authenticated']:
                    old = self.connections.get(node)
                    if old is not writer:
                        if old:
                            old.close()
                        self.connections[node] = writer
                    if pending:
                        call = peer.calls.get(pending)
                        if call and call.get('done'):
                            err = call.get('error')
                            self.store.finish(active, 'done' if err is None else 'unknown' if err == b'ETIMEDOUT' else 'failed',
                                              call.get('value'), err.decode(errors='replace') if isinstance(err, bytes) else err)
                            del peer.calls[pending]; pending, active = None, None
                    if not pending:
                        command = self.store.claim(node)
                        if command:
                            active, model, action, args = command
                            try:
                                pending, wire = peer.begin(model, action, args, now)
                            except Exception:
                                self.store.finish(active, 'failed', error='LOCAL_CERTIFICATE_DENIED'); active = None
                            else:
                                await send([wire])
        except Exception as exc:
            self.last_error = type(exc).__name__
        finally:
            if active:
                self.store.finish(active, 'unknown', error='CONNECTION_LOST')
            if node and self.connections.get(node) is writer:
                del self.connections[node]
            read.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await read
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()
            self.tasks.discard(task)

    async def close(self):
        if self.listener:
            self.listener.close(); await self.listener.wait_closed()
        if self.notifier:
            self.notifier.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.notifier
        for task in list(self.tasks):
            task.cancel()
        await asyncio.gather(*list(self.tasks), return_exceptions=True)
        self.store.close()


async def run(config):
    server = Server(config)
    try:
        await server.start()
        async with server.listener:
            await server.listener.serve_forever()
    finally:
        await server.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(run(json.loads(args.config.read_text())))


if __name__ == '__main__':
    main()
