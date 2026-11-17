"""Register an explicitly selected, existing OciDeck macOS audio decoder.

No installation or binary redistribution. The operator retains the matching
complete source, LGPL text, recipe and replacement instructions shipped with
the standalone FFmpeg component. An app signature changes its executable hash;
record this concrete post-signing binary rather than an assumed universal hash.
"""
import argparse
import hashlib
import json
import pathlib
import shlex
import subprocess


REPOSITORY = pathlib.Path(__file__).resolve().parents[2]
EXPECTED = json.loads((REPOSITORY / 'native/media_decoder/manifest.json').read_text())
NOTICE_NAMES = ['README.md', 'binary.sha256', 'build_media_decoder.sh',
                'compiler.txt', 'ffmpeg-9.0.2.tar.xz', 'ffmpeg-LGPL-2.1.txt',
                'license.txt', 'manifest.json', 'version.txt']


def digest(path):
    with pathlib.Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def inspect(binary, notices):
    binary = pathlib.Path(binary).resolve(strict=True)
    notices = pathlib.Path(notices).resolve(strict=True)
    if json.loads((notices / 'manifest.json').read_text()) != EXPECTED:
        raise ValueError('Decoder component manifest differs')
    if digest(notices / 'ffmpeg-9.0.2.tar.xz') != EXPECTED['tarballSha256']:
        raise ValueError('Matching complete FFmpeg source is required')
    if digest(notices / 'ffmpeg-LGPL-2.1.txt') != digest(REPOSITORY / 'assets/licenses/ffmpeg-LGPL-2.1.txt'):
        raise ValueError('Complete matching LGPL notice is required')
    version = subprocess.run([str(binary), '-version'], capture_output=True,
                             check=True, timeout=5).stdout.decode()
    if not version.startswith('ffmpeg version 9.0.2 '):
        raise ValueError('Decoder version differs')
    configuration = next(line.removeprefix('configuration: ') for line in version.splitlines()
                         if line.startswith('configuration: '))
    flags = set(shlex.split(configuration))
    expected_flags = set(EXPECTED['configureFlags'])
    if not expected_flags.issubset(flags):
        raise ValueError('Decoder build flags differ')
    allowed = {'--cc=/usr/bin/clang', '--ld=/usr/bin/clang',
               '--extra-cflags=-mmacosx-version-min=12.0',
               '--extra-ldflags=-mmacosx-version-min=12.0'}
    if any(flag not in allowed and not flag.startswith('--prefix=')
           for flag in flags - expected_flags):
        raise ValueError('Unexpected decoder build option')
    arch = subprocess.run(['/usr/bin/lipo', '-archs', str(binary)],
                          capture_output=True, check=True, timeout=5).stdout.decode().strip()
    if arch != 'arm64':
        raise ValueError('Only the measured native ARM64 operator runtime is supported')
    links = subprocess.run(['/usr/bin/otool', '-L', str(binary)],
                           capture_output=True, check=True, timeout=5).stdout.decode()
    for line in links.splitlines()[1:]:
        library = line.strip().split(' ', 1)[0]
        if not library.startswith(('/usr/lib/', '/System/Library/')):
            raise ValueError('Unexpected non-system decoder library')
    return {'schema': 1, 'host': 'macos-arm64', 'binary': str(binary),
            'binary_sha256': digest(binary), 'notices': str(notices),
            'notice_sha256': {name: digest(notices / name) for name in NOTICE_NAMES},
            'version_output': version, 'system_links': links,
            'source_sha256': EXPECTED['tarballSha256']}


def verify_registration(path):
    record = json.loads(pathlib.Path(path).read_text())
    if (record.get('schema') != 1 or record.get('host') != 'macos-arm64' or
            record.get('source_sha256') != EXPECTED['tarballSha256']):
        raise ValueError('Decoder registration differs')
    binary = pathlib.Path(record['binary'])
    notices = pathlib.Path(record['notices'])
    if digest(binary) != record['binary_sha256']:
        raise ValueError('Decoder executable changed')
    if set(record['notice_sha256']) != set(NOTICE_NAMES):
        raise ValueError('Decoder notices are incomplete')
    for name in NOTICE_NAMES:
        if digest(notices / name) != record['notice_sha256'][name]:
            raise ValueError('Decoder notice or source changed')
    return binary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=pathlib.Path)
    parser.add_argument('--notices', required=True, type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    record = inspect(args.binary, args.notices)
    with args.output.open('x') as output:
        json.dump(record, output, indent=2)
        output.write('\n')
