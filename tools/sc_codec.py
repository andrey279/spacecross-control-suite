"""SpaceCross data codec for PKI/server tooling. Strings decode to bytes; keys to UTF-8."""
import math


def encode(value):
    if value is None:
        return b'z'
    if isinstance(value, bool):
        return b't' if value else b'f'
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise ValueError('nonfinite number')
        raw = format(value, '.17g').encode()
        return b'n' + str(len(raw)).encode() + b':' + raw
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return b's' + str(len(value)).encode() + b':' + value
    if isinstance(value, list):
        value = dict(enumerate(value, 1))
    if isinstance(value, dict):
        entries = sorted((encode(k), encode(v)) for k, v in value.items())
        return b'a' + str(len(entries)).encode() + b':' + b''.join(k + v for k, v in entries)
    raise ValueError('unsupported value')


def decode(data, limit=131072):
    if not isinstance(data, bytes) or len(data) > limit:
        raise ValueError('invalid size')
    pos, nodes = 0, 0

    def count():
        nonlocal pos
        colon = data.find(b':', pos)
        if colon < pos or colon - pos > 9 or not data[pos:colon].isdigit():
            raise ValueError('invalid length')
        length, pos = int(data[pos:colon]), colon + 1
        return length

    def parse(depth):
        nonlocal pos, nodes
        nodes += 1
        if depth >= 32 or nodes > 8192 or pos >= len(data):
            raise ValueError('complex or truncated value')
        tag, pos = data[pos:pos + 1], pos + 1
        if tag == b'z':
            return None
        if tag in (b't', b'f'):
            return tag == b't'
        if tag in (b's', b'n'):
            length = count()
            value, pos = data[pos:pos + length], pos + length
            if len(value) != length:
                raise ValueError('truncated value')
            if tag == b's':
                return value
            number = float(value)
            if not math.isfinite(number):
                raise ValueError('nonfinite number')
            return int(number) if number.is_integer() else number
        if tag != b'a':
            raise ValueError('invalid tag')
        length, out = count(), {}
        if length > 4096:
            raise ValueError('too many entries')
        for _ in range(length):
            key = parse(depth + 1)
            if isinstance(key, bytes):
                key = key.decode('utf-8')
            if isinstance(key, bool) or not isinstance(key, (str, int, float)) or key in out:
                raise ValueError('invalid/duplicate key')
            value = parse(depth + 1)
            if value is None:
                raise ValueError('nil entry')
            out[key] = value
        return out

    result = parse(0)
    if pos != len(data):
        raise ValueError('trailing data')
    return result
