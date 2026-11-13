"""Bounded, bidirectional peer for the same four-frame RPC used by OpenOS."""
import hashlib
import secrets
from tools.sc_codec import encode, decode
from .crypto import granted, sign, verify, text, public_bytes


class Peer:
    def __init__(self, private, certificate, trust, source, destination, pin, dispatch, timeout=8):
        self.private, self.certificate, self.trust = private, certificate, trust
        self.source, self.destination, self.pin, self.dispatch = source, destination, pin, dispatch
        self.own = trust.verify(certificate, 'server', source)
        if self.own['public_key'] != public_bytes(private):
            raise ValueError('private key mismatch')
        self.inbound, self.calls = {}, {}
        self.timeout = timeout

    def frame(self, kind, ident, nonce, **extra):
        wire = sign(self.private, self.certificate, dict(v=1, kind=kind, id=ident, src=self.source,
                    dst=self.destination, port=27016, client_nonce=nonce, **extra))
        if len(wire) > 98304:
            raise ValueError('RPC frame too large')
        return wire

    def room(self, needed, slot=False):
        while len(self.inbound) >= 32 and slot or sum(e['bytes'] for e in self.inbound.values()) + needed > 524288:
            done = [(e['expires'], k) for k, e in self.inbound.items() if e['state'] == 'done']
            if not done:
                raise ValueError('RPC inbound limit')
            del self.inbound[min(done)[1]]

    def begin(self, model, action, args, now):
        cert = self.trust.verify(self.certificate, 'client', self.source)
        if not granted(cert, model, action) or len(self.calls) >= 32:
            raise ValueError('RPC identity denied or busy')
        ident, nonce = secrets.token_hex(32).encode(), secrets.token_hex(32).encode()
        wire = self.frame('hello', ident, nonce, request=encode(dict(model=model, action=action, args=args)))
        if sum(len(c.get('wire', b'')) for c in self.calls.values()) + len(wire) > 524288:
            raise ValueError('RPC client limit')
        self.calls[ident] = dict(phase='hello', nonce=nonce, digest=hashlib.sha256(decode(wire)['body']).digest(),
                                wire=wire, sent=now, deadline=now + self.timeout)
        return ident, wire

    def receive(self, wire, now):
        b, cert, digest = verify(self.trust, wire, self.destination, self.source, 27016, self.pin)
        kind, ident = text(b['kind']), b['id']
        if kind == 'hello':
            self.trust.verify(self.certificate, 'server', self.source)
            old = self.inbound.get(ident)
            if old:
                return [old['challenge_wire']] if old['digest'] == digest else []
            request = decode(b['request'], 98304)
            model, action, args = text(request['model']), text(request['action']), request['args']
            if not isinstance(args, dict) or not granted(cert, model, action):
                raise ValueError('RPC grant denied')
            if sum(e['state'] != 'done' for e in self.inbound.values()) >= 4:
                raise ValueError('RPC active limit')
            challenge = secrets.token_hex(32).encode()
            response = self.frame('challenge', ident, b['client_nonce'], challenge=challenge, hello_digest=digest)
            self.room(len(wire) + len(response), True)
            self.inbound[ident] = dict(state='challenge', nonce=b['client_nonce'], challenge=challenge, digest=digest,
                request=(model, action, args), subject=cert['subject'], challenge_wire=response,
                bytes=len(wire) + len(response), expires=now + 10)
            return [response]
        if kind == 'invoke':
            self.trust.verify(self.certificate, 'server', self.source)
            entry = self.inbound.get(ident)
            if not entry or (entry['nonce'], entry['challenge'], entry['digest']) != (b['client_nonce'], b['challenge'], b['hello_digest']):
                raise ValueError('unknown challenge')
            if entry['state'] == 'done':
                return [entry['response']] if entry.get('response') else []
            if entry['state'] != 'challenge' or now >= entry['expires']:
                raise ValueError('expired challenge')
            entry['state'] = 'executing'  # Consume before any persistent action.
            try:
                value = self.dispatch(*entry['request'], cert['subject'])
                extra = dict(ok=True, value=value)
            except Exception:
                extra = dict(ok=False, error='ERR_RPC_HANDLER')
            entry['state'], entry['expires'] = 'done', now + 30
            try:
                response = self.frame('result', ident, b['client_nonce'], challenge=b['challenge'], hello_digest=b['hello_digest'], **extra)
                self.room(len(response))
                entry['response'], entry['bytes'] = response, entry['bytes'] + len(response)
            except Exception:
                # An unknown result is never a reason to run dispatch again.
                return []
            return [response]
        call = self.calls.get(ident)
        if not call or call.get('done') or now >= call['deadline'] or (call['nonce'], call['digest']) != (b['client_nonce'], b['hello_digest']):
            return []
        if kind == 'challenge' and call['phase'] == 'hello':
            response = self.frame('invoke', ident, b['client_nonce'], challenge=b['challenge'], hello_digest=b['hello_digest'])
            call.update(phase='invoke', challenge=b['challenge'], wire=response, sent=now)
            return [response]
        if kind == 'result' and call['phase'] == 'invoke' and call['challenge'] == b['challenge'] and type(b['ok']) is bool:
            call.update(done=True, value=b.get('value') if b['ok'] else None,
                        error=None if b['ok'] else b.get('error', b'ERR_RPC_REMOTE'), wire=b'')
        return []

    def tick(self, now):
        output = []
        for ident, entry in list(self.inbound.items()):
            if entry['state'] != 'executing' and now >= entry['expires']:
                del self.inbound[ident]
        for call in self.calls.values():
            if call.get('done'):
                continue
            if now >= call['deadline']:
                call.update(done=True, value=None, error=b'ETIMEDOUT', wire=b'')
            elif now - call['sent'] >= 1:
                call['sent'] = now
                output.append(call['wire'])
        return output
