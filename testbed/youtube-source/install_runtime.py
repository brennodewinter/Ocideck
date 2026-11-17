"""Explicit operator setup in a fresh private directory; never called by HTTP.

Installs only hash-pinned local wheels and the verified official Node archive.
Python is supplied by the operator. The optional existing decoder stays in its
original application bundle, alongside its complete source and notices.
"""
import argparse
import hashlib
import importlib.metadata
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

from register_decoder import inspect


ROOT = pathlib.Path(__file__).resolve().parent
MANIFEST = json.loads((ROOT / 'runtime_manifest.json').read_text())


def digest(path):
    with pathlib.Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def fetch(url, target, expected, *, size=None, cache=None):
    candidate = cache / target.name if cache else None
    if candidate and candidate.is_file():
        shutil.copyfile(candidate, target)
    else:
        if not url.startswith('https://'):
            raise ValueError('Pinned HTTPS source required')
        with urllib.request.urlopen(url, timeout=30) as response, target.open('xb') as output:
            count = 0
            while chunk := response.read(65536):
                count += len(chunk)
                if count > (size if size is not None else 64 * 1024 * 1024):
                    raise ValueError('Component exceeds pinned download limit')
                output.write(chunk)
    if (size is not None and target.stat().st_size != size) or digest(target) != expected:
        raise ValueError('Component size or hash differs')


def install(target, *, cache=None, decoder=None, decoder_notices=None):
    if (sys.platform != 'darwin' or platform.machine() != 'arm64' or
            platform.python_version() != MANIFEST['python_version']):
        raise ValueError('This measured operator setup requires macOS ARM64 and Python 3.15.2')
    if bool(decoder) != bool(decoder_notices):
        raise ValueError('Decoder executable and complete notices must be supplied together')
    # mkdir without exist_ok is the write boundary: never alter an existing install.
    target.mkdir(mode=0o700)
    try:
        sources = target / 'sources'
        sources.mkdir(mode=0o700)
        requirements = []
        for package in MANIFEST['packages']:
            fetch(package['url'], sources / package['filename'], package['sha256'],
                  size=package['size'], cache=cache)
            requirements.append(f"{package['name']}=={package['version']} --hash=sha256:{package['sha256']}")
        node = MANIFEST['node']
        archive = sources / node['source'].rsplit('/', 1)[-1]
        fetch(node['source'], archive, node['archive_sha256'], cache=cache)
        node_dir = target / 'node-runtime'
        node_dir.mkdir(mode=0o700)
        prefix = 'node-' + node['version'] + '-darwin-arm64/'
        with tarfile.open(archive, 'r:xz') as tar:
            for member_name, output_name in [('bin/node', 'node'), ('LICENSE', 'LICENSE'), ('README.md', 'README.md')]:
                member = tar.getmember(prefix + member_name)
                if not member.isfile() or member.size > 128 * 1024 * 1024:
                    raise ValueError('Unexpected Node archive entry')
                path = node_dir / output_name
                path.write_bytes(tar.extractfile(member).read())
                if digest(path) != node['files'][output_name]:
                    raise ValueError('Node executable or complete notice differs')
        (node_dir / 'node').chmod(0o755)
        environment = {'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8'}
        subprocess.run([sys.executable, '-m', 'venv', str(target / 'venv')],
                       check=True, timeout=120, env=environment)
        requirements_file = target / 'requirements.txt'
        requirements_file.write_text('\n'.join(requirements) + '\n')
        interpreter = target / 'venv/bin/python'
        subprocess.run([str(interpreter), '-m', 'pip', '--isolated', 'install',
                        '--no-index', '--no-cache-dir', '--no-deps', '--require-hashes',
                        '--find-links', str(sources), '-r', str(requirements_file)],
                       check=True, timeout=120, env=environment)
        shutil.copytree(ROOT / 'licenses', target / 'licenses')
        if decoder:
            (target / 'decoder-registration.json').write_text(json.dumps(
                inspect(decoder, decoder_notices), indent=2) + '\n')
        report = {'schema': 1, 'python': platform.python_version(),
                  'python_executable': sys.executable, 'python_executable_sha256': digest(sys.executable),
                  'manifest_sha256': digest(ROOT / 'runtime_manifest.json'),
                  'node_executable_sha256': digest(node_dir / 'node'),
                  'source_files': {f.name: digest(f) for f in ROOT.glob('*.py')},
                  'optional_decoder': bool(decoder)}
        (target / 'install-report.json').write_text(json.dumps(report, indent=2) + '\n')
        return report
    except BaseException:
        shutil.rmtree(target)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=pathlib.Path)
    parser.add_argument('--downloads', type=pathlib.Path, help='Optional existing verified download cache')
    parser.add_argument('--decoder', type=pathlib.Path)
    parser.add_argument('--decoder-notices', type=pathlib.Path)
    args = parser.parse_args()
    install(args.destination.absolute(), cache=args.downloads,
            decoder=args.decoder, decoder_notices=args.decoder_notices)
