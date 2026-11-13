#!/usr/bin/env python3
"""Create offline EC authorities/identities and issue SpaceCross certificates.

Requires cryptography. Never overwrites key/certificate files. Private keys stay
on the operator's PC unless explicitly copied to a configured OpenOS identity.
"""
import argparse
import hashlib
import json
import os
import secrets
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from sc_codec import encode, decode

DOMAIN = b'SpaceCross certificate v1\0'


def save(path, data, private=False):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600 if private else 0o644)
    with os.fdopen(fd, 'wb') as handle:
        handle.write(data)


def keygen(directory):
    directory.mkdir(parents=True, exist_ok=True)
    if (directory / 'private.der').exists() or (directory / 'public.der').exists():
        raise ValueError('key files already exist')
    key = ec.generate_private_key(ec.SECP256R1())
    save(directory / 'private.der', key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()), True)
    save(directory / 'public.der', key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo))


def issue(ca_key, public, issuer, subject, addresses, usage, grants, serial=None):
    if not addresses or not usage or not subject or not isinstance(grants, dict):
        raise ValueError('subject, addresses, usage and grants object required')
    body = encode(dict(v=1, issuer=issuer, serial=serial or secrets.token_hex(16), subject=subject,
                       public_key=public, addresses=addresses, usage=usage, grants=grants))
    signature = ca_key.sign(DOMAIN + hashlib.sha256(body).digest(), ec.ECDSA(hashes.SHA256()))
    return encode(dict(body=body, signature=signature))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    generate = commands.add_parser('keygen')
    generate.add_argument('--out', type=Path, required=True)
    issuing = commands.add_parser('issue')
    issuing.add_argument('--ca-private', type=Path, required=True)
    issuing.add_argument('--public-key', type=Path, required=True)
    issuing.add_argument('--issuer', default='root')
    issuing.add_argument('--subject', required=True)
    issuing.add_argument('--address', action='append', required=True)
    issuing.add_argument('--usage', action='append', choices=['client', 'server'], required=True)
    issuing.add_argument('--grants', type=Path, required=True, help='JSON object: model -> action list')
    issuing.add_argument('--out', type=Path, required=True)
    inspecting = commands.add_parser('inspect')
    inspecting.add_argument('certificate', type=Path)
    args = parser.parse_args()
    if args.command == 'keygen':
        keygen(args.out)
    elif args.command == 'issue':
        key = serialization.load_der_private_key(args.ca_private.read_bytes(), None)
        public = args.public_key.read_bytes()
        serialization.load_der_public_key(public)
        save(args.out, issue(key, public, args.issuer, args.subject, args.address, args.usage,
                             json.loads(args.grants.read_text())))
    else:
        cert = decode(decode(args.certificate.read_bytes())['body'])
        # Inspection is deliberately not a trust/verification command.
        cert['public_key'] = hashlib.sha256(cert['public_key']).hexdigest()
        print(json.dumps(cert, default=lambda v: v.decode() if isinstance(v, bytes) else str(v), indent=2))


if __name__ == '__main__':
    main()
