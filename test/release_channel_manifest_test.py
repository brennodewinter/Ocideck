"""Run with python3 -m unittest discover -s test -p release_channel_manifest_test.py."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('release_channel', Path(__file__).resolve().parents[1] / 'tool/release_channel.py')
channel = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(channel)


class ChannelManifestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.dist = self.base / 'dist'
        self.dist.mkdir()
        self.asset = self.dist / 'ocideck-web-0.7.7.tar.gz'
        self.asset.write_bytes(b'real archive bytes')
        self.args = SimpleNamespace(tag='v0.7.7', sha='a' * 40, controller_sha='b' * 40, channel='web', run_id='42', dist=self.dist,
                                    output=self.base / 'manifest.json', manifest=self.base / 'manifest.json')

    def test_create_verify_repeat_and_checksum(self):
        result = channel.create(self.args)
        self.assertEqual(result, channel.verify(self.args))
        before = self.args.output.read_bytes()
        self.assertEqual(result, channel.create(self.args))
        self.assertEqual(before, self.args.output.read_bytes())
        self.assertEqual(f"{result['files'][self.asset.name]}  {self.asset.name}\n",
                         (self.base / 'SHA256SUMS.web').read_text())

    def test_every_channel_requires_all_owned_assets(self):
        self.asset.unlink()
        for name, templates in channel.CHANNELS.items():
            with self.subTest(channel=name):
                self.args.channel = name
                with self.assertRaises(ValueError):
                    channel.assets(self.dist, '0.7.7', name)
                for template in templates:
                    (self.dist / template.format(v='0.7.7')).write_bytes(b'bytes')
                self.assertEqual(len(templates), len(channel.assets(self.dist, '0.7.7', name)))
                for path in self.dist.iterdir():
                    path.unlink()

    def test_tamper_missing_empty_and_changed_identity(self):
        channel.create(self.args)
        for content in (b'tampered', b''):
            self.asset.write_bytes(content)
            with self.assertRaises(ValueError):
                channel.verify(self.args)
        self.asset.unlink()
        with self.assertRaises(ValueError):
            channel.verify(self.args)
        self.asset.write_bytes(b'real archive bytes')
        for key, bad in [('sha', 'b' * 40), ('controller_sha', 'c' * 40), ('tag', 'v0.7.8'), ('channel', 'macos')]:
            original = getattr(self.args, key)
            setattr(self.args, key, bad)
            with self.assertRaises(ValueError):
                channel.verify(self.args)
            setattr(self.args, key, original)

    def test_reject_unknown_traversal_duplicate_and_link(self):
        channel.create(self.args)
        data = json.loads(self.args.output.read_text())
        data['files']['../outside'] = 'c' * 64
        self.args.output.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            channel.verify(self.args)
        self.args.output.write_text('{"tag":"a", "tag":"b"}')
        with self.assertRaises(ValueError):
            channel.verify(self.args)
        unknown = self.dist / 'extra.bin'
        unknown.write_bytes(b'not owned')
        with self.assertRaises(ValueError):
            channel.assets(self.dist, '0.7.7', 'web')
        unknown.unlink()
        self.asset.unlink()
        self.asset.symlink_to(self.args.output)
        with self.assertRaises(ValueError):
            channel.assets(self.dist, '0.7.7', 'web')

    def test_shared_sbom_tamper_and_addition_invalidates_evidence(self):
        sbom = self.dist / 'ocideck-0.7.7.cdx.json'
        sbom.write_bytes(b'{}')
        result = channel.create(self.args)
        self.assertIn(sbom.name, result['files'])
        sbom.write_bytes(b'{"changed":true}')
        with self.assertRaises(ValueError):
            channel.verify(self.args)

    def test_special_files_and_unknown_metadata_are_rejected(self):
        self.asset.unlink()
        os.mkfifo(self.asset)
        with self.assertRaises(ValueError):
            channel.assets(self.dist, '0.7.7', 'web')
        self.asset.unlink()
        self.asset.write_bytes(b'archive')
        (self.dist / 'SHA256SUMS.attacker').write_bytes(b'unknown')
        with self.assertRaises(ValueError):
            channel.assets(self.dist, '0.7.7', 'web')

    def test_differing_evidence_never_overwritten(self):
        channel.create(self.args)
        before = self.args.output.read_bytes()
        self.asset.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            channel.create(self.args)
        self.assertEqual(before, self.args.output.read_bytes())

    def test_interruption_before_atomic_link_leaves_no_partial_manifest(self):
        with patch.object(channel.os, 'link', side_effect=OSError('simulated interruption')):
            with self.assertRaises(OSError):
                channel.create(self.args)
        self.assertFalse(self.args.output.exists())
        self.assertFalse(list(self.base.glob('.manifest-*')))
        channel.create(self.args)
        self.assertEqual(channel.verify(self.args)['source'], self.args.sha)

    def test_strict_identifiers(self):
        for key, values in [('tag', ['v01.2.3', '../v0.7.7', '0.7.7']),
                            ('sha', ['0' * 40, 'a' * 39, 'A' * 40]),
                            ('controller_sha', ['0' * 40, 'b' * 39, 'B' * 40]),
                            ('channel', ['linux', '../web']), ('run_id', ['0', '-1', 'x'])]:
            for value in values:
                with self.subTest(key=key, value=value):
                    original = getattr(self.args, key)
                    setattr(self.args, key, value)
                    with self.assertRaises(ValueError):
                        channel.create(self.args)
                    setattr(self.args, key, original)


if __name__ == '__main__':
    unittest.main()
