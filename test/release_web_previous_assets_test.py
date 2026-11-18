"""Open tabs retain exactly N-1 content-addressed resources during deployment."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / 'scripts/deploy_web.sh').read_text().split("<<'PYRETAIN'\n", 1)[1].split('\nPYRETAIN', 1)[0]


class PreviousReleaseTest(unittest.TestCase):
    def probe(self, problem=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old, new = root / 'old', root / 'new'
            old.mkdir(); new.mkdir()
            files = {'assets/doc.12345678.md': b'previous doc',
                     'main.dart.abcdef12.wasm': b'previous code',
                     'assets/older.11223344.md': b'N-2 inherited',
                     'canvaskit/skwasm.wasm': b'old engine'}
            for name, content in files.items():
                target = old / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
            entries = [{'url': name, 'urlHashed': not name.startswith('canvaskit/')}
                       for name in files if 'older.' not in name]
            if problem == 'traversal':
                entries.append({'url': '../secret', 'urlHashed': True})
            manifest = json.dumps({'version': 1, 'entries': entries}).encode()
            files['precache_manifest.json'] = manifest
            (old / 'precache_manifest.json').write_bytes(manifest)
            (old / 'SHA256SUMS').write_text(''.join(
                hashlib.sha256(content).hexdigest() + '  ' + name + '\n'
                for name, content in files.items()))
            if problem == 'tamper':
                (old / 'assets/doc.12345678.md').write_bytes(b'changed')
            if problem == 'symlink':
                (new / 'assets').symlink_to(old / 'assets', target_is_directory=True)
            if problem == 'collision':
                (new / 'main.dart.abcdef12.wasm').write_bytes(b'different')
            result = subprocess.run(['python3', '-', str(old), str(new)],
                                    input=SCRIPT, text=True, capture_output=True, timeout=10)
            if problem:
                self.assertNotEqual(result.returncode, 0, problem)
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((new / 'assets/doc.12345678.md').read_bytes(), b'previous doc')
                self.assertEqual((new / 'main.dart.abcdef12.wasm').read_bytes(), b'previous code')
                self.assertFalse((new / 'assets/older.11223344.md').exists())
                self.assertFalse((new / 'canvaskit/skwasm.wasm').exists())
                self.assertFalse((new / 'precache_manifest.json').exists())

    def test_preserves_one_generation_without_old_engine_or_manifest(self):
        self.probe()

    def test_rejects_tampering_traversal_symlinks_and_collisions(self):
        for problem in ('tamper', 'traversal', 'symlink', 'collision'):
            with self.subTest(problem=problem):
                self.probe(problem)


if __name__ == '__main__':
    unittest.main()
