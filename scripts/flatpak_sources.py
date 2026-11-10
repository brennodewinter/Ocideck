#!/usr/bin/env python3
"""Stage matching Debian source packages for every copied Flatpak package.

Input: trusted apt-get source --download-only output (.dsc plus every referenced
archive). Checks correspondence and completeness of that envelope; does not
approve a licence combination or authenticate a caller-supplied repository.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile



def fields(text):
    result = {}
    key = None
    for line in text.splitlines():
        if line.startswith((' ', '\t')) and key:
            result[key] += '\n' + line.strip()
        elif ':' in line:
            key, value = line.split(':', 1)
            result[key] = value.strip()
        else:
            key = None
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage(root, source_dir, records, common_dir=Path('/usr/share/common-licenses')):
    root, source_dir = Path(root), Path(source_dir)
    if not source_dir.is_dir():
        raise ValueError('Matching source packages are required from authenticated '
                         'apt-get source --download-only output')
    descriptors = {}
    for path in source_dir.glob('*.dsc'):
        if path.is_symlink():
            raise ValueError(f'Symlink source descriptor: {path}')
        data = fields(path.read_text())
        key = (data.get('Source'), data.get('Version'))
        if key in descriptors:
            raise ValueError(f'Duplicate source package: {key}')
        descriptors[key] = (path, data)
    verified = {}
    # Verify everything before copying any source files.
    for record in records:
        key = (record['source'], record['source_version'])
        if key in verified:
            continue
        if key not in descriptors:
            raise ValueError(f'Missing matching source package: {key[0]}={key[1]}')
        descriptor, data = descriptors[key]
        entries = [line for line in data.get('Checksums-Sha256', '').splitlines() if line.strip()]
        if not entries:
            raise ValueError(f'Missing source archive checksums: {descriptor.name}')
        files = [descriptor]
        for entry in entries:
            checksum, size, name = entry.split()
            path = source_dir / name
            if Path(name).name != name or name in ('.', '..') or path.is_symlink():
                raise ValueError(f'Unsafe source archive path: {name}')
            if not path.is_file() or path.stat().st_size != int(size) or digest(path) != checksum:
                raise ValueError(f'Missing or changed source archive: {name}')
            files.append(path)
        verified[key] = files
    notices = root / 'share/doc/ocideck-flatpak'
    destination = notices / 'sources'
    destination.mkdir(parents=True, exist_ok=True)
    hashes = []
    source_rows = []
    for (name, version), files in sorted(verified.items()):
        row = {'name': name, 'version': version, 'files': []}
        for source in files:
            target = destination / source.name
            if target.exists() and digest(target) != digest(source):
                raise ValueError(f'Conflicting source archive: {target.name}')
            shutil.copyfile(source, target)
            relative = str(target.relative_to(root))
            checksum = digest(target)
            hashes.append(f'{checksum}  {relative}\n')
            row['files'].append({'path': relative, 'sha256': checksum})
        source_rows.append(row)
    # Debian copyright files often refer to these texts instead of embedding them.
    for name in ['GPL-2', 'GPL-3', 'LGPL-2', 'LGPL-2.1', 'LGPL-3']:
        source = Path(common_dir) / name
        if not source.is_file():
            raise ValueError(f'Missing full GNU licence text: {source}')
        target = notices / 'licenses' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        hashes.append(f'{digest(target)}  {target.relative_to(root)}\n')
    manifest = notices / 'SOURCES.json'
    manifest.write_text(json.dumps({'binary_packages': records, 'sources': source_rows},
                                   indent=2, sort_keys=True) + '\n')
    hashes.append(f'{digest(manifest)}  {manifest.relative_to(root)}\n')
    for path in sorted((notices / 'licenses').iterdir()):
        if path.is_file():
            hashes.append(f'{digest(path)}  {path.relative_to(root)}\n')
    with (notices / 'FILES.sha256').open('a') as stream:
        stream.writelines(hashes)


def installed_sources(packages_path):
    records = []
    for line in Path(packages_path).read_text().splitlines():
        binary, version, arch = line.split('\t')
        facts = subprocess.check_output([
            'dpkg-query', '-W', '-f=${Version}\t${source:Package}\t${source:Version}', binary,
        ], text=True).split('\t')
        if facts[0] != version:
            raise ValueError(f'Installed package changed: {binary}')
        # dpkg --verify reports mismatches on stdout, even with exit status 0.
        verification = subprocess.check_output(['dpkg', '--verify', binary], text=True)
        # Minimal Ubuntu images intentionally omit manuals/locales via
        # dpkg path-exclude. Missing files cannot have been copied above;
        # changed files that do exist are never accepted.
        if any(not line.startswith('missing ') for line in verification.splitlines()):
            raise ValueError(f'Locally modified distro package: {binary}')
        records.append(dict(binary=binary, version=version, architecture=arch,
                            source=facts[1], source_version=facts[2]))
    return records


if __name__ == '__main__':
    from apt_source_download import download
    if len(sys.argv) != 2:
        sys.exit('usage: flatpak_sources.py FILES_ROOT')
    root = Path(sys.argv[1])
    records = installed_sources(root / 'share/doc/ocideck-flatpak/PACKAGES.tsv')
    # Always acquire through signed Sources indexes in an empty directory.
    # Arbitrary pre-existing .dsc files must not bypass APT authentication.
    with tempfile.TemporaryDirectory(prefix='ocideck-native-source-') as temporary:
        download(records, temporary)
        stage(root, temporary, records)
        origin = root / 'share/doc/ocideck-flatpak/APT-ORIGIN.json'
        shutil.copyfile(Path(temporary) / 'APT-ORIGIN.json', origin)
        with (origin.parent / 'FILES.sha256').open('a') as stream:
            stream.write(f'{digest(origin)}  {origin.relative_to(root)}\n')
        inventory = origin.parent / 'FILES.sha256'
        inventory.write_text(''.join(sorted(set(inventory.read_text().splitlines(keepends=True)))))
