import tempfile
import unittest
from pathlib import Path

from server.store import Store


class SatelliteStoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.temp.name) / 'state.sqlite3')

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_whitelist_is_bounded_deduplicated_and_node_scoped(self):
        self.assertEqual(self.store.set_satellite_whitelist('node-a', ['B', 'A', 'B']), ['A', 'B'])
        self.assertEqual(self.store.satellite_whitelist('node-a'), ['A', 'B'])
        self.assertEqual(self.store.satellite_whitelist('node-b'), [])
        with self.assertRaises(ValueError):
            self.store.set_satellite_whitelist('node-a', [''])

    def test_heartbeat_and_attack_alert_are_durable(self):
        self.store.satellite_heartbeat('node-a', {'mode': b'charges', 'state': b'idle'})
        row = self.store.db.execute('SELECT mode,state FROM satellite_status WHERE node=?', ('node-a',)).fetchone()
        self.assertEqual(row, ('charges', 'idle'))
        self.assertEqual(self.store.satellite_status('node-a')['state'], 'idle')
        ident = self.store.satellite_alert('node-a', 'Ship', {'mode': b'jump', 'target': {'id': b'hostile'}})
        row = self.store.db.execute('SELECT node,subject,mode FROM satellite_alerts WHERE id=?', (ident,)).fetchone()
        self.assertEqual(row, ('node-a', 'Ship', 'jump'))
        self.assertEqual(self.store.satellite_alerts('node-a')[0]['target']['id'], 'hostile')


if __name__ == '__main__':
    unittest.main()
