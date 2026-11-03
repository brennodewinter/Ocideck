"""Version-wide status requires fresh channel bytes and public readback, never writes."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
import release_channel_controller as control


class VersionOverviewTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.args = SimpleNamespace(state_dir=Path(self.temporary.name), tag='v1.2.3', sha='a' * 40,
            expected_channels=['macos', 'windows', 'linux-rpm'])

    def operation(self, channel, source=None):
        args = SimpleNamespace(**vars(self.args), channel=channel, controller_sha='b' * 40,
                               operation_id=channel + '-operation')
        value = control.identity(args)
        value['source'] = source or args.sha
        path = control.operation_path(args)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def test_mixed_channels_then_later_windows_never_rebuilds_mac(self):
        for channel in self.args.expected_channels:
            self.operation(channel)
        states = {'macos': ('success', 'completed'), 'windows': ('success', 'pending'),
                  'linux-rpm': ('failure', 'failed')}
        api = SimpleNamespace(post=lambda *_args: self.fail('overview must not dispatch'))
        def status(args, actual_api):
            self.assertIs(api, actual_api)
            control.read_operation(args)
            state, outcome = states[args.channel]
            return {'runs': [dict(id=42, status=state, outcome=outcome)],
                    'build_metadata': 'success' if (state, outcome) == ('success', 'completed') else 'unproven'}
        def public(args):
            self.assertEqual('a' * 40, args.sha)
            self.assertEqual('42', args.run_id)
            return {'assets': 'verified', 'public': 'verified'}
        with patch.object(control, 'status', side_effect=status), \
             patch.object(control, 'overview_readback', side_effect=public) as readback:
            first = control.overview(self.args, api)
            self.assertEqual('partial', first['publication'])
            self.assertEqual('pending', first['channels']['windows']['state'])
            self.assertEqual('failed', first['channels']['linux-rpm']['state'])
            self.assertEqual(set(control.release_channel.CHANNELS), set(first['channels']))
            self.assertEqual('unknown', first['channels']['web']['state'])
            states['windows'] = ('success', 'completed')
            second = control.overview(self.args, api)
            self.assertEqual('partial', second['publication'])
            self.assertEqual(['macos', 'windows'], second['published_channels'])
            self.args.expected_channels = ['macos', 'windows']
            final = control.overview(self.args, api)
            self.assertEqual('complete', final['publication'])
            self.assertEqual(5, readback.call_count)  # Every result rechecks Mac; no stored green.

    def test_missing_conflicting_or_unreachable_evidence_cannot_complete(self):
        self.operation('macos')
        self.operation('windows', source='c' * 40)
        def status(args, _api):
            control.read_operation(args)
            if args.channel == 'macos':
                return {'runs': [dict(id=42, status='success', outcome='completed')], 'build_metadata': 'success'}
            raise AssertionError('conflicting source should fail before remote reads')
        with patch.object(control, 'status', side_effect=status), \
             patch.object(control, 'overview_readback', return_value={'assets': 'verified', 'public': 'unknown', 'blocker': 'live unavailable'}):
            result = control.overview(self.args, object())
        self.assertEqual('unverified', result['publication'])
        self.assertEqual('assets_published', result['channels']['macos']['state'])
        self.assertEqual('unknown', result['channels']['windows']['state'])
        self.assertEqual('unknown', result['channels']['linux-rpm']['state'])
        self.assertEqual('verified', result['channels']['macos']['assets'])
        with patch.object(control, 'status', side_effect=OSError('API unavailable')):
            result = control.overview(self.args, object())
        self.assertEqual('unverified', result['publication'])
        self.assertEqual('unknown', result['channels']['macos']['state'])

    def readback_args(self, channel='macos'):
        stage = self.args.state_dir / self.args.tag / (channel + '-candidate')
        evidence = stage / 'evidence'
        evidence.mkdir(parents=True)
        files = {name.format(v='1.2.3'): 'c' * 64 for name in control.release_channel.CHANNELS[channel]}
        (evidence / ('channel-manifest-' + channel + '.json')).write_text(json.dumps(dict(
            tag=self.args.tag, channel=channel, source=self.args.sha, controller_sha='b' * 40, files=files)))
        args = SimpleNamespace(**vars(self.args), channel=channel, controller_sha='b' * 40,
            operation_id=channel + '-operation', dist=stage / 'dist', evidence=evidence,
            run_id='42', release_id='auto', create_release=False, status=False)
        if channel != 'web':
            import release_channel_surfaces as surfaces
            _, receipt = surfaces.phase_paths(args, 'website')
            receipt.write_text(json.dumps(dict(tag=self.args.tag, channel=channel,
                pages=dict.fromkeys(surfaces.LANGUAGES, 'd' * 64))))
        return args

    def test_readback_reuses_verify_only_assets_and_exact_live_rows_and_cask(self):
        import release_channel_surfaces as surfaces
        args = self.readback_args()
        url = 'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/v1.2.3/ocideck-macos-1.2.3.zip'
        page = '<ul><li data-ocideck-download=macos><a class=product-action-primary data-ocideck-download-primary href="' + url + '">Download</a></li></ul>'
        urls = []
        original = surfaces.verify_pages
        def verify(proof, expected):
            original(proof, expected, lambda url: urls.append(url) or page.encode())
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run, \
             patch.object(surfaces, 'verify_pages', side_effect=verify), \
             patch.object(surfaces, 'public', side_effect=AssertionError('must never publish')):
            result = control.overview_readback(args)
        self.assertEqual({'assets': 'verified', 'public': 'verified'}, result)
        self.assertEqual(9, len(urls))
        self.assertIn('--verify-only', run.call_args_list[0].args[0])
        self.assertNotIn('--create-release', run.call_args_list[0].args[0])
        cask = run.call_args_list[1].args[0]
        self.assertEqual(url, cask[cask.index('--expected-url') + 1])
        self.assertEqual('c' * 64, cask[cask.index('--expected-sha256') + 1])
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=1)), \
             patch.object(surfaces, 'verify_pages') as verify:
            with self.assertRaisesRegex(ValueError, 'asset readback'):
                control.overview_readback(args)
        verify.assert_not_called()
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=0)), \
             patch.object(surfaces, 'verify_pages', side_effect=ValueError('live page differs')):
            self.assertEqual('unknown', control.overview_readback(args)['public'])

    def test_web_readback_checks_every_manifest_file_without_deploy(self):
        import release_channel_surfaces as surfaces
        args = self.readback_args('web')
        import hashlib
        def extract(_archive, bundle, version):
            self.assertEqual('1.2.3', version)
            bundle.mkdir()
            for name, data in (('index.html', b'web'), ('main.js', b'app')):
                (bundle / name).write_bytes(data)
            (bundle / 'SHA256SUMS').write_text(''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n'
                for name, data in (('index.html', b'web'), ('main.js', b'app'))))
        urls = []
        original = surfaces.verify_web
        def verify(bundle):
            original(bundle, lambda url: urls.append(url) or (bundle / url.rsplit('/', 1)[1]).read_bytes())
        with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run, \
             patch.object(surfaces, 'extract_web', side_effect=extract), \
             patch.object(surfaces, 'verify_web', side_effect=verify), \
             patch.object(surfaces, 'public', side_effect=AssertionError('must never deploy')):
            result = control.overview_readback(args)
        self.assertEqual('verified', result['public'])
        self.assertEqual(1, run.call_count)
        self.assertEqual({'SHA256SUMS', 'index.html', 'main.js'}, {url.rsplit('/', 1)[1] for url in urls})

    def test_expected_scope_must_be_explicit_unique_and_known(self):
        for scope in ([], ['macos', 'macos'], ['other']):
            self.args.expected_channels = scope
            with self.subTest(scope=scope), self.assertRaises(ValueError):
                control.overview(self.args, object())

    def test_cli_overview_needs_no_single_channel_or_operation(self):
        argv = ['release_channel_controller.py', 'overview', '--state-dir', str(self.args.state_dir),
                '--tag', self.args.tag, '--sha', self.args.sha, '--expected-channels', 'macos', 'windows']
        with patch.object(sys, 'argv', argv), patch.object(control, 'Forgejo'), \
             patch.object(control, 'overview', return_value={'publication': 'partial'}) as overview, \
             contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(0, control.main())
        self.assertEqual(['macos', 'windows'], overview.call_args.args[0].expected_channels)
        self.assertEqual({'publication': 'partial'}, json.loads(output.getvalue()))


if __name__ == '__main__':
    unittest.main()
