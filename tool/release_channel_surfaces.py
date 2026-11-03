#!/usr/bin/env python3
"""Resume public pointers only after the immutable channel publisher's readback."""
from concurrent.futures import ThreadPoolExecutor
import base64
from hashlib import sha256
import io
from html.parser import HTMLParser
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
from urllib.parse import quote, urlsplit
from urllib.request import Request, build_opener
import zipfile

import release_channel
import release_journal

LANGUAGES = ('nl', 'en', 'de', 'es', 'fr', 'it', 'pl', 'pt', 'uk')
WORKFLOW = 'website-downloads.yml'
TERMINAL = {'success', 'failure', 'cancelled', 'skipped', 'error'}


def read_json(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1048576:
        raise ValueError('unsafe public phase receipt')
    return json.loads(path.read_text(), object_pairs_hook=release_channel.no_duplicates)


def fetch(url, limit=32 * 1024 * 1024):
    from release_channel_controller import NoRedirect
    parsed = urlsplit(url)
    if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.fragment:
        raise ValueError('public URL must be credential-free HTTPS')
    with build_opener(NoRedirect).open(Request(url), timeout=30) as response:
        if response.status != 200:
            raise ValueError('public file is not HTTP 200')
        content = response.read(limit + 1)
    if len(content) > limit:
        raise ValueError('public file exceeds size bound')
    return content


def scoped_phase(args, phase):
    origin = getattr(args, 'rollback_from', None)
    return ('rollback-from-' + origin + '-' + phase) if origin else phase


def phase_paths(args, phase):
    phase = scoped_phase(args, phase)
    state = args.state_dir.resolve() / args.tag
    return state / (args.channel + '-' + phase + '-intent.json'), state / (args.channel + '-' + phase + '-completed.json')


def save(args, phase, value):
    _, receipt = phase_paths(args, phase)
    release_channel.immutable_write(receipt, release_channel.encoded(value))
    journal = receipt.parent / (args.channel + '.json')
    phase = scoped_phase(args, phase).replace('.', '_')
    current = release_journal.read(journal)
    previous = next((e for e in reversed(current['events']) if e['phase'] == phase), None)
    if previous is None:
        release_journal.record(SimpleNamespace(journal=journal, phase=phase, state='started', evidence=[receipt]))
    if not previous or previous['state'] != 'completed':
        release_journal.record(SimpleNamespace(journal=journal, phase=phase, state='completed', evidence=[receipt]))
    return value


def begin(args, phase, value):
    intent, _ = phase_paths(args, phase)
    release_channel.immutable_write(intent, release_channel.encoded(value))
    release_journal.record(SimpleNamespace(journal=intent.parent / (args.channel + '.json'),
                                         phase=scoped_phase(args, phase).replace('.', '_'), state='started', evidence=[intent]))


def public_status(args):
    phases = ['website'] if args.channel != 'web' else ['web']
    if args.channel == 'macos':
        phases.append('homebrew')
    result = {}
    for phase in phases:
        intent, receipt = phase_paths(args, phase)
        if receipt.exists() or receipt.is_symlink():
            try:
                data = read_json(receipt)
                if data.get('tag') != args.tag or data.get('channel') != args.channel:
                    raise ValueError('public phase identity differs')
                result[phase] = 'recorded_completed_live_unverified'
            except (ValueError, OSError):
                result[phase] = 'unknown'
        else:
            result[phase] = 'unknown' if intent.exists() else 'not_started'
    return result


def matching_runs(api, nonce, tag, channel, controller, expected_current=''):
    from release_channel_controller import payload
    matches = []
    for page in range(1, 51):
        response = api.get(f'/actions/runs?workflow_id={WORKFLOW}&limit=100&page={page}')
        runs = response.get('workflow_runs') if isinstance(response, dict) else None
        if not isinstance(runs, list):
            raise ValueError('invalid website run listing')
        for summary in runs:
            if payload(summary).get('inputs', {}).get('operation_id') != nonce:
                continue
            run = api.get('/actions/runs/' + str(summary['id']))
            inputs = payload(run).get('inputs', {})
            expected_inputs = {'tag': tag, 'channel': channel, 'operation_id': nonce}
            if expected_current:
                expected_inputs['expected_current_tag'] = expected_current
            if inputs.get('expected_current_tag') == '':
                inputs = {key: value for key, value in inputs.items() if key != 'expected_current_tag'}
            if (inputs != expected_inputs
                    or run.get('commit_sha') != controller
                    or run.get('trigger_event') != 'workflow_dispatch'
                    or run.get('workflow_id') not in (WORKFLOW, '.forgejo/workflows/' + WORKFLOW)):
                raise ValueError('website operation identity differs')
            matches.append(run)
        if len(runs) < 100:
            return matches
    raise ValueError('website run inspection bound exceeded')


def website_receipt(api, run_id, nonce, tag, channel):
    entries = api.get(f'/actions/runs/{run_id}/artifacts')
    entries = [entry for entry in entries if entry.get('name') == 'website-public-' + nonce and entry.get('expired') is False]
    if len(entries) != 1:
        raise ValueError('website public receipt artifact unavailable')
    with zipfile.ZipFile(io.BytesIO(api.artifact(entries[0]['id']))) as archive:
        members = archive.infolist()
        if (len(members) != 1 or members[0].filename != 'website-public.json'
                or members[0].file_size > 65536 or members[0].is_dir()
                or stat.S_IFMT(members[0].external_attr >> 16) not in (0, stat.S_IFREG)):
            raise ValueError('unsafe website public receipt')
        data = json.loads(archive.read(members[0]), object_pairs_hook=release_channel.no_duplicates)
    if (data.get('tag') != tag or data.get('channel') != channel or data.get('operation_id') != nonce
            or not re.fullmatch('[0-9a-f]{40}', data.get('commit', ''))
            or set(data.get('pages', {})) != set(LANGUAGES)
            or any(not re.fullmatch('[0-9a-f]{64}', digest) for digest in data['pages'].values())):
        raise ValueError('website public receipt identity differs')
    return data


ROW_KEYS = {'macos': ('macos',), 'windows': ('windows', 'windows_installer'),
            'linux-tar': ('linux_tar',), 'linux-debian12': ('linux_debian12',),
            'linux-deb': ('linux_deb',), 'linux-rpm': ('linux_rpm',),
            'linux-appimage': ('linux_appimage',), 'linux-flatpak': ('linux_flatpak',)}


class DownloadRows(HTMLParser):
    def __init__(self, keys):
        super().__init__()
        self.keys, self.rows, self.stack = set(keys), {}, []
        self.active = None

    def handle_starttag(self, tag, attrs):
        if tag == 'li' and 'li' in self.stack:
            index = len(self.stack) - 1 - self.stack[::-1].index('li')
            if not any(item in ('ul', 'ol') for item in self.stack[index + 1:]):
                self.stack = self.stack[:index]
                if self.active and index == self.active[1]:
                    self.active = None
        attributes = dict(attrs)
        if len(attributes) != len(attrs):
            raise ValueError('duplicate download HTML attributes')
        if tag == 'li' and attributes.get('data-ocideck-download') in self.keys:
            key = attributes['data-ocideck-download']
            if key in self.rows or self.active is not None:
                raise ValueError('duplicate or nested selected download row')
            self.rows[key] = []
            self.active = (key, len(self.stack))
        if tag == 'a' and self.active and 'product-action-primary' in attributes.get('class', '').split():
            if 'data-ocideck-download-primary' not in attributes:
                raise ValueError('selected primary download marker missing')
            self.rows[self.active[0]].append(attributes.get('href'))
        if tag not in {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag not in self.stack:
            return
        index = len(self.stack) - 1 - self.stack[::-1].index(tag)
        self.stack = self.stack[:index]
        if self.active and len(self.stack) <= self.active[1]:
            self.active = None

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if self.stack and self.stack[-1] == tag:
            self.handle_endtag(tag)


def selected_urls(args):
    manifest = read_json(args.evidence / ('channel-manifest-' + args.channel + '.json'))
    if (manifest.get('tag') != args.tag or manifest.get('channel') != args.channel
            or manifest.get('source') != args.sha or manifest.get('controller_sha') != args.controller_sha):
        raise ValueError('selected website manifest identity differs')
    names = [name.format(v=args.tag[1:]) for name in release_channel.CHANNELS[args.channel]
             if not name.endswith('.json')]
    if not set(names) <= manifest.get('files', {}).keys():
        raise ValueError('selected primary downloads absent from signed manifest')
    return {key: 'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/' + args.tag + '/' + name
            for key, name in zip(ROW_KEYS[args.channel], names)}


def verify_pages(data, expected, get=fetch):
    # Historical full-page hashes remain provenance; another OS may legitimately
    # change those pages before this channel's own readback or later resume.
    if set(data['pages']) != set(LANGUAGES):
        raise ValueError('historical page provenance incomplete')
    for language in LANGUAGES:
        path = '/' + language + '/ocideck/'
        parser = DownloadRows(expected)
        parser.feed(get('https://librekat.nl' + path).decode('utf-8'))
        parser.close()
        if parser.active or parser.rows != {key: [url] for key, url in expected.items()}:
            raise ValueError('selected live primary downloads differ: ' + language)


def website(args, api):
    intent, _ = phase_paths(args, 'website')
    rollback_from = getattr(args, 'rollback_from', '') or ''
    nonce = (sha256((args.operation_id + rollback_from).encode()).hexdigest()[:32]
             if rollback_from else args.operation_id) + '-website'
    wanted = {'tag': args.tag, 'channel': args.channel, 'operation_id': nonce}
    if rollback_from:
        wanted['expected_current_tag'] = rollback_from
    if not intent.exists():
        # Main may advance after the immutable build. Only an identical reviewed
        # updater definition may acquire the new public-pointer controller.
        main = api.get('/git/refs/heads/main')
        controller = main.get('object', {}).get('sha', '')
        if not re.fullmatch('[0-9a-f]{40}', controller):
            raise ValueError('website controller main SHA unavailable')
        definition = api.get('/contents/.forgejo/workflows/' + WORKFLOW + '?ref=' + controller)
        local = Path(__file__).resolve().parent.parent / '.forgejo/workflows' / WORKFLOW
        if (definition.get('encoding') != 'base64'
                or base64.b64decode(definition.get('content', ''), validate=False) != local.read_bytes()):
            raise ValueError('current website workflow differs from reviewed controller')
        found = matching_runs(api, nonce, args.tag, args.channel, controller, rollback_from)
        if found:
            raise ValueError('website operation exists without local ownership receipt')
        wanted['controller'] = controller
        begin(args, 'website', wanted)
        if api.get('/git/refs/heads/main').get('object', {}).get('sha') != controller:
            raise ValueError('website controller main moved; intent remains unknown, never redispatch')
        api.post('/actions/workflows/' + WORKFLOW + '/dispatches',
                 {'ref': 'main', 'inputs': {key: value for key, value in wanted.items() if key != 'controller'}})
        raise ValueError('website dispatched; use public again to reconcile terminal deployment')
    saved = read_json(intent)
    if any(saved.get(key) != value for key, value in wanted.items()):
        raise ValueError('website publication intent identity differs')
    controller = saved.get('controller', '')
    if not re.fullmatch('[0-9a-f]{40}', controller):
        raise ValueError('website controller identity missing')
    found = matching_runs(api, nonce, args.tag, args.channel, controller, rollback_from)
    if len(found) != 1:
        raise ValueError('website dispatch unknown or ambiguous; never repeat POST')
    run = found[0]
    work = api.get('/actions/runs/' + str(run['id']) + '/jobs')
    if run.get('status') != 'success' or not work or any(job.get('status') != 'success' for job in work):
        raise ValueError('website source update is not terminal green')
    proof = website_receipt(api, run['id'], nonce, args.tag, args.channel)
    from release_channel_controller import Forgejo
    site = Forgejo('https://pawprint.vigilis.online/api/v1/repos/LibreKAT/website')
    deployments = site.get('/actions/runs?limit=100&page=1&head_sha=' + proof['commit'])['workflow_runs']
    deployments = [r for r in deployments if r.get('commit_sha') == proof['commit'] and r.get('workflow_id') in ('deploy.yml', '.forgejo/workflows/deploy.yml')]
    if not deployments:
        raise ValueError('website deployment for exact source commit unavailable')
    deploy = max(deployments, key=lambda value: value['id'])
    work = site.get('/actions/runs/' + str(deploy['id']) + '/jobs')
    if deploy.get('status') != 'success' or not work or any(job.get('status') != 'success' for job in work):
        raise ValueError('website deployment is not terminal green')
    verify_pages(proof, selected_urls(args))
    return save(args, 'website', dict(proof, deploy_run_id=deploy['id']))


WEB_MEMBER_LIMIT = 100000
WEB_DATA_LIMIT = 4 * 1024**3
WEB_METADATA_LIMIT = 1024**2
WEB_METADATA_TOTAL_LIMIT = 8 * 1024**2


class BoundedWebMember(tarfile.TarInfo):
    def _proc_gnusparse_00(self, *_args):
        raise ValueError('sparse web archive metadata is not supported')

    _proc_gnusparse_01 = _proc_gnusparse_00
    _proc_gnusparse_10 = _proc_gnusparse_00

    def _proc_member(self, archive):
        count = getattr(archive, '_web_count', 0) + 1
        archive._web_count = count
        if count > WEB_MEMBER_LIMIT:
            raise ValueError('web archive has too many members')
        metadata = self.type in (tarfile.XHDTYPE, tarfile.XGLTYPE, tarfile.SOLARIS_XHDTYPE,
                                 tarfile.GNUTYPE_LONGNAME, tarfile.GNUTYPE_LONGLINK)
        if metadata:
            total = getattr(archive, '_web_metadata', 0) + self.size
            if self.size > WEB_METADATA_LIMIT or total > WEB_METADATA_TOTAL_LIMIT:
                raise ValueError('web archive metadata exceeds budget')
            archive._web_metadata = total
        elif not (self.isdir() or self.isfile()) or self.type == tarfile.GNUTYPE_SPARSE:
            raise ValueError('unsafe web archive member type')
        elif self.size < 0 or self.size > WEB_DATA_LIMIT:
            raise ValueError('web archive exceeds storage budget')
        return super()._proc_member(archive)


def extract_web(archive, destination, version):
    if destination.exists():
        raise ValueError('web extraction destination must be absent')
    with tarfile.open(archive, 'r:gz', tarinfo=BoundedWebMember) as bundle:
        members = []
        seen, total = set(), 0
        for member in bundle:
            if len(members) >= WEB_MEMBER_LIMIT:
                raise ValueError('web archive has too many members')
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or str(path) in seen
                    or not (member.isdir() or member.isfile()) or member.size < 0):
                raise ValueError('unsafe or duplicate web archive member')
            seen.add(str(path))
            total += member.size
            if total > WEB_DATA_LIMIT:
                raise ValueError('web archive exceeds storage budget')
            members.append(member)
        if total > WEB_DATA_LIMIT or shutil.disk_usage(destination.parent).free < total + 128 * 1024**2:
            raise ValueError('web archive exceeds storage budget')
        destination.mkdir(mode=0o700)
        for member in members:
            target = destination / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output)
    if json.loads((destination / 'version.json').read_text()).get('version') != version:
        raise ValueError('web archive version differs')


def web_files(bundle):
    if bundle.is_symlink() or not bundle.is_dir() or any(path.is_symlink() for path in bundle.rglob('*')):
        raise ValueError('web bundle must contain only real directories and regular files')
    entries = {}
    for line in (bundle / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        name = name.removeprefix('*').removeprefix('./')
        path = PurePosixPath(name)
        if not re.fullmatch('[0-9a-f]{64}', digest) or path.is_absolute() or '..' in path.parts or name in entries:
            raise ValueError('invalid internal web manifest')
        if release_channel.file_hash(bundle / name) != digest:
            raise ValueError('internal web file differs')
        entries[name] = digest
    if any(not (p.is_dir() or p.is_file()) for p in bundle.rglob('*')):
        raise ValueError('special file in web bundle')
    actual = {str(p.relative_to(bundle)) for p in bundle.rglob('*') if p.is_file() and p.name != 'SHA256SUMS'}
    if not entries or set(entries) != actual:
        raise ValueError('internal web manifest does not cover exact files')
    return entries


def verify_web(bundle, get=fetch):
    files = web_files(bundle)
    if get('https://ocideck.librekat.nl/SHA256SUMS') != (bundle / 'SHA256SUMS').read_bytes():
        raise ValueError('live web checksum list differs')
    def check(entry):
        name, digest = entry
        return sha256(get('https://ocideck.librekat.nl/' + quote(name, safe='/'))).hexdigest() == digest
    with ThreadPoolExecutor(max_workers=8) as workers:
        if not all(workers.map(check, files.items())):
            raise ValueError('live web bytes differ')
    return files


def public(args, api):
    if not args.dist or not args.evidence or not args.run_id:
        raise ValueError('public phases require exact signed candidate and run ID')
    release_channel.identity(args.tag, args.sha, args.channel)
    validate_rollback(args)
    root = Path(__file__).resolve().parent.parent
    state = args.state_dir.resolve() / args.tag
    # Reauthenticate public immutable bytes and signatures on every resume.
    verify = SimpleNamespace(**vars(args), status=True)
    if release_channel_control_publish(verify):
        raise ValueError('public signed asset readback failed')
    release_channel_control_paths(args, state)
    with release_journal.locked(state / (args.channel + '-public')):
        if getattr(args, 'rollback_from', None):
            check_rollback_pointer(args)
        if args.channel != 'web':
            result = {'website': website(args, api)}
            if args.channel == 'macos':
                result['homebrew'] = homebrew(args, root)
            return result
        archive = args.dist / ('ocideck-web-' + args.tag[1:] + '.tar.gz')
        # Reconstruct from authenticated archive on every invocation, never trust
        # an old mutable extraction after a crash or operator edit.
        with tempfile.TemporaryDirectory(prefix='web-public-', dir=state) as temporary:
            bundle = Path(temporary) / 'bundle'
            extract_web(archive, bundle, args.tag[1:])
            files = web_files(bundle)
            intent, _ = phase_paths(args, 'web')
            wanted = {'tag': args.tag, 'channel': args.channel, 'archive_sha256': release_channel.file_hash(archive), 'files': files}
            if intent.exists():
                if read_json(intent) != wanted:
                    raise ValueError('web publication intent differs')
                verify_web(bundle)
            else:
                if subprocess.run(['bash', str(root / 'scripts/deploy_web.sh'), '--preflight-only', '--bundle-dir', str(bundle)], timeout=300).returncode:
                    raise ValueError('web preflight failed before any deploy intent; repair and retry same bytes')
                begin(args, 'web', wanted)
                if subprocess.run(['bash', str(root / 'scripts/deploy_web.sh'), '--bundle-dir', str(bundle)], timeout=2700).returncode:
                    raise ValueError('web deployment interrupted or failed; inspect before resume; never blindly redeploy')
                verify_web(bundle)
            return {'web': save(args, 'web', wanted)}




def validate_rollback(args):
    previous = getattr(args, 'rollback_from', None)
    if previous is None:
        return
    release_channel.identity(previous, args.sha, args.channel)
    target = tuple(map(int, args.tag[1:].split('.')))
    current = tuple(map(int, previous[1:].split('.')))
    if target >= current:
        raise ValueError('rollback target must be strictly older than rollback-from')


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.urls.extend(value for key, value in attrs if key == 'href' and value)


def page_tags(content, channel):
    parser = Links()
    parser.feed(content.decode('utf-8'))
    names = release_channel.CHANNELS[channel]
    tags = set()
    seen = set()
    for pattern in names:
        if pattern.endswith('.json'):
            continue
        regex = re.escape(pattern).replace(r'\{v\}', r'([0-9]+\.[0-9]+\.[0-9]+)')
        for url in parser.urls:
            match = re.fullmatch(r'https://pawprint\.vigilis\.online/LibreKAT/Ocideck/releases/download/(v[0-9]+\.[0-9]+\.[0-9]+)/' + regex, url)
            if match:
                if match[1] != 'v' + match[2]:
                    raise ValueError('download URL tag and filename disagree')
                seen.add(pattern)
                tags.add(match[1])
    expected = {name for name in names if not name.endswith('.json')}
    if seen != expected:
        raise ValueError('selected download rows unavailable for rollback')
    return tags


def check_rollback_pointer(args, get=fetch):
    phase = 'web' if args.channel == 'web' else 'website'
    intent, _ = phase_paths(args, phase)
    allowed = {args.rollback_from}
    if intent.is_file() and not intent.is_symlink():
        recorded = read_json(intent)
        if recorded.get('tag') != args.tag or recorded.get('channel') != args.channel:
            raise ValueError('rollback intent identity differs')
        allowed.add(args.tag)
    if args.channel == 'web':
        value = json.loads(get('https://ocideck.librekat.nl/version.json'), object_pairs_hook=release_channel.no_duplicates)
        tags = {'v' + value.get('version', '')}
    else:
        tags = set()
        for language in LANGUAGES:
            path = '/' + language + '/ocideck/'
            tags.update(page_tags(get('https://librekat.nl' + path), args.channel))
    if not tags or not tags <= allowed:
        raise ValueError('current public pointer differs from explicit rollback-from or owned target')
    if args.channel == 'macos':
        tap_intent, _ = phase_paths(args, 'homebrew')
        tap_allowed = {args.rollback_from}
        if tap_intent.is_file() and not tap_intent.is_symlink():
            saved = read_json(tap_intent)
            if saved.get('tag') != args.tag or saved.get('channel') != args.channel:
                raise ValueError('Homebrew rollback intent identity differs')
            tap_allowed.add(args.tag)
        cask = get('https://pawprint.vigilis.online/LibreKAT/homebrew-ocideck/raw/branch/main/Casks/ocideck.rb').decode('utf-8')
        versions = re.findall(r'^\s*version "([0-9]+\.[0-9]+\.[0-9]+)"', cask, re.M)
        urls = re.findall(r'^\s*url "([^"\n]+)"', cask, re.M)
        if len(versions) != 1 or len(urls) != 1 or 'v' + versions[0] not in tap_allowed:
            raise ValueError('Homebrew current pointer differs from rollback-from or owned target')
        tag = 'v' + versions[0]
        expected = 'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/' + tag + '/ocideck-macos-' + versions[0] + '.zip'
        if urls[0] != expected:
            raise ValueError('Homebrew current download URL differs')



def homebrew(args, root):
    from release_channel_controller import Forgejo, payload
    manifest = read_json(args.evidence / 'channel-manifest-macos.json')
    name = 'ocideck-macos-' + args.tag[1:] + '.zip'
    url = 'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/' + args.tag + '/' + name
    command = ['bash', str(root / 'scripts/verify_homebrew_cask.sh'), '--expected-url', url,
               '--expected-sha256', manifest['files'][name], args.tag]
    pin = bool(getattr(args, 'rollback_from', None))
    nonce = sha256((args.operation_id + (getattr(args, 'rollback_from', '') or '') + '-homebrew').encode()).hexdigest()[:40]
    intent, _ = phase_paths(args, 'homebrew')
    wanted = {'tag': args.tag, 'channel': args.channel, 'operation_id': nonce, 'pin': 'true' if pin else 'false'}
    api = Forgejo('https://pawprint.vigilis.online/api/v1/repos/LibreKAT/homebrew-ocideck')
    workflow = 'update-cask.yml'
    if not intent.exists():
        # Even an already-correct cask needs the policy transaction: rollback
        # must pin it and a later normal publication must clear that hold.
        main = api.get('/git/refs/heads/main')['object']['sha']
        if not re.fullmatch('[0-9a-f]{40}', main):
            raise ValueError('invalid Homebrew controller commit')
        wanted['controller'] = main
        begin(args, 'homebrew', wanted)
        if api.get('/git/refs/heads/main').get('object', {}).get('sha') != main:
            raise ValueError('Homebrew main moved; intent remains unknown, never redispatch')
        api.post('/actions/workflows/' + workflow + '/dispatches',
                 {'ref': 'main', 'inputs': {key: wanted[key] for key in ('tag', 'operation_id', 'pin')}})
        raise ValueError('Homebrew dispatched; resume public after terminal tap update')
    saved = read_json(intent)
    if any(saved.get(key) != value for key, value in wanted.items()):
        raise ValueError('Homebrew dispatch intent differs')
    matches = []
    for page in range(1, 51):
        listing = api.get(f'/actions/runs?workflow_id={workflow}&limit=100&page={page}')['workflow_runs']
        for run in listing:
            if payload(run).get('inputs', {}).get('operation_id') != nonce:
                continue
            detail = api.get('/actions/runs/' + str(run['id']))
            if (detail.get('commit_sha') != saved['controller']
                    or detail.get('workflow_id') not in (workflow, '.forgejo/workflows/' + workflow)
                    or detail.get('trigger_event') != 'workflow_dispatch'
                    or payload(detail).get('inputs') != {key: wanted[key] for key in ('tag', 'operation_id', 'pin')}):
                raise ValueError('Homebrew operation provenance differs')
            matches.append(detail)
        if len(listing) < 100:
            break
    else:
        raise ValueError('Homebrew run inspection bound exceeded')
    if len(matches) != 1:
        raise ValueError('Homebrew dispatch unknown or ambiguous; never repeat POST')
    run = matches[0]
    jobs = api.get('/actions/runs/' + str(run['id']) + '/jobs')
    if run.get('status') != 'success' or not jobs or any(job.get('status') != 'success' for job in jobs):
        raise ValueError('Homebrew update is not terminal green')
    artifacts = api.get('/actions/runs/' + str(run['id']) + '/artifacts')
    artifacts = [item for item in artifacts if item.get('name') == 'homebrew-channel-' + nonce and item.get('expired') is False]
    if len(artifacts) != 1:
        raise ValueError('Homebrew policy receipt missing')
    with zipfile.ZipFile(io.BytesIO(api.artifact(artifacts[0]['id']))) as zipped:
        members = zipped.infolist()
        if (len(members) != 1 or members[0].filename != 'homebrew-channel.json'
                or members[0].file_size > 65536 or members[0].is_dir()
                or stat.S_IFMT(members[0].external_attr >> 16) not in (0, stat.S_IFREG)):
            raise ValueError('unsafe Homebrew receipt')
        proof = json.loads(zipped.read(members[0]), object_pairs_hook=release_channel.no_duplicates)
    if (proof.get('tag') != args.tag or proof.get('operation_id') != nonce
            or proof.get('pinned') is not pin or not re.fullmatch('[0-9a-f]{40}', proof.get('commit', ''))
            or not re.fullmatch('[0-9a-f]{64}', proof.get('cask_sha256', ''))):
        raise ValueError('Homebrew policy receipt identity differs')
    cask = fetch('https://pawprint.vigilis.online/LibreKAT/homebrew-ocideck/raw/commit/' + proof['commit'] + '/Casks/ocideck.rb')
    if sha256(cask).hexdigest() != proof['cask_sha256'] or subprocess.run(command, timeout=120).returncode:
        raise ValueError('Homebrew exact public cask not verified')
    return save(args, 'homebrew', dict(proof, channel=args.channel, url=url, sha256=manifest['files'][name], run_id=run['id']))

def release_channel_control_publish(args):
    import release_channel_control
    return release_channel_control.publish(args)


def release_channel_control_paths(args, state):
    import release_channel_control
    return release_channel_control.select_candidate_paths(args, state)
