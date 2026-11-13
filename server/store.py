"""Durable log receipts, Discord outbox and explicit control command outcomes."""
import hashlib
import json
import os
import re
import secrets
import sqlite3
import time
from pathlib import Path
from tools.sc_codec import encode, decode
from .crypto import unseal, text


def readable(value):
    if isinstance(value, bytes):
        return value.decode('utf-8', errors='replace')
    if isinstance(value, dict):
        return {str(k): readable(v) for k, v in value.items()}
    return value


class RetryAfter(Exception):
    def __init__(self, seconds):
        self.seconds = max(0.25, min(3600, float(seconds)))


class Store:
    def __init__(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            os.close(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
        except FileExistsError:
            pass
        os.chmod(path, 0o600)
        self.db = sqlite3.connect(path, timeout=5)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS logs(node TEXT, id TEXT, subject TEXT, digest BLOB, sealed BLOB,
            record BLOB, received REAL, PRIMARY KEY(node,id));
          CREATE TABLE IF NOT EXISTS outbox(node TEXT, id TEXT, payload TEXT, attempts INTEGER DEFAULT 0,
            due REAL DEFAULT 0, sent INTEGER DEFAULT 0, PRIMARY KEY(node,id));
          CREATE TABLE IF NOT EXISTS commands(id TEXT PRIMARY KEY, node TEXT, model TEXT, action TEXT,
            args BLOB, state TEXT, result BLOB, error TEXT, created REAL);
          CREATE TABLE IF NOT EXISTS satellite_whitelist(node TEXT, entry TEXT,
            PRIMARY KEY(node,entry));
          CREATE TABLE IF NOT EXISTS satellite_status(node TEXT PRIMARY KEY, mode TEXT,
            state TEXT, seen REAL NOT NULL);
          CREATE TABLE IF NOT EXISTS satellite_alerts(id INTEGER PRIMARY KEY AUTOINCREMENT,
            node TEXT NOT NULL, subject TEXT NOT NULL, mode TEXT NOT NULL, target BLOB NOT NULL,
            received REAL NOT NULL);
        ''')

    def close(self):
        self.db.close()

    def set_satellite_whitelist(self, node, entries):
        entries = [value.decode('utf-8') if isinstance(value, bytes) else value for value in entries] if isinstance(entries, list) else entries
        if not isinstance(entries, list) or len(entries) > 4096 or any(
                not isinstance(x, str) or not x or len(x) > 128 for x in entries):
            raise ValueError('invalid satellite whitelist')
        values = sorted(set(entries))
        with self.db:
            self.db.execute('DELETE FROM satellite_whitelist WHERE node=?', (node,))
            self.db.executemany('INSERT INTO satellite_whitelist(node,entry) VALUES(?,?)',
                                [(node, value) for value in values])
        return values

    def satellite_whitelist(self, node):
        return [row[0] for row in self.db.execute(
            'SELECT entry FROM satellite_whitelist WHERE node=? ORDER BY entry', (node,))]

    def satellite_heartbeat(self, node, status):
        if not isinstance(status, dict):
            raise ValueError('invalid satellite heartbeat')
        mode, state = status.get('mode'), status.get('state')
        mode = mode.decode('utf-8') if isinstance(mode, bytes) else mode
        state = state.decode('utf-8') if isinstance(state, bytes) else state
        if mode not in ('jump', 'charges') or not isinstance(state, str) or len(state) > 32:
            raise ValueError('invalid satellite status')
        with self.db:
            self.db.execute('INSERT INTO satellite_status VALUES(?,?,?,?) ON CONFLICT(node) DO UPDATE SET '
                            'mode=excluded.mode,state=excluded.state,seen=excluded.seen',
                            (node, mode, state, time.time()))

    def satellite_status(self, node):
        row = self.db.execute('SELECT mode,state,seen FROM satellite_status WHERE node=?', (node,)).fetchone()
        if not row:
            return None
        return dict(node=node, mode=row[0], state=row[1], seen=row[2])

    def satellite_alert(self, node, subject, alert):
        mode = alert.get('mode') if isinstance(alert, dict) else None
        mode = mode.decode('utf-8') if isinstance(mode, bytes) else mode
        if not isinstance(alert, dict) or mode not in ('jump', 'charges'):
            raise ValueError('invalid satellite alert')
        target = alert.get('target')
        if not isinstance(target, dict) or len(encode(target)) > 8192:
            raise ValueError('invalid satellite alert target')
        with self.db:
            cur = self.db.execute('INSERT INTO satellite_alerts(node,subject,mode,target,received) VALUES(?,?,?,?,?)',
                                  (node, subject, mode, encode(target), time.time()))
        return cur.lastrowid

    def satellite_alerts(self, node, limit=100):
        if type(limit) is not int or not 1 <= limit <= 1000:
            raise ValueError('invalid alert limit')
        rows = self.db.execute('SELECT id,subject,mode,target,received FROM satellite_alerts '
                               'WHERE node=? ORDER BY id DESC LIMIT ?', (node, limit))
        return [dict(id=row[0], subject=row[1], mode=row[2], target=readable(decode(row[3])), received=row[4])
                for row in rows]

    def put(self, node, ident, sealed, subject, log_key):
        if not isinstance(ident, bytes) or not re.fullmatch(rb'[A-Za-z0-9-]{1,120}\.sealed', ident) or not isinstance(sealed, bytes) or len(sealed) > 80000:
            raise ValueError('invalid log upload')
        name, digest = ident.decode('ascii'), hashlib.sha256(sealed).digest()
        existing = self.db.execute('SELECT digest FROM logs WHERE node=? AND id=?', (node, name)).fetchone()
        if existing:
            if existing[0] != digest:
                raise ValueError('log ID conflict')
            return dict(receipt=ident, digest=digest)
        plaintext = unseal(log_key, sealed)
        record = decode(plaintext, 65536)
        if not isinstance(record, dict) or set(record) != {'level', 'code', 'fields', 'time'} or not isinstance(record['fields'], dict) or type(record['time']) not in (int, float):
            raise ValueError('invalid log record')
        level, code = text(record['level']), text(record['code'], 256)
        if level not in ('debug', 'info', 'warning', 'error', 'critical'):
            raise ValueError('invalid log level')
        content = f'[{level}] {node}/{name} ({subject}) {code}\n' + json.dumps(readable(record['fields']), ensure_ascii=False)
        payload = json.dumps(dict(content=content[:1900], allowed_mentions=dict(parse=[])), ensure_ascii=False)
        # Commit ciphertext + decoded record + notification intent before any ACK.
        with self.db:
            self.db.execute('INSERT INTO logs VALUES(?,?,?,?,?,?,?)', (node, name, subject, digest, sealed, plaintext, time.time()))
            if level in ('warning', 'error', 'critical'):
                self.db.execute('INSERT INTO outbox(node,id,payload) VALUES(?,?,?)', (node, name, payload))
        return dict(receipt=ident, digest=digest)

    def notify_one(self, sender, now=None):
        now = time.time() if now is None else now
        row = self.db.execute('SELECT node,id,payload,attempts FROM outbox WHERE sent=0 AND due<=? ORDER BY due,node,id LIMIT 1', (now,)).fetchone()
        if not row:
            return False
        node, ident, payload, attempts = row
        try:
            sender(payload.encode())
        except Exception as exc:
            delay = exc.seconds if isinstance(exc, RetryAfter) else min(300, 2 ** min(20, attempts + 1))
            with self.db:
                self.db.execute('UPDATE outbox SET attempts=attempts+1,due=? WHERE node=? AND id=?', (now + delay, node, ident))
        else:
            with self.db:
                self.db.execute('UPDATE outbox SET sent=1 WHERE node=? AND id=?', (node, ident))
        return True

    def enqueue(self, node, model, action, args):
        if not isinstance(args, dict) or len(encode(args)) > 65536:
            raise ValueError('invalid command args')
        ident = secrets.token_hex(16)
        with self.db:
            self.db.execute('INSERT INTO commands VALUES(?,?,?,?,?,?,?,?,?)',
                (ident, node, model, action, encode(args), 'queued', None, None, time.time()))
        return ident

    def claim(self, node):
        with self.db:
            row = self.db.execute('SELECT id,model,action,args FROM commands WHERE node=? AND state=? ORDER BY created LIMIT 1', (node, 'queued')).fetchone()
            if row:
                changed = self.db.execute('UPDATE commands SET state=? WHERE id=? AND state=?', ('running', row[0], 'queued')).rowcount
                if changed:
                    return row[0], row[1], row[2], decode(row[3])

    def finish(self, ident, state, value=None, error=None):
        with self.db:
            self.db.execute('UPDATE commands SET state=?,result=?,error=? WHERE id=? AND state=?',
                (state, encode(value) if value is not None else None, error, ident, 'running'))

    def recover(self):
        with self.db:
            self.db.execute("UPDATE commands SET state='unknown',error='SERVER_RESTART' WHERE state='running'")

    def command(self, ident):
        row = self.db.execute('SELECT node,model,action,state,result,error FROM commands WHERE id=?', (ident,)).fetchone()
        if not row:
            raise ValueError('unknown command')
        return dict(zip(('node', 'model', 'action', 'state', 'result', 'error'), [*row[:4], readable(decode(row[4])) if row[4] is not None else None, row[5]]))
