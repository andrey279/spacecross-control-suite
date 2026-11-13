import hashlib
from pathlib import Path
import stat
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from pki import keygen, issue, DOMAIN
from sc_codec import encode, decode


class PKITest(unittest.TestCase):
    def test_real_certificate_signature_tampering_and_wrong_ca(self):
        ca = ec.generate_private_key(ec.SECP256R1())
        public = ec.generate_private_key(ec.SECP256R1()).public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
        wire = issue(ca, public, 'root', 'Owner', ['client'], ['client'], {'power': ['snapshot']}, 'serial')
        cert = decode(wire)
        data = DOMAIN + hashlib.sha256(cert['body']).digest()
        ca.public_key().verify(cert['signature'], data, ec.ECDSA(hashes.SHA256()))
        changed = decode(cert['body']); changed['subject'] = 'Intruder'
        with self.assertRaises(InvalidSignature):
            ca.public_key().verify(cert['signature'], DOMAIN + hashlib.sha256(encode(changed)).digest(), ec.ECDSA(hashes.SHA256()))
        with self.assertRaises(InvalidSignature):
            ec.generate_private_key(ec.SECP256R1()).public_key().verify(cert['signature'], data, ec.ECDSA(hashes.SHA256()))

    def test_keygen_is_exclusive_and_private_mode_is_0600(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            keygen(root)
            before = (root / 'private.der').read_bytes()
            self.assertEqual(stat.S_IMODE((root / 'private.der').stat().st_mode), 0o600)
            with self.assertRaises(ValueError):
                keygen(root)
            self.assertEqual((root / 'private.der').read_bytes(), before)

    def test_codec_roundtrips_binary_and_rejects_duplicate_keys(self):
        raw = encode({'bytes': b'\x00\xff', 'flag': False, 'nested': [1, 2]})
        self.assertEqual(encode(decode(raw)), raw)
        for malformed in [b'a2:s1:xts1:xf', b's50:short', b'a999999999:', b'return os.execute("bad")']:
            with self.assertRaises(ValueError):
                decode(malformed)


if __name__ == '__main__':
    unittest.main()
