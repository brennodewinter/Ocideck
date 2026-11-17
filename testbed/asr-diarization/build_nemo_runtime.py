"""Explicit native macOS arm64 reference-library build; not app packaging.

Creates fresh operator-owned directories. No global installs or model downloads.
Requires native Xcode clang, CMake>=3.26, Ninja and Git on PATH.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess

RUNTIME_REPOSITORY = 'https://github.com/NVIDIA/NeMo-Speech.cpp.git'
RUNTIME_REVISION = 'e790e463b2913cff9f989a3df224c587f14b4c5c'


def run(*arguments, cwd=None, env=None):
    subprocess.run(list(arguments), cwd=cwd, env=env, check=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--prefix', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('Only the native macOS arm64 reference build has been verified')
    work, prefix = args.work_dir.resolve(), args.prefix.resolve()
    if work.exists() or prefix.exists():
        parser.error('Use fresh work and installation directories; existing contents are preserved')
    if work == prefix:
        parser.error('Use separate work and installation directories')
    work.mkdir(parents=True)
    source = work / 'source'
    run('git', 'init', str(source))
    run('git', '-C', str(source), 'remote', 'add', 'origin', RUNTIME_REPOSITORY)
    run('git', '-C', str(source), 'fetch', '--depth', '1', 'origin', RUNTIME_REVISION)
    run('git', '-C', str(source), 'checkout', '--detach', 'FETCH_HEAD')
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != RUNTIME_REVISION:
        raise ValueError('Unexpected runtime revision')
    run('git', '-C', str(source), 'submodule', 'update', '--init', '--depth', '1', 'llama.cpp')
    environment = os.environ.copy()
    environment['JOBS'] = '2'
    run('bash', 'scripts/build_sentencepiece_static.sh', cwd=source, env=environment)
    flags = ['-DNEMO_SPEECH_BUILD_CLI=OFF', '-DNEMO_SPEECH_BUILD_MIC_CAPTURE=OFF',
             '-DBUILD_SHARED_LIBS=OFF', '-DGGML_OPENMP=OFF',
             '-DCMAKE_C_COMPILER=/usr/bin/clang', '-DCMAKE_CXX_COMPILER=/usr/bin/clang++']
    run('bash', 'scripts/configure.sh', 'metal-diar', *flags, cwd=source)
    run('cmake', '--build', '--preset', 'metal-diar', '-j', '2', cwd=source)
    build = source / 'build/metal-diar'
    run('cmake', '--install', str(build), '--prefix', str(prefix))
    files = []
    for relative in ['lib/libnemo_speech_asr_c.2.dylib', 'lib/libnemo_speech_asr.dylib']:
        path = prefix / relative
        architectures = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
        if architectures != ['arm64']:
            raise ValueError('Runtime library is not native arm64')
        dependencies = subprocess.check_output(['otool', '-L', str(path)], text=True)
        if any(line.startswith('\t') and not line.strip().startswith(
                ('@rpath/libnemo_speech_asr', '/System/Library/', '/usr/lib/'))
               for line in dependencies.splitlines()):
            raise ValueError('Unexpected non-system library dependency; inspect installation')
        files.append({'file': relative, 'bytes': path.stat().st_size,
                      'sha256': digest(path), 'architectures': architectures,
                      'linked_libraries': dependencies.splitlines()[1:]})
    manifest = {'schema': 1, 'purpose': 'explicit operator reference server; not OciDeck release packaging',
                'repository': RUNTIME_REPOSITORY, 'revision': RUNTIME_REVISION,
                'version': re.search(r'NEMO_SPEECH_VERSION:\s*(\S+)',
                                     (source / 'VERSION').read_text()).group(1),
                'toolchain': {'clang': subprocess.check_output(
                    ['/usr/bin/clang', '--version'], text=True).splitlines()[0],
                    'macos_sdk': subprocess.check_output(
                        ['xcrun', '--show-sdk-version'], text=True).strip(),
                    'cmake': subprocess.check_output(
                        ['cmake', '--version'], text=True).splitlines()[0],
                    'ninja': subprocess.check_output(['ninja', '--version'], text=True).strip()},
                'platform': 'macos-arm64', 'preset': 'metal-diar', 'cmake_flags': flags,
                'source_patches': 'Pinned upstream patches/ applied by its configure step',
                'submodules': subprocess.check_output(
                    ['git', '-C', str(source), 'submodule', 'status'], text=True).splitlines(),
                'library': 'lib/libnemo_speech_asr_c.2.dylib', 'files': files,
                'notice_root': 'share/licenses/nemo-speech'}
    notices = prefix / manifest['notice_root']
    manifest['notice_sha256'] = {str(p.relative_to(prefix)): digest(p)
                                 for p in sorted(notices.rglob('*')) if p.is_file()}
    if not manifest['notice_sha256']:
        raise ValueError('Runtime licence notices were not installed')
    (prefix / 'ocideck-runtime.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Verified reference runtime manifest:', prefix / 'ocideck-runtime.json')


if __name__ == '__main__':
    main()
