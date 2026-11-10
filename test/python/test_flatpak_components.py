import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('flatpak_components', Path(__file__).resolve().parents[2] / 'scripts/flatpak_components.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ArtifactInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'PACKAGES.tsv').write_text(''.join(f'libsample{i}\t1-2\tamd64\n' for i in range(11)))
        records = [dict(binary=f'libsample{i}', version='1-2', architecture='amd64',
                        source='sample', source_version='1-2') for i in range(11)]
        (self.root / 'SOURCES.json').write_text(json.dumps({'binary_packages': records}))
        (self.root / 'RUNTIME-COMMIT').write_text('a' * 64 + '\n')
        (self.root / 'FILES.sha256').write_text('b' * 64 + '  share/doc/ocideck-flatpak/sources/sample.dsc\n')

    def build(self):
        with patch.object(module.sys, 'argv', ['flatpak_components.py',
            str(self.root / 'PACKAGES.tsv'), str(self.root / 'FILES.sha256'),
            '1.0', str(self.root / 'components.cdx.json')]):
            module.main()

    def test_exact_source_identity_runtime_and_separate_licences(self):
        self.build()
        data = json.loads((self.root / 'components.cdx.json').read_text())
        self.assertEqual(data['metadata']['component']['licenses'][0]['license']['id'], 'GPL-3.0-or-later')
        props = {p['name']: p['value'] for p in data['metadata']['properties']}
        self.assertEqual(props['ocideck:own-source-license'], 'EUPL-1.2')
        self.assertEqual(props['flatpak:runtime:commit'], 'a' * 64)
        props = {p['name']: p['value'] for p in data['components'][0]['properties']}
        self.assertEqual(props['debian:source:version'], '1-2')

    def test_mismatched_binary_source_identity_fails(self):
        path = self.root / 'PACKAGES.tsv'
        path.write_text(path.read_text().replace('1-2', '1-3'))
        with self.assertRaisesRegex(ValueError, 'Source inventory mismatch'):
            self.build()

    def test_unknown_runtime_commit_fails(self):
        (self.root / 'RUNTIME-COMMIT').write_text('unknown')
        with self.assertRaisesRegex(ValueError, 'runtime commit'):
            self.build()

    def test_inventory_cannot_escape_application_root(self):
        (self.root / 'FILES.sha256').write_text('b' * 64 + '  lib/../../secret\n')
        with self.assertRaisesRegex(ValueError, 'Invalid copied-file'):
            self.build()


if __name__ == '__main__':
    unittest.main()
