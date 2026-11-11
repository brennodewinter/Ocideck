import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


source = load('linux_source_bundle')
apt = load('apt_source_download')


class SourceBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.project = root / 'project'
        self.project.mkdir()
        self.bundle = root / 'bundle'
        self.bundle.mkdir()
        (self.bundle / 'ocideck').write_text('fixture executable')
        self.common = root / 'common'
        self.common.mkdir()
        for name in source.GNU:
            (self.common / name).write_text('fixture licence')
        for name in ['LICENSE.md', 'THIRD_PARTY_NOTICES.md',
                     'packaging/linux/DISTRIBUTION-LICENSES.md', 'sbom/ocideck.cdx.json',
                     'scripts/linux_source_bundle.py']:
            path = self.project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}' if name.endswith('.json') else 'fixture notice')
        (self.project / '.gitignore').write_text('.dart_tool/\n')
        (self.project / 'app.dart').write_text('source fixture')
        self.package = root / 'package'
        self.package.mkdir()
        (self.package / 'LICENSE').write_text('fixture package licence')
        (self.package / 'code.dart').write_text('fixture package source')
        (self.project / '.dart_tool').mkdir()
        (self.project / '.dart_tool/package_config.json').write_text(json.dumps({
            'configVersion': 2, 'packages': [
                {'name': 'ocideck', 'rootUri': '../', 'packageUri': 'lib/'},
                {'name': 'sample', 'rootUri': self.package.as_uri(), 'packageUri': 'lib/'},
            ],
        }))
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-qm', 'fixture')

    def git(self, *args):
        subprocess.run(['git', '-C', str(self.project), *args], check=True,
                       stdout=subprocess.DEVNULL)

    def stage(self):
        with patch.object(source, 'native_requirements', return_value=[{'source': 'fixture'}]):
            source.stage(self.project, self.bundle, self.bundle.parent / 'out', '1.0', self.common)

    def test_sources_licences_local_resolution_and_binary_binding(self):
        (self.project / 'untracked-secret').write_text('must not ship')
        self.stage()
        source.verify(self.bundle)
        with tarfile.open(self.bundle / source.DOC / 'sources.tar.gz') as archive:
            names = archive.getnames()
            self.assertIn('ocideck-sources/project/app.dart', names)
            self.assertIn('ocideck-sources/packages/sample/LICENSE', names)
            self.assertNotIn('ocideck-sources/project/untracked-secret', names)
            config = json.load(archive.extractfile('ocideck-sources/project/.dart_tool/package_config.json'))
            self.assertEqual(config['packages'][1]['rootUri'], '../../packages/sample')
        manifest = json.loads((self.bundle / source.DOC / 'BUILD-SOURCES.json').read_text())
        self.assertEqual(manifest['own_source_license'], 'EUPL-1.2')
        self.assertEqual(manifest['media_combination_license'], 'GPL-3.0-or-later')
        (self.bundle / 'ocideck').write_text('new executable')
        with self.assertRaisesRegex(ValueError, 'payload changed'):
            source.verify(self.bundle)

    def test_changed_archive_blocks_packaging(self):
        self.stage()
        (self.bundle / source.DOC / 'sources.tar.gz').write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            source.verify(self.bundle)

    def test_flatpak_additions_require_matching_separate_inventory(self):
        self.stage()
        library = self.bundle / 'lib/libsample.so.1'
        library.parent.mkdir()
        library.write_text('distro binary fixture')
        with self.assertRaisesRegex(ValueError, 'payload changed'):
            source.verify(self.bundle)
        inventory = self.bundle.parent / 'FILES.sha256'
        inventory.write_text(f'{source.sha(library)}  lib/ocideck/lib/libsample.so.1\n')
        source.verify(self.bundle, inventory)
        library.write_text('changed distro binary')
        with self.assertRaisesRegex(ValueError, 'payload changed'):
            source.verify(self.bundle, inventory)

    def test_missing_licence_blocks_packaging(self):
        (self.common / 'GPL-3').unlink()
        with self.assertRaises(FileNotFoundError):
            self.stage()

    def test_dirty_source_does_not_claim_head(self):
        (self.project / 'app.dart').write_text('uncommitted')
        with self.assertRaisesRegex(ValueError, 'tracked modifications'):
            self.stage()

    def test_package_symlink_cannot_leak_host_files(self):
        (self.package / 'outside').symlink_to(self.project / 'app.dart')
        with self.assertRaisesRegex(ValueError, 'External source symlink'):
            self.stage()

    def test_git_monorepo_shared_sources_and_links_are_preserved(self):
        monorepo = self.package.parent / 'monorepo'
        monorepo.mkdir()
        (monorepo / '.git').mkdir()
        (monorepo / 'LICENSE').write_text('shared upstream licence')
        subpackage = monorepo / 'packages/sample'
        subpackage.mkdir(parents=True)
        (subpackage / 'LICENSE').symlink_to('../../LICENSE')
        config = self.project / '.dart_tool/package_config.json'
        data = json.loads(config.read_text())
        data['packages'][1]['rootUri'] = subpackage.as_uri()
        config.write_text(json.dumps(data))
        self.stage()
        with tarfile.open(self.bundle / source.DOC / 'sources.tar.gz') as archive:
            self.assertIn('ocideck-sources/packages/sample/LICENSE', archive.getnames())
            rebuilt = json.load(archive.extractfile('ocideck-sources/project/.dart_tool/package_config.json'))
            self.assertEqual(rebuilt['packages'][1]['rootUri'], '../../packages/sample/packages/sample')

    def test_flutter_sdk_sources_are_shared_without_binary_caches(self):
        sdk = self.package.parent / 'flutter-sdk'
        (sdk / '.git').mkdir(parents=True)
        (sdk / 'bin').mkdir()
        (sdk / 'bin/flutter').write_text('SDK launcher')
        (sdk / 'LICENSE').write_text('shared SDK licence')
        packages = ['flutter', 'flutter_driver', 'flutter_localizations',
                    'flutter_test', 'flutter_web_plugins',
                    'fuchsia_remote_debug_protocol', 'integration_test']
        config = self.project / '.dart_tool/package_config.json'
        data = json.loads(config.read_text())
        for name in packages:
            package = sdk / 'packages' / name
            (package / 'lib').mkdir(parents=True)
            (package / 'pubspec.yaml').write_text(f'name: {name}\n')
            (package / 'lib/source.dart').write_text(f'source for {name}')
            data['packages'].append({'name': name, 'rootUri': package.as_uri(),
                                     'packageUri': 'lib/'})
        cache = sdk / 'bin/cache'
        (cache / 'artifacts/engine/android-arm').mkdir(parents=True)
        (cache / 'artifacts/engine/android-arm/flutter.jar').write_bytes(b'binary cache')
        sky = cache / 'pkg/sky_engine'
        (sky / 'lib').mkdir(parents=True)
        (sky / 'lib/ui.dart').write_text('generated SDK source')
        data['packages'].append({'name': 'sky_engine', 'rootUri': sky.as_uri(),
                                 'packageUri': 'lib/'})
        config.write_text(json.dumps(data))
        self.stage()
        source.verify(self.bundle)
        with tarfile.open(self.bundle / source.DOC / 'sources.tar.gz') as archive:
            names = archive.getnames()
            self.assertFalse(any('/bin/cache/' in name for name in names))
            self.assertEqual(sum(name.endswith('/LICENSE') and '/sdk/' in name
                                 for name in names), 1)
            for name in packages:
                path = f'ocideck-sources/sdk/flutter/packages/{name}/lib/source.dart'
                self.assertEqual(archive.extractfile(path).read().decode(), f'source for {name}')
            self.assertEqual(archive.extractfile(
                'ocideck-sources/packages/sky_engine/lib/ui.dart').read(), b'generated SDK source')
            rebuilt = json.load(archive.extractfile('ocideck-sources/project/.dart_tool/package_config.json'))
            roots = {row['name']: row['rootUri'] for row in rebuilt['packages']}
            for name in packages:
                self.assertEqual(roots[name], f'../../sdk/flutter/packages/{name}')
            self.assertEqual(roots['sky_engine'], '../../packages/sky_engine')


class AptRepositoryTests(unittest.TestCase):
    def test_published_provenance_does_not_leak_repository_credentials(self):
        public = apt.public_repository_config('URIs: https://user:secret@example.invalid/ubuntu?token=secret\n')
        self.assertEqual(public, 'URIs: https://example.invalid/ubuntu\n')

    def test_sources_keep_signature_configuration_and_skip_disabled(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'sources.list.d').mkdir()
            (root / 'sources.list.d/ubuntu.sources').write_text(
                'Types: deb\nURIs: https://example.invalid/ubuntu\nSuites: noble\n'
                'Components: main universe\nSigned-By: /usr/share/keyrings/ubuntu.gpg\n\n'
                'Types: deb\nEnabled: no\nURIs: https://disabled.invalid\n')
            (root / 'sources.list').write_text(
                'deb [signed-by=/keys/vendor.gpg] https://vendor.invalid stable main\n')
            deb822, legacy = apt.source_entries(root)
            self.assertIn('Types: deb-src', deb822)
            self.assertIn('Signed-By: /usr/share/keyrings/ubuntu.gpg', deb822)
            self.assertNotIn('disabled.invalid', deb822)
            self.assertIn('deb-src [signed-by=/keys/vendor.gpg]', legacy)

    def test_untrusted_repository_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'sources.list').write_text('deb [trusted=yes] https://example.invalid stable main\n')
            with self.assertRaisesRegex(ValueError, 'Unauthenticated'):
                apt.source_entries(root)


class ProjectArchiveTests(unittest.TestCase):
    def test_archive_cannot_write_outside_source_tree(self):
        for name, link in [('../escape', None), ('link', '/etc/passwd')]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                data = io.BytesIO()
                with tarfile.open(fileobj=data, mode='w') as writer:
                    info = tarfile.TarInfo(name)
                    if link:
                        info.type = tarfile.SYMTYPE
                        info.linkname = link
                    writer.addfile(info)
                data.seek(0)
                with tarfile.open(fileobj=data) as reader:
                    with self.assertRaises(ValueError):
                        source.extract_project(reader, Path(temp))


if __name__ == '__main__':
    unittest.main()
