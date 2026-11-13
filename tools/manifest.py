#!/usr/bin/env python3
"""Generate immutable component metadata from Git objects, not a dirty worktree.

Output: components.sc (data-only wire), components.lua (readable version table).
Run in a real checkout; GitHub release workflow publishes both for the exact SHA.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
try:
    from .sc_codec import encode
except ImportError:
    from sc_codec import encode


def git(root, *args):
    return subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True).stdout


def safe(path):
    return bool(re.fullmatch(r'[A-Za-z0-9_./-]+', path)) and not path.startswith('/') and not path.endswith('/') and all(v not in ('', '.', '..') for v in path.split('/'))


def owner(path, catalog):
    # Portable test suites live together; installing Tests pulls their domain modules.
    if '/tests/' in path and 'Tests' in catalog:
        return 'Tests'
    matches = [(len(prefix), name) for name, entry in catalog.items() for prefix in entry['paths']
               if path == prefix or path.startswith(prefix + '/')]
    if not matches:
        raise ValueError('unowned file: ' + path)
    best = max(n for n, _ in matches)
    names = {name for n, name in matches if n == best}
    if len(names) != 1:
        raise ValueError('ambiguous component: ' + path)
    return names.pop()


def generate(root, revision='HEAD'):
    root = Path(root).resolve()
    if Path(git(root, 'rev-parse', '--show-toplevel').decode().strip()).resolve() != root:
        raise ValueError('root must be its own Git checkout')
    sha = git(root, 'rev-parse', '--verify', revision + '^{commit}').decode().strip()
    if not re.fullmatch('[0-9a-f]{40}', sha):
        raise ValueError('40-character Git commit required')
    catalog = json.loads(git(root, 'show', sha + ':components.json'))
    if not isinstance(catalog, dict) or not 1 <= len(catalog) <= 64:
        raise ValueError('invalid component catalog')
    for name, entry in catalog.items():
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', name) or not isinstance(entry, dict) or set(entry) != {'paths', 'requires'}:
            raise ValueError('invalid catalog entry')
        if not isinstance(entry['paths'], list) or not isinstance(entry['requires'], list) or not entry['paths'] or any(not safe(v) for v in entry['paths']) or any(v not in catalog for v in entry['requires']):
            raise ValueError('invalid component paths/dependencies')
    if 'Core' not in catalog:
        raise ValueError('Core component required')
    visited, active = set(), set()
    def visit(name):
        if name in active:
            raise ValueError('dependency cycle')
        if name not in visited:
            active.add(name)
            for dependency in catalog[name]['requires']:
                visit(dependency)
            active.remove(name); visited.add(name)
    for name in catalog:
        visit(name)
    names = git(root, 'show', sha + ':install.list').decode().splitlines()
    tracked = [p for p in git(root, 'ls-tree', '-r', '--name-only', sha).decode().splitlines() if p.endswith('.lua')]
    if names != sorted(set(names)) or set(names) != set(tracked) or any(not safe(v) for v in names):
        raise ValueError('install.list does not match committed Lua files')
    components = {name: dict(files=[], requires=sorted(set(entry['requires']))) for name, entry in catalog.items()}
    files, history = {}, {name: set() for name in catalog}
    for path in names:
        name = owner(path, catalog)
        raw = git(root, 'show', sha + ':' + path)
        if len(raw) > 1048576:
            raise ValueError('file exceeds release limit')
        files[path] = dict(size=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        components[name]['files'].append(path); history[name].add(path)
    # Deleted files must still affect the owning component's version.
    removed = git(root, 'log', '--format=', '--name-only', '--diff-filter=D', sha).decode().splitlines()
    for path in set(removed):
        if path.endswith('.lua'):
            try:
                history[owner(path, catalog)].add(path)
            except ValueError:
                pass  # A historical component can have been deliberately retired.
    for name, paths in history.items():
        components[name]['version'] = git(root, 'log', '-1', '--format=%H', sha, '--', 'components.json', *sorted(paths)).decode().strip()
    if len(files) > 4096 or sum(v['size'] for v in files.values()) > 16777216:
        raise ValueError('release resource limit')
    manifest = dict(v=1, revision=sha, components=components, files=files)
    raw = encode(manifest)
    if len(raw) > 131072:
        raise ValueError('manifest exceeds receiver limit')
    # The executable-looking format is for review only; network clients parse .sc.
    lines = ['-- Generated from Git objects; runtime reads components.sc without eval.', 'return {{']
    for name, entry in sorted(components.items()):
        quoted = ', '.join(json.dumps(p) for p in entry['files'])
        required = ', '.join(json.dumps(p) for p in entry['requires'])
        lines.append(f'  [{json.dumps(name)}] = {{version = "{entry["version"]}", files = {{{quoted}}}, requires = {{{required}}}}},')
    lines.append('}}\n')
    return manifest, raw, '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--revision', default='HEAD')
    parser.add_argument('--out', type=Path, default=Path('dist'))
    args = parser.parse_args()
    value, raw, lua = generate(args.root, args.revision)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'components.sc').write_bytes(raw)
    (args.out / 'components.lua').write_text(lua)
    print(value['revision'], len(value['files']), 'files')


if __name__ == '__main__':
    main()
