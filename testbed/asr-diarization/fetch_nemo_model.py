"""Explicit download of one ungated pinned model plus its notices. No app call."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        while block := source.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def fetch(url, path, size, checksum):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.stat().st_size != size or digest(path) != checksum:
            raise ValueError('Existing file differs; inspect it before retrying')
        return
    if shutil.disk_usage(path.parent).free < size + 100 * 1024 * 1024:
        raise ValueError('Insufficient free space')
    temporary = None
    try:
        value, count = hashlib.sha256(), 0
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            with urllib.request.urlopen(url, timeout=60) as source:
                while block := source.read(1024 * 1024):
                    count += len(block)
                    if count > size:
                        raise ValueError('Unexpected download size')
                    output.write(block)
                    value.update(block)
        if count != size or value.hexdigest() != checksum:
            raise ValueError('Model or notice checksum mismatch')
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cache-dir', type=Path, required=True)
    args = parser.parse_args()
    source = Path(__file__).parent
    model = json.loads((source / 'nemo_model.json').read_text())
    root = args.cache_dir
    base = 'https://huggingface.co/' + model['repository'] + '/resolve/' + model['revision'] + '/'
    fetch(base + model['file'], root / model['file'], model['bytes'], model['sha256'])
    for notice in model['notices']:
        fetch(base + notice['file'], root / 'notices' / notice['file'], notice['bytes'], notice['sha256'])
    license_text = (source / model['license_file']).read_bytes()
    if hashlib.sha256(license_text).hexdigest() != model['license_sha256']:
        raise ValueError('Local license notice changed')
    destination = root / 'notices/OpenMDW-1.1.txt'
    if destination.exists() and destination.read_bytes() != license_text:
        raise ValueError('Existing license notice differs; inspect it before retrying')
    destination.write_bytes(license_text)
    print('Pinned model and original notices verified; no model account or token used')


if __name__ == '__main__':
    main()
