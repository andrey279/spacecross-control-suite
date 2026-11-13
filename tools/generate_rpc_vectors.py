#!/usr/bin/env python3
"""Independent ECDSA/codec fixtures. All fixed private scalars are public test keys."""
import hashlib
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from pki import issue
from sc_codec import encode, decode

ca = ec.derive_private_key(31, ec.SECP256R1())
client = ec.derive_private_key(32, ec.SECP256R1())
public = lambda key: key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
private = client.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
certificate = issue(ca, public(client), 'root', 'Owner', ['client'], ['client'], {'power': ['snapshot']}, 'fixture-client')
body = encode(dict(v=1, kind='hello', id='a' * 64, client_nonce='b' * 64, src='client', dst='server', port=27016,
                   request=encode(dict(model='power', action='snapshot', args={}))))
signing_input = b'SpaceCross RPC v1\0' + hashlib.sha256(body).digest()
signature = client.sign(signing_input, ec.ECDSA(hashes.SHA256()))
client.public_key().verify(signature, signing_input, ec.ECDSA(hashes.SHA256()))
fields = dict(ca_public=public(ca), client_public=public(client), client_private=private, certificate=certificate,
              body=body, signing_input=signing_input, signature=signature,
              wire=encode(dict(body=body, certificate=certificate, signature=signature)))
cert_outer = decode(certificate)
fields['certificate_input'] = b'SpaceCross certificate v1\0' + hashlib.sha256(cert_outer['body']).digest()
fields['certificate_signature'] = cert_outer['signature']
changed = decode(body)
changed['request'] = encode(dict(model='power', action='arm', args={}))
fields['bad_body'] = encode(changed)
fields['bad_wire'] = encode(dict(body=fields['bad_body'], certificate=certificate, signature=signature))
hashed = {value.hex(): hashlib.sha256(value).hexdigest() for value in [body, fields['bad_body'], cert_outer['body']]}
target = Path(__file__).resolve().parents[1] / 'spacecross/security/tests/stubs/rpc_vectors.lua'
target.write_text('-- Generated public ECDSA test material, never deployment keys.\nreturn {\n' +
                  ''.join(f'  {name} = "{value.hex()}",\n' for name, value in fields.items()) +
                  '  hashes = {\n' + ''.join(f'    ["{key}"] = "{value}",\n' for key, value in hashed.items()) + '  },\n}\n')
print(target)
