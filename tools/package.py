#!/usr/bin/env python3
"""Produce a deterministic latest-main install file list; no external dependencies."""
import argparse
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--check', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
files = sorted(path.relative_to(root).as_posix() for path in root.rglob('*.lua')
               if not any(part in {'.test-output', '.runtime', 'dist'} for part in path.relative_to(root).parts))
expected = '\n'.join(files) + '\n'
target = root / 'install.list'
if a.check:
    if not target.exists() or target.read_text() != expected:
        raise SystemExit('install.list is stale; run python3 tools/package.py')
else:
    target.write_text(expected)
print(f'{len(files)} Lua files in install.list')
