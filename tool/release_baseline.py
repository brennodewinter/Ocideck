#!/usr/bin/env python3
"""Reserve the next version from signed public evidence, not a stale main version.

Checks metadata/signatures and asset presence, not archive bytes or deployment.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, build_opener

from release_channel import CHANNELS, identity, no_duplicates

LIMIT = 2 * 1024 * 1024


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('baseline downloads do not follow redirects')


class PublicTransport:
    def __init__(self, api):
        self.api = api.rstrip('/')
        self.origin = urlsplit(self.api)
        if self.origin.scheme != 'https' or self.origin.username or self.origin.password or self.origin.query or self.origin.fragment:
            raise ValueError('API must be a public HTTPS URL')
        self.opener = build_opener(NoRedirect)

    def get(self, path):
        url = path if path.startswith('https://') else self.api + path
        target = urlsplit(url)
        if target.scheme != 'https' or target.netloc != self.origin.netloc or target.username or target.password or target.fragment:
            raise ValueError('download escaped release host')
        with self.opener.open(url, timeout=30) as response:
            body = response.read(LIMIT + 1)
        if len(body) > LIMIT:
            raise ValueError('release metadata exceeds size limit')
        return body

    def data(self, path):
        return json.loads(self.get(path), object_pairs_hook=no_duplicates)


def git(repo, *args):
    result = subprocess.run(['git', '-C', str(repo), *args], capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise ValueError('cannot read repository evidence: ' + ' '.join(args[:2]))
    return result.stdout


def abandoned(repo):
    source = (repo / 'scripts/release.sh').read_text()
    match = re.search(r'local abandoned_tags=\(\s*(.*?)\n\s*\)', source, re.S)
    if not match:
        raise ValueError('explicit abandoned-tag policy missing')
    values = set()
    for line in match.group(1).splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', line):
            raise ValueError('unsupported abandoned-tag policy')
        values.add(line)
    return values


def remote_tags(repo, remote):
    direct, peeled = {}, {}
    for line in git(repo, 'ls-remote', '--tags', remote).splitlines():
        sha, ref = line.split()
        if not ref.startswith('refs/tags/'):
            raise ValueError('invalid remote tag reference')
        tag = ref[len('refs/tags/'):] 
        target = peeled if tag.endswith('^{}') else direct
        tag = tag[:-3] if tag.endswith('^{}') else tag
        if re.fullmatch(r'v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', tag):
            identity(tag, sha, 'web')
            if tag in target:
                raise ValueError('duplicate remote tag')
            target[tag] = sha
    return {tag: peeled.get(tag, sha) for tag, sha in direct.items()}


def signature(body, signed, key):
    with tempfile.TemporaryDirectory(prefix='release-baseline-') as directory:
        target = Path(directory) / 'manifest'
        sig = Path(directory) / 'manifest.minisig'
        target.write_bytes(body)
        sig.write_bytes(signed)
        result = subprocess.run(['minisign', '-Vm', str(target), '-x', str(sig), '-p', str(key)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        if result.returncode:
            raise ValueError('invalid public release signature')


def asset_listing(transport, release_id):
    assets = {}
    if type(release_id) is not int or release_id <= 0:
        raise ValueError('invalid release ID')
    for page in range(1, 101):
        values = transport.data(f'/releases/{release_id}/assets?limit=50&page={page}')
        if not isinstance(values, list):
            raise ValueError('invalid assets response')
        for asset in values:
            name = asset.get('name')
            if not isinstance(name, str) or name in assets:
                raise ValueError('invalid or duplicate release asset')
            assets[name] = asset
        if len(values) < 50:
            return assets
    raise ValueError('asset listing exceeds bound')


def public_proof(transport, assets, tag, sha, key):
    version = tag[1:]
    shared = {f'ocideck-{version}.cdx.json', f'ocideck-{version}.spdx.json'}
    # Legacy all-platform releases predate the independently published Windows cohort.
    all_names = ({template.format(v=version) for names in CHANNELS.values() for template in names}
                 - {f'ocideck-windows-cohort-{version}.json'}) | shared

    def read(name):
        if name not in assets:
            raise ValueError('missing public evidence: ' + name)
        return transport.get(assets[name]['browser_download_url'])

    if 'SHA256SUMS' in assets:
        body = read('SHA256SUMS')
        signature(body, read('SHA256SUMS.minisig'), key)
        names = set()
        for line in body.decode().splitlines():
            match = re.fullmatch(r'[0-9a-fA-F]{64}  (?:\./)?([A-Za-z0-9._+-]+)', line)
            if not match or match[1] in names:
                raise ValueError('invalid global checksum manifest')
            names.add(match[1])
        if names != all_names or not names <= assets.keys():
            raise ValueError('incomplete global publication')
        return
    for channel, templates in CHANNELS.items():
        name = f'channel-manifest-{channel}.json'
        if name not in assets:
            continue
        body = read(name)
        signature(body, read(name + '.minisig'), key)
        data = json.loads(body, object_pairs_hook=no_duplicates)
        if not isinstance(data, dict) or set(data) != {'schema', 'tag', 'version', 'source', 'controller_sha', 'channel', 'run_id', 'files'}:
            raise ValueError('invalid channel manifest')
        identity(tag, data['controller_sha'], channel)
        if type(data['schema']) is not int or data['schema'] != 1 or data['tag'] != tag or data['version'] != version or data['source'] != sha or data['channel'] != channel:
            raise ValueError('public channel identity mismatch')
        if not isinstance(data['run_id'], str) or not re.fullmatch(r'[1-9][0-9]*', data['run_id']):
            raise ValueError('invalid public run identity')
        files = data['files']
        owned = {template.format(v=version) for template in templates}
        if not isinstance(files, dict) or not owned <= files.keys() or not files.keys() <= owned | shared or not files.keys() <= assets.keys():
            raise ValueError('incomplete channel publication')
        if any(not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest) for digest in files.values()):
            raise ValueError('invalid channel checksum')
        return
    raise ValueError('tag has no signed public publication; resume it first')


def baseline(args, transport=None):
    if not re.fullmatch(r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', args.current_version):
        raise ValueError('invalid current version')
    if type(args.current_build) is not int or args.current_build < 0:
        raise ValueError('invalid current build')
    origin, mirror = remote_tags(args.repo, 'origin'), remote_tags(args.repo, 'mirror')
    ignored = abandoned(args.repo)
    current = tuple(map(int, args.current_version.split('.')))
    candidates = [tag for tag in origin.keys() | mirror.keys() if tag not in ignored and tuple(map(int, tag[1:].split('.'))) >= current]
    if not candidates:
        raise ValueError('current version has no public tag; resume it first')
    tag = max(candidates, key=lambda value: tuple(map(int, value[1:].split('.'))))
    sha = origin.get(tag)
    if not sha or mirror.get(tag) != sha:
        raise ValueError('public tag source differs or missing on a remote')
    transport = transport or PublicTransport(args.api)
    release = transport.data('/releases/tags/' + tag)
    if release.get('tag_name') != tag or release.get('draft') is not False or release.get('prerelease') is not False:
        raise ValueError('highest tag is not publicly released; resume it first')
    assets = asset_listing(transport, release['id'])
    public_proof(transport, assets, tag, sha, args.public_key)
    pubspec = git(args.repo, 'show', sha + ':pubspec.yaml')
    match = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', pubspec, re.M)
    if not match or match[1] != tag[1:]:
        raise ValueError('published source pubspec differs; fetch immutable tag objects first')
    return {'version': tag[1:], 'build': max(args.current_build, int(match[2])), 'tag': tag, 'source': sha}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--current-version', required=True)
    parser.add_argument('--current-build', type=int, required=True)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--api', required=True)
    parser.add_argument('--public-key', type=Path, required=True)
    try:
        print(json.dumps(baseline(parser.parse_args()), sort_keys=True))
        return 0
    except (ValueError, OSError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
