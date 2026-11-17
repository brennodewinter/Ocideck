"""Explicit download of one pinned MIT model. The application never invokes this."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request

root = Path(__file__).resolve().parent
catalog = json.loads((root / 'models.json').read_text())['models']
parser = argparse.ArgumentParser()
parser.add_argument('model', choices=[model['name'] for model in catalog])
parser.add_argument('--cache-dir', type=Path, default=root / 'model')
args = parser.parse_args()
model = next(model for model in catalog if model['name'] == args.model)
target = args.cache_dir / model['name']
target.mkdir(parents=True, exist_ok=True)
for entry in model['files']:
    path = target / entry['file']
    digest = hashlib.sha256()
    if path.exists():
        with path.open('rb') as source:
            while block := source.read(1024 * 1024):
                digest.update(block)
        if path.stat().st_size != entry['bytes'] or digest.hexdigest() != entry['sha256']:
            raise SystemExit('Existing file differs; inspect/remove it before retrying: ' + entry['file'])
        continue
    if shutil.disk_usage(target).free < entry['bytes'] + 100 * 1024 * 1024:
        raise SystemExit('Insufficient free space for selected model')
    url = ('https://huggingface.co/' + model['repository'] + '/resolve/' +
           model['revision'] + '/' + entry['file'])
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target, delete=False) as output:
            temporary = Path(output.name)
            with urllib.request.urlopen(url, timeout=60) as source:
                size = 0
                while block := source.read(1024 * 1024):
                    size += len(block)
                    if size > entry['bytes']:
                        raise ValueError('Download exceeds expected length')
                    digest.update(block)
                    output.write(block)
        if size != entry['bytes'] or digest.hexdigest() != entry['sha256']:
            raise ValueError('Model checksum mismatch')
        os.replace(temporary, path)
        print(entry['file'] + ': verified')
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
