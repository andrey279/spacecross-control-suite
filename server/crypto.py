"""Wire-compatible application certificates, RPC signatures and sealed logs."""
import hashlib
import hmac
import re
from cryptography.hazmat.primitives import hashes, padding, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from tools.sc_codec import encode, decode

CERT_DOMAIN = b'SpaceCross certificate v1\0'
RPC_DOMAIN = b'SpaceCross RPC v1\0'


def text(value, maximum=64):
    if not isinstance(value, bytes) or not 1 <= len(value) <= maximum or any(c < 32 or c == 127 for c in value):
        raise ValueError('invalid label')
    return value.decode('utf-8')


def address(value):
    result = text(value)
    if not re.fullmatch(r'[A-Za-z0-9-]+', result):
        raise ValueError('invalid address')
    return result


def array(value, maximum):
    if not isinstance(value, dict) or len(value) > maximum or set(value) != set(range(1, len(value) + 1)):
        raise ValueError('invalid array')
    return [value[i] for i in range(1, len(value) + 1)]


def public_key(raw):
    key = serialization.load_der_public_key(raw)
    if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(key.curve, ec.SECP256R1):
        raise ValueError('P-256 key required')
    return key


def public_bytes(key):
    return key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)


class Trust:
    def __init__(self, authorities, revoked=()):
        self.authorities = {issuer: public_key(raw) for issuer, raw in authorities.items()}
        self.revoked = set(revoked)

    def verify(self, wire, usage=None, host=None):
        outer = decode(wire, 8192)
        body, signature = outer['body'], outer['signature']
        if not isinstance(signature, bytes) or not 1 <= len(signature) <= 256:
            raise ValueError('invalid signature')
        value = decode(body, 8192)
        if set(value) != {'v', 'issuer', 'serial', 'subject', 'public_key', 'addresses', 'usage', 'grants'} or type(value['v']) is not int or value['v'] != 1:
            raise ValueError('invalid certificate')
        issuer, serial = text(value['issuer']), text(value['serial'], 128)
        if serial in self.revoked:
            raise ValueError('revoked certificate')
        self.authorities[issuer].verify(signature, CERT_DOMAIN + hashlib.sha256(body).digest(), ec.ECDSA(hashes.SHA256()))
        hosts = [address(v) for v in array(value['addresses'], 32)]
        uses = [text(v) for v in array(value['usage'], 2)]
        if not hosts or len(set(hosts)) != len(hosts) or not uses or len(set(uses)) != len(uses) or set(uses) - {'client', 'server'}:
            raise ValueError('invalid certificate bindings')
        if usage and usage not in uses or host and host not in hosts:
            raise ValueError('certificate binding mismatch')
        grants = value['grants']
        if not isinstance(grants, dict) or len(grants) > 64:
            raise ValueError('invalid grants')
        permissions = {}
        for model, actions in grants.items():
            text(model.encode())
            values = [text(v) for v in array(actions, 64)]
            if len(set(values)) != len(values):
                raise ValueError('duplicate grants')
            permissions[model] = values
        return dict(subject=text(value['subject']), serial=serial, key=public_key(value['public_key']),
                    public_key=value['public_key'], grants=permissions, addresses=hosts, usage=uses)


def granted(cert, model, action):
    return any(action in cert['grants'].get(name, []) or '*' in cert['grants'].get(name, []) for name in (model, '*'))


def sign(private, certificate, body):
    raw = encode(body)
    return encode(dict(body=raw, certificate=certificate, signature=private.sign(RPC_DOMAIN + hashlib.sha256(raw).digest(), ec.ECDSA(hashes.SHA256()))))


def verify(trust, wire, source, destination, port, pin):
    outer = decode(wire, 98304)
    if outer['certificate'] != pin:
        raise ValueError('certificate pin mismatch')
    body = decode(outer['body'], 98304)
    if type(body['v']) is not int or body['v'] != 1 or address(body['src']) != source or address(body['dst']) != destination or body['port'] != port:
        raise ValueError('invalid RPC binding')
    for field in ('id', 'client_nonce'):
        if not isinstance(body[field], bytes) or not re.fullmatch(rb'[0-9a-fA-F]{64}', body[field]):
            raise ValueError('invalid nonce')
    kind = text(body['kind'])
    if kind not in ('hello', 'challenge', 'invoke', 'result'):
        raise ValueError('invalid RPC kind')
    cert = trust.verify(pin, 'client' if kind in ('hello', 'invoke') else 'server', source)
    cert['key'].verify(outer['signature'], RPC_DOMAIN + hashlib.sha256(outer['body']).digest(), ec.ECDSA(hashes.SHA256()))
    if kind != 'hello' and (not isinstance(body['challenge'], bytes) or not re.fullmatch(rb'[0-9a-fA-F]{64}', body['challenge'])
                            or not isinstance(body['hello_digest'], bytes) or len(body['hello_digest']) != 32):
        raise ValueError('invalid challenge')
    return body, cert, hashlib.sha256(outer['body']).digest()


def unseal(private, wire):
    outer = decode(wire, 80000)
    raw = outer['body']
    body = decode(raw, 80000)
    if set(body) != {'version', 'algorithm', 'key_id', 'ephemeral', 'iv', 'ciphertext'} or body['version'] != 1 or body['algorithm'] != b'ECDH-HKDF-SHA256-AES128CBC-HMACSHA256':
        raise ValueError('invalid sealed log')
    if body['key_id'] != hashlib.sha256(public_bytes(private)).digest() or len(body['iv']) != 16:
        raise ValueError('wrong log key or IV')
    ephemeral = public_key(body['ephemeral'])
    material = HKDF(hashes.SHA256(), 48, b'SpaceCross sealed logs v1', body['ephemeral'] + body['key_id']).derive(private.exchange(ec.ECDH(), ephemeral))
    if not hmac.compare_digest(hmac.digest(material[16:], raw, 'sha256'), outer['mac']):
        raise ValueError('invalid log MAC')
    decryptor = Cipher(algorithms.AES(material[:16]), modes.CBC(body['iv'])).decryptor()
    padded = decryptor.update(body['ciphertext']) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    return unpadder.update(padded) + unpadder.finalize()
