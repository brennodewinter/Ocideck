"""Explicit model installation; no application path calls this script."""
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

root = Path(__file__).resolve().parent
for model in json.loads((root / 'models.json').read_text())['models']:
    name = model['name']
    cache = root / 'model'
    cache.mkdir(exist_ok=True)
    archive = cache / (name + '.zip')
    if not archive.exists():
        with urllib.request.urlopen('https://alphacephei.com/vosk/models/' + archive.name,
                                    timeout=60) as source, archive.open('wb') as target:
            shutil.copyfileobj(source, target)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != model['sha256']:
        raise SystemExit('Model archive checksum mismatch: ' + name)
    with zipfile.ZipFile(archive) as bundle:
        for item in bundle.infolist():
            path = (cache / item.filename).resolve()
            if not path.is_relative_to(cache.resolve()):
                raise SystemExit('Unsafe archive member')
        bundle.extractall(cache)
    print(name + ': verified and installed (' + model['license'] + ')')
