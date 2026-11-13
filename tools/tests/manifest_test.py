import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from tools.manifest import generate
from tools.sc_codec import decode


class ManifestTests(unittest.TestCase):
    def test_actual_component_catalog_builds_a_lua_readable_release(self):
        project = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = (project / 'install.list').read_text().splitlines()
            for path in ['components.json', 'install.list', *paths]:
                target = root / path; target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((project / path).read_bytes())
            def git(*args):
                return subprocess.run(['git', '-C', directory, *args], check=True, capture_output=True).stdout
            git('init'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid')
            git('add', '.'); git('commit', '-m', 'current source fixture')
            manifest, raw, lua = generate(root)
            self.assertEqual(set(manifest['files']), set(paths))
            self.assertIn('spacecross/defense/access.lua', manifest['components']['Core']['files'])
            self.assertNotIn('spacecross/defense/access.lua', manifest['components']['Defense']['files'])
            self.assertIn('spacecross/update/tests/service_test.lua', manifest['components']['Tests']['files'])
            target = root / 'manifest.sc'; target.write_bytes(raw)
            process = subprocess.run([sys.executable, str(project / 'tools/lua.py'), str(project / 'tools/check_manifest.lua'), str(target), manifest['revision']],
                                     cwd=project, capture_output=True, check=True)
            self.assertIn(b'Manifest OK:', process.stdout)
            target = root / 'manifest.lua'; target.write_text(lua)
            # The public Lua version table must also have valid Lua syntax.
            script = root / 'check.lua'; script.write_text('assert(loadfile(arg[1]))')
            subprocess.run([sys.executable, str(project / 'tools/lua.py'), str(script), str(target)], check=True, capture_output=True)

    def test_git_versions_dependencies_deleted_files_and_dirty_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.run(['git', '-C', directory, *args], check=True, capture_output=True).stdout.decode().strip()
            git('init'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid')
            catalog = {'Core': {'paths': ['core.lua'], 'requires': []},
                       'Autopilot': {'paths': ['pilot.lua', 'old.lua'], 'requires': ['Core']}}
            (root / 'components.json').write_text(json.dumps(catalog))
            (root / 'core.lua').write_text('return {}')
            (root / 'pilot.lua').write_text('return {pilot=true}')
            (root / 'old.lua').write_text('return 1')
            (root / 'install.list').write_text('core.lua\nold.lua\npilot.lua\n')
            git('add', '.'); git('commit', '-m', 'initial')
            first = git('rev-parse', 'HEAD')
            (root / 'pilot.lua').write_text('return {pilot=2}')
            git('add', '.'); git('commit', '-m', 'pilot')
            second = git('rev-parse', 'HEAD')
            manifest, raw, lua = generate(root)
            self.assertEqual(manifest['components']['Core']['version'], first)
            self.assertEqual(manifest['components']['Autopilot']['version'], second)
            self.assertEqual(manifest['files']['pilot.lua']['sha256'], hashlib.sha256(b'return {pilot=2}').hexdigest())
            self.assertEqual(decode(raw)['revision'], second.encode())
            self.assertIn('return {{', lua)
            (root / 'pilot.lua').write_text('uncommitted invalid source')
            self.assertEqual(generate(root)[1], raw)
            (root / 'old.lua').unlink()
            (root / 'install.list').write_text('core.lua\npilot.lua\n')
            git('add', 'old.lua', 'install.list'); git('commit', '-m', 'remove obsolete pilot file')
            third = git('rev-parse', 'HEAD')
            manifest, _, _ = generate(root)
            self.assertEqual(manifest['components']['Autopilot']['version'], third)
            self.assertNotIn('old.lua', manifest['files'])

    def test_stale_committed_install_list_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.run(['git', '-C', directory, *args], check=True, capture_output=True).stdout
            git('init'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid')
            (root / 'components.json').write_text(json.dumps({'Core': {'paths': ['core.lua'], 'requires': []}}))
            (root / 'core.lua').write_text('return {}'); (root / 'install.list').write_text('missing.lua\n')
            git('add', '.'); git('commit', '-m', 'bad list')
            with self.assertRaisesRegex(ValueError, 'install.list'):
                generate(root)


if __name__ == '__main__':
    unittest.main()
