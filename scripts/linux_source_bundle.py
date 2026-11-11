#!/usr/bin/env python3
"""Accompany Linux binaries with their exact project and resolved package source.

Run after the final build/helper step, before any tarball or package is made.
Verification binds every payload file to this snapshot and detects stale kits.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import unquote, urlparse

DOC = Path('share/doc/ocideck')
EXCLUDED = {'.git', '.dart_tool', '.flutter-plugins-dependencies', '.packages',
            'build', 'dist', 'outputs', 'work', '__pycache__', '.DS_Store'}
GNU = ['GPL-2', 'GPL-3', 'LGPL-2', 'LGPL-2.1', 'LGPL-3']


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def native_requirements():
    """Record the actual system media build, without calling it redistributed."""
    cache = subprocess.check_output(['ldconfig', '-p'], text=True)
    libraries = dict(re.findall(r'^\s*(\S+) .* => (/\S+)$', cache, re.M))
    required = ['libmpv.so.2', 'libwebkit2gtk-4.1.so.0',
                'libgstreamer-1.0.so.0', 'libpulse.so.0', 'libpulse-simple.so.0']
    if any(name not in libraries for name in required):
        raise ValueError('Linux media prerequisites are missing')
    dependencies = subprocess.check_output(['ldd', libraries['libmpv.so.2']], text=True)
    if 'not found' in dependencies:
        raise ValueError('Unresolved libmpv runtime dependencies')
    for name, path in re.findall(r'^\s*(lib(?:av(?:codec|device|filter|format|util)|sw(?:resample|scale))\.so\.\S+) => (/\S+)', dependencies, re.M):
        required.append(name)
        libraries[name] = path
    rows = []
    for name in sorted(set(required)):
        path = Path(libraries[name]).resolve()
        candidates = [str(path)]
        if str(path).startswith('/usr/lib/'):
            candidates.append(str(path)[4:])  # Debian's pre-usrmerge database
        owner = None
        for candidate in candidates:
            result = subprocess.run(['dpkg-query', '-S', candidate], text=True,
                                    capture_output=True)
            if result.returncode == 0:
                owner = result.stdout.strip().split(': ', 1)[0]
                break
        if not owner or '\n' in owner:
            raise ValueError(f'No unambiguous distro provenance: {path}')
        version, source_name, source_version = subprocess.check_output([
            'dpkg-query', '-W', '-f=${Version}\t${source:Package}\t${source:Version}', owner,
        ], text=True).split('\t')
        copyright_file = Path('/usr/share/doc') / owner.split(':')[0] / 'copyright'
        rows.append({'soname': name, 'binary_package': owner, 'version': version,
                     'source': source_name, 'source_version': source_version,
                     'binary_sha256': sha(path), 'copyright': copyright_file.read_text(),
                     'delivery': 'external OS prerequisite; not copied into native bundle'})
    return rows


def payload_hashes(bundle):
    return {str(p.relative_to(bundle)): sha(p)
            for p in sorted(Path(bundle).rglob('*'))
            if p.is_file() and DOC not in p.relative_to(bundle).parents}


def copy_source(source, destination, *, flutter_sdk=False, flutter_project=False):
    # Never follow an external symlink into credentials or untracked host data.
    source = Path(source).resolve()
    generated_parents = {source / parent for parent in
                         ('linux/flutter', 'windows/flutter', 'macos/Flutter')} if flutter_project else set()
    def ignore(directory, names):
        ignored = set(names) & EXCLUDED
        if Path(directory) in generated_parents:
            ignored.add('ephemeral')
        # Release SDK archives contain engines for several platforms and the
        # Dart SDK here. They are build prerequisites, not package source.
        if flutter_sdk and Path(directory) == source / 'bin':
            ignored.add('cache')
        for name in names:
            path = Path(directory) / name
            if path.is_symlink() and not path.resolve().is_relative_to(source):
                raise ValueError(f'External source symlink: {path}')
        return ignored
    shutil.copytree(source, destination, ignore=ignore, symlinks=True)
    for path in Path(destination).rglob('*'):
        if path.is_symlink() and path.readlink().is_absolute():
            relative_target = (source / path.relative_to(destination)).resolve().relative_to(source)
            path.unlink()
            path.symlink_to(os.path.relpath(Path(destination) / relative_target, path.parent))


def extract_project(archive, target):
    """Extract git's file/dir/symlink subset on Debian 12's older Python too."""
    target = Path(target).resolve()
    for member in archive:
        name = PurePosixPath(member.name)
        if name.is_absolute() or '..' in name.parts:
            raise ValueError(f'Unsafe project archive path: {member.name}')
        destination = target / member.name
        if not destination.resolve().is_relative_to(target):
            raise ValueError(f'Escaping project archive link: {member.name}')
        destination.parent.mkdir(parents=True, exist_ok=True)
        if member.isdir():
            destination.mkdir(exist_ok=True)
        elif member.issym():
            link = PurePosixPath(member.linkname)
            if link.is_absolute() or not (destination.parent / member.linkname).resolve().is_relative_to(target):
                raise ValueError(f'External project archive symlink: {member.name}')
            destination.symlink_to(member.linkname)
        elif member.isfile():
            with archive.extractfile(member) as reader, destination.open('wb') as writer:
                shutil.copyfileobj(reader, writer)
            destination.chmod(member.mode & 0o777)
        else:
            raise ValueError(f'Unsupported project archive entry: {member.name}')


def snapshot_project(project, target):
    if (project / '.ocideck-source-revision').is_file() and not (project / '.git').exists():
        # Container input is a git-archive exported by the release wrapper.
        revision = (project / '.ocideck-source-revision').read_text().strip()
        copy_source(project, target, flutter_project=True)
    else:
        # Releases must describe their actual source, never dirty HEAD plus a
        # reassuring commit label. Untracked files are intentionally not shipped.
        status = subprocess.check_output(
            ['git', '-C', str(project), 'status', '--porcelain', '--untracked-files=no'], text=True)
        if status.strip():
            raise ValueError('Release source tree has tracked modifications; commit before packaging')
        revision = subprocess.check_output(
            ['git', '-C', str(project), 'rev-parse', 'HEAD'], text=True).strip()
        target.mkdir(parents=True)
        # git archive is trusted local input, but extraction still rejects escapes.
        with tempfile.TemporaryFile() as stream:
            subprocess.run(['git', '-C', str(project), 'archive', 'HEAD'], stdout=stream, check=True)
            stream.seek(0)
            with tarfile.open(fileobj=stream) as archive:
                extract_project(archive, target)
    if len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
        raise ValueError('Invalid source revision')
    return revision


def stage(project, bundle, out, version, common=Path('/usr/share/common-licenses')):
    project, bundle, out = Path(project).resolve(), Path(bundle).resolve(), Path(out).resolve()
    config_file = project / '.dart_tool/package_config.json'
    config = json.loads(config_file.read_text())
    docs = bundle / DOC
    docs.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    for name in GNU:
        shutil.copyfile(common / name, docs / name)
    shutil.copyfile(project / 'LICENSE.md', docs / 'EUPL-1.2.txt')
    for name, path in [('DISTRIBUTION-LICENSES.md', 'packaging/linux/DISTRIBUTION-LICENSES.md'),
                       ('THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_NOTICES.md')]:
        shutil.copyfile(project / path, docs / name)
    # Conventional Debian documentation entry, also used by the RPM doc symlink.
    shutil.copyfile(docs / 'DISTRIBUTION-LICENSES.md', docs / 'copyright')
    shutil.copyfile(project / 'sbom/ocideck.cdx.json', docs / 'components.cdx.json')
    shutil.copyfile(project / 'scripts/linux_source_bundle.py', docs / 'verify_sources.py')
    (docs / 'RUNTIME-REQUIREMENTS.json').write_text(json.dumps(native_requirements(), indent=2) + '\n')
    with tempfile.TemporaryDirectory(prefix='ocideck-source-kit-') as temporary:
        kit = Path(temporary) / 'ocideck-sources'
        kit.mkdir()
        revision = snapshot_project(project, kit / 'project')
        rows = []
        copied_sdk = None
        for package in config['packages']:
            uri = urlparse(package['rootUri'])
            if uri.scheme not in ('', 'file'):
                raise ValueError(f'Non-local resolved package: {package["name"]}')
            source = Path(unquote(uri.path))
            if not source.is_absolute():
                source = (config_file.parent / source).resolve()
            name = package['name']
            if not name.replace('_', '').isalnum():
                raise ValueError(f'Invalid package name: {name}')
            if source.is_relative_to(project):
                destination = 'project/' + str(source.relative_to(project))
            else:
                # Git dependencies may be packages inside a monorepo. Their
                # CMake files and symlinks can use shared sources above the
                # package directory (nativeapi does). Preserve that source tree.
                repository = next((p for p in [source, *source.parents]
                                   if (p / '.git').exists()), source)
                base = f'packages/{name}'
                is_sdk = ((repository / 'bin/flutter').is_file()
                          and (repository / 'packages/flutter/pubspec.yaml').is_file())
                if is_sdk and source.is_relative_to(repository / 'bin/cache'):
                    # sky_engine is generated Dart source inside the SDK cache;
                    # retain that package, without the rest of the binary cache.
                    repository = source
                    copy_source(source, kit / base)
                elif is_sdk:
                    base = 'sdk/flutter'
                    if copied_sdk is None:
                        copy_source(repository, kit / base, flutter_sdk=True)
                        copied_sdk = repository
                    elif copied_sdk != repository:
                        raise ValueError('Multiple Flutter SDK source roots')
                else:
                    copy_source(repository, kit / base)
                destination = str(Path(base) / source.relative_to(repository))
            rows.append({**package, 'rootUri': '../../' + destination})
        rebuilt = kit / 'project/.dart_tool'
        rebuilt.mkdir(exist_ok=True)
        (rebuilt / 'package_config.json').write_text(json.dumps({
            'configVersion': 2, 'packages': rows,
        }, indent=2) + '\n')
        (kit / 'REBUILD.md').write_text(REBUILD)
        (kit / 'REVISION').write_text(revision + '\n')
        files = {str(p.relative_to(kit)): sha(p) for p in sorted(kit.rglob('*')) if p.is_file()}
        (kit / 'SOURCE-FILES.json').write_text(json.dumps(files, indent=2) + '\n')
        archive = out / f'ocideck-linux-sources-{version}.tar.gz'
        with tarfile.open(archive, 'w:gz') as stream:
            stream.add(kit, arcname=kit.name)
        shutil.copyfile(archive, docs / 'sources.tar.gz')
    manifest = {
        'version': version, 'revision': revision, 'own_source_license': 'EUPL-1.2',
        'media_combination_license': 'GPL-3.0-or-later',
        'source_archive': 'sources.tar.gz', 'source_sha256': sha(docs / 'sources.tar.gz'),
        'payload': payload_hashes(bundle),
        'notice_hashes': {p.name: sha(p) for p in sorted(docs.iterdir())
                          if p.is_file() and p.name != 'BUILD-SOURCES.json'},
    }
    (docs / 'BUILD-SOURCES.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    verify(bundle)


def verify(bundle, copied_files=None):
    bundle = Path(bundle)
    docs = bundle / DOC
    manifest = json.loads((docs / 'BUILD-SOURCES.json').read_text())
    if manifest['own_source_license'] != 'EUPL-1.2' or manifest['media_combination_license'] != 'GPL-3.0-or-later':
        raise ValueError('Incorrect Linux distribution licence declaration')
    expected_payload = dict(manifest['payload'])
    if copied_files:
        for line in Path(copied_files).read_text().splitlines():
            digest, name = line.split('  ', 1)
            if not re.fullmatch(r'[a-f0-9]{64}', digest) or '..' in Path(name).parts:
                raise ValueError('Invalid Flatpak copied-file inventory')
            if name.startswith('lib/ocideck/'):
                relative = name.removeprefix('lib/ocideck/')
                if relative in expected_payload and expected_payload[relative] != digest:
                    raise ValueError('Flatpak overwrote original application payload')
                expected_payload[relative] = digest
    if expected_payload != payload_hashes(bundle):
        raise ValueError('Linux binary payload changed after source staging')
    for name, expected in manifest['notice_hashes'].items():
        if Path(name).name != name or sha(docs / name) != expected:
            raise ValueError(f'Linux source/notice changed: {name}')
    if sha(docs / 'sources.tar.gz') != manifest['source_sha256']:
        raise ValueError('Linux corresponding source archive changed')


REBUILD = """# Rebuild and replace OciDeck Linux

Our own code remains EUPL-1.2; see project/LICENSE.md. For the GPL media
combination see project/packaging/linux/DISTRIBUTION-LICENSES.md.

This archive is the actual project snapshot and resolved package sources.
SOURCE-FILES.json records SHA-256 hashes; REVISION identifies the source commit.
Use the standard unmodified Flutter compiler/SDK pinned in project/.tool-versions
(installation and checksum verification: project/docs/DEVELOPMENT_SETUP_GUIDE.md).
Compiler/SDK tools are separately available free software, not our modified code.
The framework packages used by the application are included under packages/.
The rebuilt package_config.json points to these local sources, not a user's cache.

Install the distro build dependencies listed in project/docs/BUILD.md, then:

    cd project
    flutter build linux --release --no-pub
    scripts/bundle_whisper_cli.sh linux

Build hooks/third-party build recipes and pins are included with their packages;
standard build tools may fetch their declared upstream inputs. The native distro
source packages in Flatpak sources/ contain distro patches and debian/rules:

    dpkg-source -x sources/<package>.dsc
    cd <unpacked-source>
    dpkg-buildpackage -us -uc -b

Use apt-get build-dep <source-package> for standard distro build dependencies.
Native libraries supplied by the OS or GNOME runtime are independently supplied
system components. The manifest identifies what OciDeck actually copies.

To run a replacement library with a native bundle:

    LD_LIBRARY_PATH=/absolute/path/to/rebuilt/libs ./build/linux/x64/release/bundle/ocideck

For Flatpak, first copy the source payload to a writable directory, rebuild, and
initialise a local Git repository and commit your modifications (including the
required modification notices). Stage a fresh source kit before packaging:

    git init
    git add .
    git commit -m 'Local rebuild and modifications'
    python3 scripts/linux_source_bundle.py stage "$PWD" build/linux/x64/release/bundle dist <version>
    FORMATS=flatpak scripts/package_linux.sh <version>

Use your local version in place of <version>; build from the extracted project
directory. Install the new .flatpak with
flatpak --user install --bundle. Alternatively use a development-only override:

    flatpak run --filesystem=/absolute/path/to/rebuilt/libs:ro \\
      --env=LD_LIBRARY_PATH=/absolute/path/to/rebuilt/libs:/app/lib/ocideck/lib \\
      com.dewinter.ocideck

No application signature/activation check blocks modified binaries or libraries.
Pass accompanying source and licence notices on when redistributing binaries.
"""


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    build = sub.add_parser('stage')
    for arg in ('project', 'bundle', 'out', 'version'):
        build.add_argument(arg)
    check = sub.add_parser('verify')
    check.add_argument('bundle')
    check.add_argument('--copied-files')
    args = parser.parse_args()
    if args.command == 'verify':
        verify(args.bundle, args.copied_files)
    else:
        stage(args.project, args.bundle, args.out, args.version)
