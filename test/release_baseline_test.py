"""No network: baseline metadata and signatures use explicit fault fixtures."""
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_baseline as baseline


class FakeTransport:
    def __init__(self):
        self.release = {'id': 8, 'tag_name': 'v0.7.7', 'draft': False, 'prerelease': False}
        self.manifest = dict(schema=1, tag='v0.7.7', version='0.7.7', source='a' * 40,
            controller_sha='b' * 40, channel='web', run_id='42', files={'ocideck-web-0.7.7.tar.gz': 'c' * 64})
        self.assets = [{'name': name, 'browser_download_url': 'https://forge.invalid/' + name} for name in
            ('channel-manifest-web.json', 'channel-manifest-web.json.minisig', 'ocideck-web-0.7.7.tar.gz')]

    def data(self, path):
        return self.release if path.startswith('/releases/tags/') else self.assets

    def get(self, url):
        return b'signature' if url.endswith('.minisig') else json.dumps(self.manifest).encode()


class ReleaseBaselineTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / 'scripts').mkdir()
        (self.repo / 'scripts/release.sh').write_text('local abandoned_tags=(\n v1.2.1 # explicit existing policy\n)')
        self.args = SimpleNamespace(repo=self.repo, current_version='0.7.6', current_build=48,
                                    api='https://forge.invalid/api', public_key=self.repo / 'key')
        self.transport = FakeTransport()
        self.tags = {'v0.7.6': 'd' * 40, 'v0.7.7': 'a' * 40, 'v1.2.1': 'e' * 40}

    def run_baseline(self, signature_error=False, mirror=None):
        def remote(repo, name):
            return self.tags if name == 'origin' or mirror is None else mirror
        with patch.object(baseline, 'remote_tags', side_effect=remote), \
             patch.object(baseline, 'git', return_value='version: 0.7.7+49\n'), \
             patch.object(baseline, 'signature', side_effect=ValueError('invalid signature') if signature_error else None):
            return baseline.baseline(self.args, self.transport)

    def test_complete_unpaginated_asset_list_at_fifty(self):
        assets = [{'name': f'asset-{i}'} for i in range(50)]
        with patch.object(self.transport, 'data', return_value=assets) as request:
            result = baseline.asset_listing(self.transport, 8)
        self.assertEqual({asset['name']: asset for asset in assets}, result)
        request.assert_called_once_with('/releases/8/assets')

    def test_asset_list_rejects_invalid_entries_and_duplicate_names(self):
        for values in ({}, [{'name': f'asset-{i}'} for i in range(5001)], [None], [{'name': None}], [{'name': ''}],
                       [{'name': 'same'}, {'name': 'same'}]):
            with self.subTest(values=values), patch.object(self.transport, 'data', return_value=values):
                with self.assertRaises(ValueError):
                    baseline.asset_listing(self.transport, 8)

    def test_highest_signed_publication_and_shared_abandoned_policy(self):
        self.assertEqual({'version': '0.7.7', 'build': 49, 'tag': 'v0.7.7', 'source': 'a' * 40}, self.run_baseline())
        self.args.current_build = 55
        self.assertEqual(55, self.run_baseline()['build'])

    def test_unpublished_higher_tag_blocks_instead_of_skipping(self):
        self.tags['v0.7.8'] = 'f' * 40
        with self.assertRaisesRegex(ValueError, 'highest tag'):
            self.run_baseline()

    def test_mirror_mismatch_and_invalid_signature_rejected(self):
        with self.assertRaises(ValueError):
            self.run_baseline(mirror={'v0.7.7': 'f' * 40})
        with self.assertRaisesRegex(ValueError, 'signature'):
            self.run_baseline(signature_error=True)

    def test_identity_missing_asset_and_draft_rejected(self):
        self.transport.manifest['source'] = 'f' * 40
        with self.assertRaisesRegex(ValueError, 'identity'):
            self.run_baseline()
        self.transport.manifest['source'] = 'a' * 40
        self.transport.assets.pop()
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            self.run_baseline()
        self.transport.release['draft'] = True
        with self.assertRaisesRegex(ValueError, 'publicly released'):
            self.run_baseline()

    def test_absent_public_tag_and_missing_signature_rejected(self):
        self.tags.clear()
        with self.assertRaisesRegex(ValueError, 'no public tag'):
            self.run_baseline()
        self.tags['v0.7.7'] = 'a' * 40
        self.transport.assets.pop(1)
        with self.assertRaisesRegex(ValueError, 'missing public evidence'):
            self.run_baseline()

    def test_remote_annotated_tag_peeling(self):
        body = f"{'b' * 40}\trefs/tags/v0.7.7\n{'a' * 40}\trefs/tags/v0.7.7^{{}}\n{'f' * 40}\trefs/tags/v0.7.8-rc1\n"
        with patch.object(baseline, 'git', return_value=body):
            self.assertEqual({'v0.7.7': 'a' * 40}, baseline.remote_tags(self.repo, 'origin'))

    def test_transport_rejects_non_https_and_cross_host_before_open(self):
        with self.assertRaises(ValueError):
            baseline.PublicTransport('http://forge.invalid/api')
        transport = baseline.PublicTransport('https://forge.invalid/api')
        with patch.object(transport.opener, 'open') as opened:
            with self.assertRaises(ValueError):
                transport.get('https://other.invalid/asset')
            opened.assert_not_called()
        with self.assertRaises(ValueError):
            baseline.NoRedirect().redirect_request(None, None, None, None, None, None)

    def test_pubspec_identity_required(self):
        with patch.object(baseline, 'remote_tags', return_value=self.tags), \
             patch.object(baseline, 'git', return_value='version: 0.7.6+48\n'), \
             patch.object(baseline, 'signature'):
            with self.assertRaisesRegex(ValueError, 'pubspec differs'):
                baseline.baseline(self.args, self.transport)

    def test_signature_runs_actual_verifier_contract(self):
        def verify(command, **kwargs):
            self.assertEqual('minisign', command[0])
            self.assertEqual(b'manifest', Path(command[2]).read_bytes())
            self.assertEqual(b'signature', Path(command[4]).read_bytes())
            return SimpleNamespace(returncode=0)
        with patch.object(baseline.subprocess, 'run', side_effect=verify):
            baseline.signature(b'manifest', b'signature', self.args.public_key)
        with patch.object(baseline.subprocess, 'run', return_value=SimpleNamespace(returncode=1)):
            with self.assertRaisesRegex(ValueError, 'signature'):
                baseline.signature(b'manifest', b'signature', self.args.public_key)

    def test_global_signed_manifest_exact_assets(self):
        version = '0.7.7'
        names = {n.format(v=version) for templates in baseline.CHANNELS.values() for n in templates}
        names.discard('ocideck-windows-cohort-0.7.7.json')
        names |= {'ocideck-0.7.7.cdx.json', 'ocideck-0.7.7.spdx.json'}
        assets = {n: {'browser_download_url': 'https://forge.invalid/' + n} for n in names | {'SHA256SUMS', 'SHA256SUMS.minisig'}}
        body = ''.join('c' * 64 + '  ./' + n + '\n' for n in sorted(names)).encode()
        with patch.object(self.transport, 'get', side_effect=lambda u: b'sig' if u.endswith('.minisig') else body), \
             patch.object(baseline, 'signature'):
            baseline.public_proof(self.transport, assets, 'v0.7.7', 'a' * 40, self.args.public_key)
            assets.pop('ocideck-web-0.7.7.tar.gz')
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                baseline.public_proof(self.transport, assets, 'v0.7.7', 'a' * 40, self.args.public_key)

    def test_global_manifest_accepts_only_matching_public_source_kit(self):
        version = '0.7.8'
        required = {n.format(v=version) for templates in baseline.CHANNELS.values() for n in templates}
        required.discard('ocideck-windows-cohort-0.7.8.json')
        required |= {'ocideck-0.7.8.cdx.json', 'ocideck-0.7.8.spdx.json'}
        for extra, public, valid in (
            ('ocideck-linux-sources-0.7.8.tar.gz', True, True),
            ('ocideck-linux-sources-0.7.8.tar.gz', False, False),
            ('ocideck-linux-sources-0.7.7.tar.gz', True, False),
            ('unexpected.tar.gz', True, False),
        ):
            with self.subTest(extra=extra, public=public):
                names = required | {extra}
                assets = {n: {'browser_download_url': 'https://forge.invalid/' + n}
                          for n in names | {'SHA256SUMS', 'SHA256SUMS.minisig'} if public or n != extra}
                body = ''.join('c' * 64 + '  ./' + n + '\n' for n in sorted(names)).encode()
                with patch.object(self.transport, 'get', side_effect=lambda u: b'sig' if u.endswith('.minisig') else body), \
                     patch.object(baseline, 'signature'):
                    if valid:
                        baseline.public_proof(self.transport, assets, 'v0.7.8', 'a' * 40, self.args.public_key)
                    else:
                        with self.assertRaisesRegex(ValueError, 'incomplete'):
                            baseline.public_proof(self.transport, assets, 'v0.7.8', 'a' * 40, self.args.public_key)


if __name__ == '__main__':
    unittest.main()
