import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(shutil.which('minisign'), 'minisign required for signature boundary')
class HomebrewChannelTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'homebrew').mkdir()
        for name in ('update_homebrew_cask.sh', 'verify_homebrew_cask.sh'):
            shutil.copyfile(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        shutil.copyfile(ROOT / 'homebrew/ocideck.rb.tmpl', self.root / 'homebrew/ocideck.rb.tmpl')
        self.key = self.root / 'test.key'
        subprocess.run(['minisign', '-G', '-W', '-s', str(self.key),
                        '-p', str(self.root / 'minisign.pub')], check=True, capture_output=True)
        self.digest = 'a' * 64
        self.manifest = self.root / 'channel-manifest-macos.json'
        self.sums = self.root / 'SHA256SUMS.macos'
        self.out = self.root / 'cask.rb'
        self.data = {'schema': 1, 'tag': 'v9.8.7', 'version': '9.8.7',
                     'source': 'b' * 40, 'controller_sha': 'c' * 40, 'channel': 'macos',
                     'run_id': '123', 'files': {'ocideck-macos-9.8.7.zip': self.digest}}
        self.env = dict(os.environ, SHA256SUMS_FILE=str(self.sums),
                        CHANNEL_MANIFEST_FILE=str(self.manifest))
        self.write_evidence()

    def sign(self, path):
        subprocess.run(['minisign', '-Sm', str(path), '-s', str(self.key),
                        '-x', str(path) + '.minisig'], check=True, capture_output=True)

    def write_evidence(self):
        self.manifest.write_text(json.dumps(self.data))
        self.sums.write_text(''.join(f'{value}  {name}\n'
                                    for name, value in sorted(self.data['files'].items())))
        self.sign(self.manifest)
        self.sign(self.sums)

    def generate(self):
        return subprocess.run(['bash', str(self.root / 'scripts/update_homebrew_cask.sh'),
                               'v9.8.7', str(self.out), '--channel', 'macos'],
                              env=self.env, capture_output=True, text=True)

    def verify(self, digest=None, url=None):
        return subprocess.run(['bash', str(self.root / 'scripts/verify_homebrew_cask.sh'),
                               '--expected-sha256', digest or self.digest,
                               '--expected-url', url or
                               'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/v9.8.7/ocideck-macos-9.8.7.zip',
                               'v9.8.7'], env=dict(self.env, CASK_FILE=str(self.out)),
                              capture_output=True, text=True)

    def test_signed_channel_generates_and_verifies_exact_url_and_hash(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_signed_wrong_identity_does_not_replace_existing_cask(self):
        self.out.write_text('preserve existing cask')
        self.data['tag'] = 'v9.8.6'
        self.write_evidence()
        self.assertNotEqual(self.generate().returncode, 0)
        self.assertEqual(self.out.read_text(), 'preserve existing cask')

    def test_tampered_manifest_and_independently_signed_wrong_sums_are_rejected(self):
        self.manifest.write_text(self.manifest.read_text() + ' ')
        self.assertNotEqual(self.generate().returncode, 0)
        self.write_evidence()
        self.sums.write_text('d' * 64 + '  ocideck-macos-9.8.7.zip\n')
        self.sign(self.sums)
        self.assertNotEqual(self.generate().returncode, 0)
        self.assertFalse(self.out.exists())

    def test_valid_version_does_not_hide_wrong_url_or_hash(self):
        self.assertEqual(self.generate().returncode, 0)
        self.assertNotEqual(self.verify(digest='d' * 64).returncode, 0)
        self.assertNotEqual(self.verify(url='https://example.org/wrong.zip').returncode, 0)

    def test_unknown_asset_and_duplicate_manifest_key_are_rejected(self):
        self.data['files']['other.zip'] = 'd' * 64
        self.write_evidence()
        self.assertNotEqual(self.generate().returncode, 0)
        self.data['files'].pop('other.zip')
        self.write_evidence()
        text = self.manifest.read_text().replace('"schema": 1', '"schema": 1, "schema": 1')
        self.manifest.write_text(text)
        self.sign(self.manifest)
        self.assertNotEqual(self.generate().returncode, 0)


if __name__ == '__main__':
    unittest.main()
