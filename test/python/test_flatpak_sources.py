import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('flatpak_sources', Path(__file__).resolve().parents[2] / 'scripts/flatpak_sources.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SourceEnvelopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root = base / 'files'
        self.sources = base / 'sources'
        self.sources.mkdir()
        self.common = base / 'common'
        self.common.mkdir()
        for name in ['GPL-2', 'GPL-3', 'LGPL-2', 'LGPL-2.1', 'LGPL-3']:
            (self.common / name).write_text('fixture licence text')
        notices = self.root / 'share/doc/ocideck-flatpak'
        notices.mkdir(parents=True)
        (notices / 'FILES.sha256').write_text('')
        archive = self.sources / 'sample_1.orig.tar.xz'
        archive.write_bytes(b'source-envelope-test-fixture')
        checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.descriptor = self.sources / 'sample_1-2.dsc'
        self.descriptor.write_text(f'Format: 3.0 (quilt)\nSource: sample\nVersion: 1-2\nChecksums-Sha256:\n {checksum} {archive.stat().st_size} {archive.name}\n')
        self.records = [dict(binary='libsample1', version='1-2', architecture='amd64', source='sample', source_version='1-2')]

    def stage(self):
        module.stage(self.root, self.sources, self.records, self.common)

    def test_exact_sources_and_full_licences_are_delivered(self):
        self.stage()
        notices = self.root / 'share/doc/ocideck-flatpak'
        manifest = json.loads((notices / 'SOURCES.json').read_text())
        self.assertEqual(manifest['binary_packages'], self.records)
        self.assertTrue((notices / 'sources/sample_1-2.dsc').is_file())
        self.assertTrue((notices / 'licenses/GPL-3').is_file())
        for row in (notices / 'FILES.sha256').read_text().splitlines():
            expected, name = row.split('  ', 1)
            self.assertEqual(hashlib.sha256((self.root / name).read_bytes()).hexdigest(), expected)

    def test_missing_descriptor_blocks_packaging(self):
        self.descriptor.unlink()
        with self.assertRaisesRegex(ValueError, 'Missing matching source'):
            self.stage()

    def test_wrong_source_version_blocks_packaging(self):
        self.records[0]['source_version'] = '1-3'
        with self.assertRaisesRegex(ValueError, 'Missing matching source'):
            self.stage()

    def test_changed_archive_blocks_packaging(self):
        (self.sources / 'sample_1.orig.tar.xz').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Missing or changed'):
            self.stage()

    def test_path_traversal_blocks_packaging(self):
        self.descriptor.write_text(self.descriptor.read_text().replace('sample_1.orig.tar.xz', '../sample_1.orig.tar.xz'))
        with self.assertRaisesRegex(ValueError, 'Unsafe source'):
            self.stage()

    def test_missing_gnu_licence_text_blocks_packaging(self):
        (self.common / 'GPL-3').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing full GNU'):
            self.stage()

    def test_changed_installed_binary_is_rejected(self):
        packages = self.root / 'share/doc/ocideck-flatpak/PACKAGES.tsv'
        packages.write_text('libsample1\t1-2\tamd64\n')
        with patch.object(module.subprocess, 'check_output', side_effect=[
            '1-2\tsample\t1-2', '??5?????? /usr/lib/libsample.so.1\n',
        ]):
            with self.assertRaisesRegex(ValueError, 'Locally modified'):
                module.installed_sources(packages)

    def test_minimal_image_omitted_manual_does_not_block_sources(self):
        packages = self.root / 'share/doc/ocideck-flatpak/PACKAGES.tsv'
        packages.write_text('libsample1\t1-2\tamd64\n')
        with patch.object(module.subprocess, 'check_output', side_effect=[
            '1-2\tsample\t1-2', 'missing     /usr/share/man/man1/sample.1.gz\n',
        ]):
            self.assertEqual(module.installed_sources(packages), self.records)


if __name__ == '__main__':
    unittest.main()
