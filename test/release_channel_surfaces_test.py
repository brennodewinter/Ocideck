"""Public pointer regressions without credentials or publication."""
import hashlib
import gzip
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
    def row(self, key, url):
        return '<li class="product-download" data-ocideck-download="' + key + '"><a class="product-action-primary" data-ocideck-download-primary href="' + url + '">Download</a></li>'

    def test_nine_selected_rows_ignore_other_os_before_readback_and_resume(self):
        expected = {'windows': 'https://release/zip', 'windows_installer': 'https://release/setup'}
        proof = {'pages': {language: 'a' * 64 for language in surfaces.LANGUAGES}}
        selected = ''.join(self.row(key, url) for key, url in expected.items())
        for rollback in (False, True):
            for other_version in ('1.2.3', '1.2.4'):
                urls = []
                content = '<ul>' + selected + self.row('linux_tar', 'https://other/' + other_version) + '</ul>'
                surfaces.verify_pages(proof, expected, lambda url: urls.append(url) or content.encode())
                self.assertEqual(len(urls), 9)
                self.assertIn('https://librekat.nl/nl/ocideck/', urls)
        for bad in (selected.replace('https://release/setup', 'https://evil/setup'),
                    selected.replace('https://release/zip', 'https://release/wrong'),
                    self.row('windows', expected['windows']),
                    selected + self.row('windows', expected['windows']),
                    selected.replace('https://release/zip', 'https://evil/zip') + '<a hidden href="https://release/zip">hidden correct</a>'):
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, 'selected'):
                surfaces.verify_pages(proof, expected, lambda _: ('<ul>' + bad + '</ul>').encode())

    def test_minified_optional_end_tags_preserve_primary_row_identity(self):
        expected = {'macos': 'https://release/mac'}
        text = '<html><body><ul><li data-ocideck-download=macos><p>copy<a class=product-action-primary data-ocideck-download-primary href=https://release/mac>Download</a><li>other</ul></body></html>'
        proof = {'pages': dict.fromkeys(surfaces.LANGUAGES, 'a' * 64)}
        surfaces.verify_pages(proof, expected, lambda _: text.encode())
        surfaces.verify_pages(proof, expected, lambda _: text.replace('<li>other', '').encode())

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

    def test_announced_archive_budget_rejected_before_body_or_destination(self):
        for kind, size, error in ((tarfile.REGTYPE, surfaces.WEB_DATA_LIMIT + 1, 'storage'),
                                  (tarfile.XHDTYPE, surfaces.WEB_METADATA_LIMIT + 1, 'metadata'),
                                  (tarfile.GNUTYPE_LONGNAME, surfaces.WEB_METADATA_LIMIT + 1, 'metadata')):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                info = tarfile.TarInfo('header')
                info.type, info.size = kind, size
                archive = root / 'tiny.tar.gz'
                archive.write_bytes(gzip.compress(info.tobuf()))
                with self.assertRaisesRegex(ValueError, error):
                    surfaces.extract_web(archive, root / 'out', '1.2.3')
                self.assertFalse((root / 'out').exists())
                self.assertLess(archive.stat().st_size, 1024)

    def test_sparse_pax_body_is_rejected_before_sparse_map_read(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            info = tarfile.TarInfo('sparse')
            info.pax_headers = {'GNU.sparse.major': '1', 'GNU.sparse.minor': '0'}
            archive = root / 'sparse.tar.gz'
            archive.write_bytes(gzip.compress(info.tobuf(format=tarfile.PAX_FORMAT)))
            with self.assertRaisesRegex(ValueError, 'sparse web archive metadata'):
                surfaces.extract_web(archive, root / 'out', '1.2.3')
            self.assertFalse((root / 'out').exists())

    def test_member_limit_stops_before_reading_next_body(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            headers = b''.join(tarfile.TarInfo(str(i)).tobuf() for i in range(3))
            archive = root / 'count.tar.gz'
            archive.write_bytes(gzip.compress(headers))
            with patch.object(surfaces, 'WEB_MEMBER_LIMIT', 2):
                with self.assertRaisesRegex(ValueError, 'too many members'):
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

    def web_args(self, directory, rollback=False):
        root = Path(directory)
        args = SimpleNamespace(state_dir=root, tag='v1.2.3', channel='web', sha='a' * 40,
            controller_sha='b' * 40, dist=root / 'dist', evidence=root / 'evidence', run_id='123',
            rollback_from='v1.2.4' if rollback else None)
        args.dist.mkdir()
        (args.dist / 'ocideck-web-1.2.3.tar.gz').write_bytes(b'authenticated archive')
        state = root / args.tag
        state.mkdir()
        import release_journal
        release_journal.initialize(SimpleNamespace(journal=state / 'web.json', tag=args.tag,
            sha=args.sha, channel='web', workflow=Path(__file__).resolve().parents[1] / '.forgejo/workflows/release-channel.yml'))
        return args

    def test_preflight_repair_retries_same_bytes_but_unknown_deploy_never_repeats(self):
        from contextlib import ExitStack
        for rollback in (False, True):
            for unknown in (False, True):
                with self.subTest(rollback=rollback, unknown=unknown), tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
                    args = self.web_args(directory, rollback)
                    stack.enter_context(patch.object(surfaces, 'release_channel_control_publish', return_value=0))
                    stack.enter_context(patch.object(surfaces, 'release_channel_control_paths'))
                    stack.enter_context(patch.object(surfaces, 'check_rollback_pointer'))
                    stack.enter_context(patch.object(surfaces, 'extract_web', side_effect=lambda _a, dest, _v: dest.mkdir()))
                    stack.enter_context(patch.object(surfaces, 'web_files', return_value={'index.html': 'c' * 64}))
                    verify = stack.enter_context(patch.object(surfaces, 'verify_web'))
                    run = stack.enter_context(patch.object(surfaces.subprocess, 'run'))
                    run.side_effect = [SimpleNamespace(returncode=0), SimpleNamespace(returncode=1)] if unknown else [SimpleNamespace(returncode=1)]
                    with self.assertRaises(ValueError):
                        surfaces.public(args, object())
                    intent, _ = surfaces.phase_paths(args, 'web')
                    self.assertEqual(intent.exists(), unknown)
                    run.side_effect = [SimpleNamespace(returncode=0), SimpleNamespace(returncode=0)]
                    if unknown:
                        verify.side_effect = ValueError('live still old; outcome unknown')
                        with self.assertRaisesRegex(ValueError, 'unknown'):
                            surfaces.public(args, object())
                        self.assertEqual(run.call_count, 2)
                    else:
                        surfaces.public(args, object())
                        self.assertEqual(run.call_count, 3)
                        self.assertIn('--preflight-only', run.call_args_list[1].args[0])

    def rollback_args(self, directory, channel='web'):
        return SimpleNamespace(state_dir=Path(directory), tag='v1.2.3', channel=channel,
            rollback_from='v1.2.4', operation_id='rollback-test', sha='a' * 40,
            controller_sha='b' * 40)

    def test_rollback_must_be_strictly_older_and_separate_state(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.rollback_args(directory)
            surfaces.validate_rollback(args)
            intent, _ = surfaces.phase_paths(args, 'web')
            self.assertIn('rollback-from-v1.2.4-web-intent', intent.name)
            args.tag = 'v1.2.5'
            with self.assertRaisesRegex(ValueError, 'strictly older'):
                surfaces.validate_rollback(args)

    def test_partial_rollback_accepts_only_owned_target(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.rollback_args(directory)
            current = lambda _: b'{"version":"1.2.4"}'
            target = lambda _: b'{"version":"1.2.3"}'
            surfaces.check_rollback_pointer(args, current)
            with self.assertRaisesRegex(ValueError, 'current public pointer'):
                surfaces.check_rollback_pointer(args, target)
            intent, _ = surfaces.phase_paths(args, 'web')
            intent.parent.mkdir(parents=True)
            intent.write_text(json.dumps({'tag': args.tag, 'channel': args.channel}))
            surfaces.check_rollback_pointer(args, target)
            with self.assertRaisesRegex(ValueError, 'current public pointer'):
                surfaces.check_rollback_pointer(args, lambda _: b'{"version":"1.2.5"}')

    def test_download_row_guard_rejects_wrong_or_incomplete_channel(self):
        content = b'<a href="https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/v1.2.4/ocideck-linux-x64-1.2.4.tar.gz">Linux</a>'
        self.assertEqual(surfaces.page_tags(content, 'linux-tar'), {'v1.2.4'})
        with self.assertRaisesRegex(ValueError, 'unavailable'):
            surfaces.page_tags(content, 'windows')
        with self.assertRaisesRegex(ValueError, 'disagree'):
            surfaces.page_tags(content.replace(b'download/v1.2.4/', b'download/v1.2.3/'), 'linux-tar')

    def test_homebrew_lost_dispatch_response_is_never_repeated(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.rollback_args(directory, 'macos')
            args.rollback_from = None
            args.evidence = Path(directory) / 'evidence'
            args.evidence.mkdir()
            (args.evidence / 'channel-manifest-macos.json').write_text(json.dumps({
                'files': {'ocideck-macos-1.2.3.zip': 'c' * 64}}))
            root = Path(__file__).resolve().parents[1]
            state = args.state_dir / args.tag
            state.mkdir()
            import release_journal
            release_journal.initialize(SimpleNamespace(journal=state / 'macos.json', tag=args.tag,
                sha=args.sha, channel='macos', workflow=root / '.forgejo/workflows/release-channel.yml'))
            class API:
                def __init__(self):
                    self.posts = []
                def get(self, path):
                    if path == '/git/refs/heads/main':
                        return {'object': {'sha': 'd' * 40}}
                    return {'workflow_runs': []}
                def post(self, path, value):
                    self.posts.append((path, value))
                    raise OSError('lost dispatch response')
            api = API()
            with patch('release_channel_controller.Forgejo', return_value=api):
                with self.assertRaisesRegex(OSError, 'lost dispatch'):
                    surfaces.homebrew(args, root)
                with self.assertRaisesRegex(ValueError, 'never repeat POST'):
                    surfaces.homebrew(args, root)
            self.assertEqual(len(api.posts), 1)
            self.assertEqual(api.posts[0][1]['inputs']['pin'], 'false')

    def test_new_main_reuses_only_identical_reviewed_website_workflow(self):
        import base64
        with tempfile.TemporaryDirectory() as directory:
            args = self.rollback_args(directory, 'linux-tar')
            args.rollback_from = None
            root = Path(__file__).resolve().parents[1]
            definition = (root / '.forgejo/workflows/website-downloads.yml').read_bytes()
            class API:
                def __init__(self):
                    self.posts = []
                def get(self, path):
                    if path == '/git/refs/heads/main':
                        return {'object': {'sha': 'd' * 40}}
                    if path.startswith('/contents/'):
                        return {'encoding': 'base64', 'content': base64.b64encode(definition).decode()}
                    return {'workflow_runs': []}
                def post(self, path, value):
                    self.posts.append((path, value))
            api = API()
            def begin(_args, phase, value):
                intent, _ = surfaces.phase_paths(args, phase)
                intent.parent.mkdir(parents=True)
                intent.write_text(json.dumps(value))
            with patch.object(surfaces, 'begin', side_effect=begin):
                with self.assertRaisesRegex(ValueError, 'website dispatched'):
                    surfaces.website(args, api)
            intent, _ = surfaces.phase_paths(args, 'website')
            self.assertEqual(json.loads(intent.read_text())['controller'], 'd' * 40)
            with self.assertRaisesRegex(ValueError, 'never repeat POST'):
                surfaces.website(args, api)
            self.assertEqual(len(api.posts), 1)

    def test_rollback_never_calls_asset_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.rollback_args(directory)
            args.dist = Path(directory) / 'dist'
            args.evidence = Path(directory) / 'evidence'
            args.run_id = '123'
            with patch.object(surfaces, 'release_channel_control_publish', return_value=1) as verify:
                with self.assertRaisesRegex(ValueError, 'signed asset readback'):
                    surfaces.public(args, object())
            self.assertTrue(verify.call_args.args[0].status)


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
