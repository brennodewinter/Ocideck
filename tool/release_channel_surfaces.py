#!/usr/bin/env python3
"""Resume public pointers only after the immutable channel publisher's readback."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tarfile
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


def phase_paths(args, phase):
    state = args.state_dir.resolve() / args.tag
    return state / (args.channel + '-' + phase + '-intent.json'), state / (args.channel + '-' + phase + '-completed.json')


def save(args, phase, value):
    _, receipt = phase_paths(args, phase)
    release_channel.immutable_write(receipt, release_channel.encoded(value))
    journal = receipt.parent / (args.channel + '.json')
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
                                         phase=phase, state='started', evidence=[intent]))


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


def matching_runs(api, nonce, tag, channel, controller):
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
            if (inputs != {'tag': tag, 'channel': channel, 'operation_id': nonce}
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


def verify_pages(data, get=fetch):
    for language, digest in data['pages'].items():
        path = '/ocideck/' if language == 'nl' else '/' + language + '/ocideck/'
        if sha256(get('https://librekat.nl' + path)).hexdigest() != digest:
            raise ValueError('live download page differs: ' + language)


def website(args, api):
    intent, _ = phase_paths(args, 'website')
    nonce = args.operation_id + '-website'
    wanted = {'tag': args.tag, 'channel': args.channel, 'operation_id': nonce, 'controller': args.controller_sha}
    found = matching_runs(api, nonce, args.tag, args.channel, args.controller_sha)
    if not intent.exists():
        if found:
            raise ValueError('website operation exists without local ownership receipt')
        main = api.get('/git/refs/heads/main')
        if main.get('object', {}).get('sha') != args.controller_sha:
            raise ValueError('website controller main moved; no dispatch attempted')
        begin(args, 'website', wanted)
        api.post('/actions/workflows/' + WORKFLOW + '/dispatches',
                 {'ref': 'main', 'inputs': {key: wanted[key] for key in ('tag', 'channel', 'operation_id')}})
        raise ValueError('website dispatched; use public again to reconcile terminal deployment')
    if read_json(intent) != wanted or len(found) != 1:
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
    verify_pages(proof)
    return save(args, 'website', dict(proof, deploy_run_id=deploy['id']))


def extract_web(archive, destination, version):
    if destination.exists():
        raise ValueError('web extraction destination must be absent')
    with tarfile.open(archive, 'r:gz') as bundle:
        members = bundle.getmembers()
        seen, total = set(), 0
        if len(members) > 100000:
            raise ValueError('web archive has too many members')
        for member in members:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or str(path) in seen
                    or not (member.isdir() or member.isfile()) or member.size < 0):
                raise ValueError('unsafe or duplicate web archive member')
            seen.add(str(path))
            total += member.size
        if total > 4 * 1024**3 or shutil.disk_usage(destination.parent).free < total + 128 * 1024**2:
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
    root = Path(__file__).resolve().parent.parent
    state = args.state_dir.resolve() / args.tag
    # Reauthenticate public immutable bytes and signatures on every resume.
    verify = SimpleNamespace(**vars(args), status=True)
    if release_channel_control_publish(verify):
        raise ValueError('public signed asset readback failed')
    release_channel_control_paths(args, state)
    with release_journal.locked(state / (args.channel + '-public')):
        if args.channel != 'web':
            result = {'website': website(args, api)}
            if args.channel == 'macos':
                manifest = read_json(args.evidence / 'channel-manifest-macos.json')
                name = 'ocideck-macos-' + args.tag[1:] + '.zip'
                url = 'https://pawprint.vigilis.online/LibreKAT/Ocideck/releases/download/' + args.tag + '/' + name
                command = ['bash', str(root / 'scripts/verify_homebrew_cask.sh'), '--expected-url', url,
                           '--expected-sha256', manifest['files'][name], args.tag]
                if subprocess.run(command, timeout=120).returncode:
                    raise ValueError('Homebrew exact pointer not verified; run tap channel update then resume public')
                result['homebrew'] = save(args, 'homebrew', {'tag': args.tag, 'channel': args.channel, 'url': url, 'sha256': manifest['files'][name]})
            return result
        archive = args.dist / ('ocideck-web-' + args.tag[1:] + '.tar.gz')
        bundle = state / 'web-public-bundle'
        if not bundle.exists():
            extract_web(archive, bundle, args.tag[1:])
        files = web_files(bundle)
        intent, _ = phase_paths(args, 'web')
        wanted = {'tag': args.tag, 'channel': args.channel, 'archive_sha256': release_channel.file_hash(archive), 'files': files}
        if intent.exists():
            if read_json(intent) != wanted:
                raise ValueError('web publication intent differs')
            verify_web(bundle)
        else:
            begin(args, 'web', wanted)
            if subprocess.run(['bash', str(root / 'scripts/deploy_web.sh'), '--bundle-dir', str(bundle)], timeout=2700).returncode:
                raise ValueError('web deployment interrupted or failed; inspect before resume; never blindly redeploy')
            verify_web(bundle)
        return {'web': save(args, 'web', wanted)}


def release_channel_control_publish(args):
    import release_channel_control
    return release_channel_control.publish(args)


def release_channel_control_paths(args, state):
    import release_channel_control
    return release_channel_control.select_candidate_paths(args, state)
