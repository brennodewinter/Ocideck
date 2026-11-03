#!/usr/bin/env python3
"""Create and verify local release-channel byte manifests; does not publish."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

CHANNELS = {
    'macos': ['ocideck-macos-{v}.zip'],
    'windows': ['ocideck-windows-x64-{v}.zip', 'ocideck-windows-x64-setup-{v}.exe'],
    'web': ['ocideck-web-{v}.tar.gz'],
    'linux-tar': ['ocideck-linux-x64-{v}.tar.gz'],
    'linux-debian12': ['ocideck-linux-debian12-x86_64-{v}.tar.gz'],
    'linux-deb': ['ocideck-linux-amd64-{v}.deb'],
    'linux-rpm': ['ocideck-linux-x86_64-{v}.rpm'],
    'linux-appimage': ['ocideck-linux-x86_64-{v}.AppImage'],
    'linux-flatpak': ['ocideck-linux-x86_64-{v}.flatpak', 'ocideck-linux-x86_64-{v}.flatpak.cdx.json'],
}


def identity(tag, sha, channel):
    if not re.fullmatch(r'v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', tag):
        raise ValueError('tag must be vMAJOR.MINOR.PATCH')
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or sha == '0' * 40:
        raise ValueError('source must be a nonzero full lowercase commit SHA')
    if channel not in CHANNELS:
        raise ValueError('unknown channel')
    return tag[1:]


def file_hash(path):
    # O_NOFOLLOW also rejects replacement with a symlink between listing and open.
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
            raise ValueError('asset must be a nonempty regular file: ' + path.name)
        hasher = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
        digest = hasher.hexdigest()
    return digest


def assets(dist, version, channel):
    if dist.is_symlink() or not dist.is_dir():
        raise ValueError('dist must be a real directory')
    owned = {name.format(v=version) for name in CHANNELS[channel]}
    shared = {f'ocideck-{version}.cdx.json', f'ocideck-{version}.spdx.json'}
    allowed = {name.format(v=version) for names in CHANNELS.values() for name in names} | shared
    entries = {p.name: p for p in dist.iterdir()}
    # A shared dist may contain other channels, but never unknown assets or links.
    for name, path in entries.items():
        if name == 'SHA256SUMS' or name in {f'SHA256SUMS.{c}' for c in CHANNELS} or name in {f'channel-manifest-{c}.json' for c in CHANNELS}:
            if path.is_symlink() or not path.is_file():
                raise ValueError('invalid evidence file: ' + name)
            continue
        if name not in allowed or path.is_symlink() or not path.is_file():
            raise ValueError('unexpected asset: ' + name)
    missing = owned - entries.keys()
    if missing:
        raise ValueError('missing assets: ' + ', '.join(sorted(missing)))
    return {name: file_hash(entries[name]) for name in sorted(owned | (shared & entries.keys()))}


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key: ' + key)
        result[key] = value
    return result


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def immutable_write(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.manifest-', delete=False) as stream:
        pending = Path(stream.name)
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    try:
        try:
            os.link(pending, path)
        except FileExistsError:
            if path.is_symlink() or not path.is_file() or path.read_bytes() != content:
                raise ValueError('refusing to replace existing evidence: ' + str(path))
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        pending.unlink()


def create(args):
    version = identity(args.tag, args.sha, args.channel)
    identity(args.tag, args.controller_sha, args.channel)
    if not re.fullmatch(r'[1-9][0-9]*', args.run_id):
        raise ValueError('run-id must be a positive integer')
    hashes = assets(args.dist, version, args.channel)
    manifest = {'schema': 1, 'tag': args.tag, 'version': version, 'source': args.sha, 'controller_sha': args.controller_sha, 'channel': args.channel,
                'run_id': args.run_id, 'files': hashes}
    checksum = ''.join(f'{digest}  {name}\n' for name, digest in hashes.items()).encode()
    immutable_write(args.output, encoded(manifest))
    immutable_write(args.output.parent / ('SHA256SUMS.' + args.channel), checksum)
    return manifest


def verify(args):
    version = identity(args.tag, args.sha, args.channel)
    identity(args.tag, args.controller_sha, args.channel)
    if args.manifest.is_symlink() or not args.manifest.is_file():
        raise ValueError('manifest must be a regular file')
    manifest = json.loads(args.manifest.read_text(), object_pairs_hook=no_duplicates)
    if not isinstance(manifest, dict) or set(manifest) != {'schema', 'tag', 'version', 'source', 'controller_sha', 'channel', 'run_id', 'files'}:
        raise ValueError('invalid manifest fields')
    if type(manifest['schema']) is not int or manifest['schema'] != 1 or manifest['version'] != version or manifest['tag'] != args.tag or manifest['source'] != args.sha or manifest['controller_sha'] != args.controller_sha or manifest['channel'] != args.channel:
        raise ValueError('manifest identity mismatch')
    if not isinstance(manifest['run_id'], str) or not re.fullmatch(r'[1-9][0-9]*', manifest['run_id']):
        raise ValueError('invalid run-id')
    if manifest['files'] != assets(args.dist, version, args.channel):
        raise ValueError('manifest files do not match actual channel bytes')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('create', 'verify'):
        sub = commands.add_parser(command)
        for name in ('channel', 'tag', 'sha', 'controller-sha'):
            sub.add_argument('--' + name, required=True)
        sub.add_argument('--dist', required=True, type=Path)
        if command == 'create':
            sub.add_argument('--run-id', required=True)
            sub.add_argument('--output', required=True, type=Path)
        else:
            sub.add_argument('--manifest', required=True, type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(create(args) if args.command == 'create' else verify(args), sort_keys=True))
    except (ValueError, OSError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
