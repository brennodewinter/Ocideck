"""Public pointer regressions without credentials or publication."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_channel_surfaces as surfaces


class PublicSurfacesTest(unittest.TestCase):
    def test_nine_languages_and_wrong_live_bytes(self):
        content = b'checked page'
        proof = {'pages': {language: hashlib.sha256(content).hexdigest() for language in surfaces.LANGUAGES}}
        urls = []
        surfaces.verify_pages(proof, lambda url: urls.append(url) or content)
        self.assertEqual(len(urls), 9)
        self.assertIn('https://librekat.nl/ocideck/', urls)
        with self.assertRaisesRegex(ValueError, 'differs'):
            surfaces.verify_pages(proof, lambda _: b'stale')

    def archive(self, root, names):
        path = root / 'bundle.tar.gz'
        with tarfile.open(path, 'w:gz') as archive:
            for name, kind, content in names:
                member = tarfile.TarInfo(name)
                member.type = kind
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
        return path

    def test_unsafe_archive_rejected_before_destination(self):
        for names in [[('../escape', tarfile.REGTYPE, b'x')],
                      [('link', tarfile.SYMTYPE, b'')],
                      [('same', tarfile.REGTYPE, b'a'), ('./same', tarfile.REGTYPE, b'b')]]:
            with self.subTest(names=names), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = self.archive(root, names)
                with self.assertRaises(ValueError):
                    surfaces.extract_web(archive, root / 'out', '1.2.3')
                self.assertFalse((root / 'out').exists())

    def test_storage_checked_before_extract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.archive(root, [('version.json', tarfile.REGTYPE, b'{"version":"1.2.3"}')])
            with patch.object(surfaces.shutil, 'disk_usage', return_value=SimpleNamespace(free=0)):
                with self.assertRaisesRegex(ValueError, 'storage'):
                    surfaces.extract_web(archive, root / 'out', '1.2.3')
            self.assertFalse((root / 'out').exists())

    def test_exact_web_files_and_live_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = b'web app'
            (root / 'main.js').write_bytes(data)
            digest = hashlib.sha256(data).hexdigest()
            (root / 'SHA256SUMS').write_text(digest + '  main.js\n')
            self.assertEqual(surfaces.verify_web(root, lambda url: (root / 'SHA256SUMS').read_bytes() if url.endswith('/SHA256SUMS') else data), {'main.js': digest})
            with self.assertRaisesRegex(ValueError, 'live web'):
                surfaces.verify_web(root, lambda url: (root / 'SHA256SUMS').read_bytes() if url.endswith('/SHA256SUMS') else b'old')
            (root / 'extra.js').write_bytes(b'unlisted')
            with self.assertRaisesRegex(ValueError, 'exact files'):
                surfaces.web_files(root)

    def test_redirect_or_insecure_url_is_not_public_proof(self):
        for url in ('http://librekat.nl/ocideck/', 'https://user@librekat.nl/ocideck/'):
            with self.assertRaisesRegex(ValueError, 'HTTPS'):
                surfaces.fetch(url)

    def test_local_bundle_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'linked').symlink_to('/tmp', target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'real directories'):
                surfaces.web_files(root)

    def test_unknown_dispatch_never_repeated(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(state_dir=Path(directory), tag='v1.2.3', channel='linux-tar',
                                   operation_id='nonce', controller_sha='a' * 40)
            intent, _ = surfaces.phase_paths(args, 'website')
            intent.parent.mkdir(parents=True)
            intent.write_text(json.dumps(dict(tag=args.tag, channel=args.channel,
                operation_id='nonce-website', controller=args.controller_sha)))
            class API:
                def get(self, _path):
                    return {'workflow_runs': []}
                def post(self, *_args):
                    raise AssertionError('must never redispatch')
            with self.assertRaisesRegex(ValueError, 'never repeat'):
                surfaces.website(args, API())

    def test_status_is_not_live_success(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(state_dir=Path(directory), tag='v1.2.3', channel='windows')
            intent, receipt = surfaces.phase_paths(args, 'website')
            intent.parent.mkdir(parents=True)
            self.assertEqual(surfaces.public_status(args), {'website': 'not_started'})
            intent.write_text('{}')
            self.assertEqual(surfaces.public_status(args), {'website': 'unknown'})
            receipt.write_text(json.dumps({'tag': args.tag, 'channel': args.channel}))
            self.assertEqual(surfaces.public_status(args), {'website': 'recorded_completed_live_unverified'})


if __name__ == '__main__':
    unittest.main()
