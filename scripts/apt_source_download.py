#!/usr/bin/env python3
"""Download exact sources through APT's authenticated repository indexes.

Uses the builder's configured repositories and Signed-By settings, adding only
deb-src. Does not enable third-party repositories or bypass authentication.
"""
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit, urlunsplit


def public_repository_config(text):
    def redact(match):
        url = urlsplit(match.group())
        # Authentication remains in the builder; never publish URI credentials,
        # tokens or query strings as provenance inside a distributable artifact.
        return urlunsplit((url.scheme, url.netloc.rsplit('@', 1)[-1], url.path, '', ''))
    return re.sub(r'https?://\S+', redact, text)


def source_entries(apt_dir):
    apt_dir = Path(apt_dir)
    entries = []
    for path in sorted((apt_dir / 'sources.list.d').glob('*.sources')):
        for stanza in re.split(r'\n\s*\n', path.read_text()):
            if re.search(r'^Enabled:\s*no\s*$', stanza, re.M | re.I):
                continue
            if re.search(r'^Types:.*\bdeb(?:-src)?\b', stanza, re.M):
                entries.append(re.sub(r'^Types:.*$', 'Types: deb-src', stanza,
                                      flags=re.M).strip())
    legacy = [apt_dir / 'sources.list',
              *sorted((apt_dir / 'sources.list.d').glob('*.list'))]
    lines = []
    for path in legacy:
        if path.is_file():
            for line in path.read_text().splitlines():
                if re.match(r'^\s*deb(?:-src)?\s', line):
                    lines.append(re.sub(r'^\s*deb(?:-src)?\s', 'deb-src ', line))
    if not entries and not lines:
        raise ValueError('No configured APT repositories for source download')
    # Do not inherit a builder's explicit unauthenticated/trusted override.
    for entry in entries + lines:
        if re.search(r'Trusted:\s*yes|Allow-(?:Insecure|Weak|Downgrade-To-Insecure):\s*yes|'
                     r'(?:trusted|allow-insecure|allow-weak|allow-downgrade-to-insecure)=yes', entry, re.I):
            raise ValueError('Unauthenticated APT repository is not allowed')
    return '\n\n'.join(entries) + '\n', '\n'.join(lines) + '\n'


def download(records, destination, apt_dir=Path('/etc/apt')):
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    deb822, legacy = source_entries(apt_dir)
    with tempfile.TemporaryDirectory(prefix='ocideck-apt-sources-') as temporary:
        config = Path(temporary)
        config.chmod(0o755)
        parts = config / 'parts'
        parts.mkdir()
        (parts / 'sources.sources').write_text(deb822)
        (config / 'sources.list').write_text(legacy)
        options = [f'-oDir::Etc::sourcelist={config / "sources.list"}',
                   f'-oDir::Etc::sourceparts={parts}',
                   '-oAPT::Get::AllowUnauthenticated=false',
                   '-oAcquire::AllowInsecureRepositories=false',
                   '-oAcquire::AllowWeakRepositories=false',
                   '-oAcquire::AllowDowngradeToInsecureRepositories=false',
                   '-oAPT::Update::Error-Mode=any']
        subprocess.run(['apt-get', *options, 'update'], check=True)
        for name, version in sorted({(r['source'], r['source_version']) for r in records}):
            if not re.fullmatch(r'[a-z0-9][a-z0-9+.-]*', name) or not re.fullmatch(r'[A-Za-z0-9:.+~_-]+', version):
                raise ValueError('Invalid source package identity')
            subprocess.run(['apt-get', *options, 'source', '--download-only',
                            '--only-source', '--', f'{name}={version}'],
                           cwd=destination, check=True)
    (destination / 'APT-ORIGIN.json').write_text(json.dumps({
        'method': 'apt-get source --download-only, authenticated Sources indexes',
        'deb822': public_repository_config(deb822),
        'sources_list': public_repository_config(legacy),
        'packages': sorted({f"{r['source']}={r['source_version']}" for r in records}),
    }, indent=2) + '\n')
