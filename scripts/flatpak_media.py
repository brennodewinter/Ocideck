#!/usr/bin/env python3
"""Bundle libmpv's libraries absent from the GNOME runtime, with provenance."""
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys


def output(*args):
    return subprocess.check_output(args, text=True)


def bundle(root, runtime, library):
    root, runtime, library = Path(root), Path(runtime), Path(library).resolve()
    if not runtime.is_dir() or not library.is_file():
        raise ValueError('GNOME runtime and system libmpv must be available')
    available = {p.name for p in runtime.rglob('*.so*')}
    available.update(p.name for p in (root / 'lib/ocideck/lib').glob('*.so*'))
    dependencies = output('ldd', str(library))
    if 'not found' in dependencies:
        raise ValueError('libmpv has unresolved dependencies:\n' + dependencies)
    libraries = {'libmpv.so.2': library}
    for name, path in re.findall(r'^\s*(\S+) => (/\S+)', dependencies, re.M):
        if name not in available:
            libraries[name] = Path(path).resolve()
    # libpulse-simple is a direct helper dependency but need not be linked by
    # libmpv. Resolve the installed helper too instead of relying on the host.
    helper = root / 'lib/ocideck/ocideck-audio'
    if not helper.is_file():
        raise ValueError('Installed native audio helper is missing')
    linked = output('ldd', str(helper))
    if 'not found' in linked:
        raise ValueError('Native audio helper has unresolved dependencies')
    for soname, path in re.findall(r'^\s*(\S+) => (/\S+)', linked, re.M):
        if soname not in available:
            libraries[soname] = Path(path).resolve()
    # The native audio helper needs a real codec set even when the GNOME
    # runtime omits patent-encumbered decoders. Bundle only named local-file
    # plugins and their non-runtime dependencies, with the same provenance.
    plugin_dir = Path(output('pkg-config', '--variable=pluginsdir', 'gstreamer-1.0').strip())
    plugin_names = [
        'libgstlibav.so', 'libgstisomp4.so', 'libgstaudioparsers.so',
        'libgstwavparse.so', 'libgstwavenc.so', 'libgstplayback.so',
        'libgstaudioconvert.so', 'libgstaudioresample.so', 'libgstcoreelements.so',
    ]
    for name in plugin_names:
        plugin = plugin_dir / name
        if not plugin.is_file():
            raise ValueError(f'Missing native audio decoder plugin: {plugin}')
        libraries['gstreamer-1.0/' + name] = plugin.resolve()
        linked = output('ldd', str(plugin))
        if 'not found' in linked:
            raise ValueError(f'Unresolved audio decoder plugin: {plugin}')
        for soname, path in re.findall(r'^\s*(\S+) => (/\S+)', linked, re.M):
            if soname not in available:
                libraries[soname] = Path(path).resolve()
    notices = root / 'share/doc/ocideck-flatpak'
    packages_path = notices / 'PACKAGES.tsv'
    packages = set(packages_path.read_text().splitlines())
    hashes = []
    for name, source in sorted(libraries.items()):
        # Fail closed if a system binary lacks a package/version/licence record.
        owner = output('dpkg-query', '-S', str(source)).split(': ', 1)[0]
        package = owner.split(':', 1)[0]
        copyright_file = Path('/usr/share/doc') / package / 'copyright'
        if not copyright_file.is_file():
            raise ValueError(f'Missing licence for {source}: {package}')
        packages.add(output('dpkg-query', '-W',
                            '-f=${binary:Package}\t${Version}\t${Architecture}',
                            owner).strip())
        copyright_target = notices / 'licenses' / f'{package}.copyright'
        shutil.copyfile(copyright_file, copyright_target)
        hashes.append(f'{hashlib.sha256(copyright_target.read_bytes()).hexdigest()}  '
                      f'{copyright_target.relative_to(root)}\n')
        destination = root / 'lib/ocideck/lib' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        hashes.append(f'{digest}  {destination.relative_to(root)}\n')
    packages_path.write_text('\n'.join(sorted(packages)) + '\n')
    with (notices / 'FILES.sha256').open('a') as stream:
        stream.writelines(hashes)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit('usage: flatpak_media.py FILES_ROOT GNOME_RUNTIME_FILES LIBMPV')
    bundle(*sys.argv[1:])
