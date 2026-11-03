#!/usr/bin/env python3
"""Reuse the existing Windows candidate build and suite on an immutable ref."""
import argparse
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote, urlsplit
import zipfile

from release_channel import identity, no_duplicates, file_hash
from release_journal import atomic_write, locked

REPO = 'brennodewinter/Ocideck'
WORKFLOWS = ('windows-test-check.yml', 'release.yml')
MAX_ARCHIVE = 4 * 1024 * 1024 * 1024
POLL_SECONDS = 20 * 60
COLLECT_SECONDS = 30 * 60


class GitHub:
    def __init__(self):
        token = os.environ.get('GH_DISPATCH_TOKEN', '')
        if not token or any(c in token for c in '\r\n"\\'):
            raise ValueError('existing GH_DISPATCH_TOKEN is required for exact Windows proof')
        self.authorization = 'header = "Authorization: Bearer ' + token + '"\n'

    def request(self, url, output, payload=None, authenticated=True, redirect=False):
        remaining = getattr(self, 'deadline', None)
        remaining = None if remaining is None else remaining - time.monotonic()
        if remaining is not None and remaining <= 0:
            raise TimeoutError('Windows cancellation deadline reached')
        parsed = urlsplit(url)
        if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.fragment or any(c in url for c in '\r\n"\\'):
            raise ValueError('invalid GitHub request URL')
        if authenticated and (parsed.netloc != 'api.github.com' or not parsed.path.startswith('/repos/' + REPO + '/')):
            raise ValueError('authenticated request escaped GitHub repository')
        if not authenticated and not (parsed.hostname or '').endswith(('.blob.core.windows.net', '.githubusercontent.com')):
            raise ValueError('artifact redirect escaped GitHub storage')
        config = 'url = "' + url + '"\n'
        if authenticated:
            config += self.authorization
        command = ['curl', '--config', '-', '--silent', '--show-error', '--connect-timeout', '15', '--max-time', str(min(300, max(1, math.ceil(remaining))) if remaining is not None else 300),
                   '--proto', '=https', '--max-filesize', str(MAX_ARCHIVE if redirect or not authenticated else 2097152),
                   '--output', str(output), '--write-out', '%{http_code}', '--header', 'Accept: application/vnd.github+json']
        headers = Path(str(output) + '.headers')
        if redirect:
            command += ['--dump-header', str(headers)]
        if payload is not None:
            command += ['--request', 'POST', '--header', 'Content-Type: application/json', '--data-binary', '@-']
            # curl's config and payload cannot share stdin; put the nonsensitive dispatch body in a private temporary file.
            with tempfile.NamedTemporaryFile() as body:
                body.write(json.dumps(payload).encode()); body.flush()
                command[-1] = '@' + body.name
                result = subprocess.run(command, input=config.encode(), capture_output=True, timeout=min(330, remaining) if remaining is not None else 330)
        else:
            result = subprocess.run(command, input=config.encode(), capture_output=True, timeout=min(330, remaining) if remaining is not None else 330)
        if result.returncode:
            if getattr(self, 'deadline', None) is not None and time.monotonic() >= self.deadline:
                raise TimeoutError('Windows phase deadline reached')
            raise ValueError('GitHub request failed; reconcile existing runs before retry')
        if redirect and result.stdout in (b'301', b'302', b'303', b'307', b'308'):
            locations = re.findall(r'^location:\s*(.*?)\s*$', headers.read_text(), re.I | re.M)
            if len(locations) != 1:
                raise ValueError('artifact response has no unique redirect')
            self.request(locations[0], output, authenticated=False)
        elif not re.fullmatch(rb'2[0-9][0-9]', result.stdout):
            raise ValueError('GitHub returned a non-success status; no automatic retry')
        headers.unlink(missing_ok=True)

    def data(self, path, payload=None):
        with tempfile.TemporaryDirectory(prefix='windows-api-') as directory:
            output = Path(directory) / 'response'
            self.request('https://api.github.com/repos/' + REPO + path, output, payload)
            body = output.read_bytes()
            if len(body) > 2097152:
                raise ValueError('GitHub metadata exceeds size bound')
            return json.loads(body, object_pairs_hook=no_duplicates) if body else None

    def download(self, artifact_id, output):
        self.request('https://api.github.com/repos/' + REPO + '/actions/artifacts/' + str(artifact_id) + '/zip', output, redirect=True)


def pages(api, path, key):
    values = []
    for page in range(1, 101):
        if getattr(api, 'deadline', None) is not None and time.monotonic() >= api.deadline:
            raise TimeoutError('Windows cancellation deadline reached')
        response = api.data(path + ('&' if '?' in path else '?') + 'per_page=100&page=' + str(page))
        current = response.get(key) if isinstance(response, dict) else None
        if not isinstance(current, list) or len(current) > 100 or any(not isinstance(value, dict) for value in current):
            raise ValueError('invalid paginated GitHub metadata')
        values.extend(current)
        if len(current) < 100:
            return values
    raise ValueError('GitHub history exceeds inspection bound')


def source_file(api, path, sha):
    response = api.data('/contents/' + path + '?ref=' + sha)
    if not isinstance(response, dict) or response.get('encoding') != 'base64' or not isinstance(response.get('content'), str):
        raise ValueError('cannot establish exact Windows source bytes: ' + path)
    return base64.b64decode(''.join(response['content'].split()), validate=True)


def source_contract(api, root, tag, sha, ref):
    identity(tag, sha, 'windows')
    if ref != 'codex/release-candidate-' + tag + '-' + sha:
        raise ValueError('Windows ref is not the immutable candidate ref')
    remote = api.data('/git/ref/heads/' + quote(ref, safe=''))
    if not isinstance(remote, dict) or remote.get('ref') != 'refs/heads/' + ref or remote.get('object', {}).get('sha') != sha:
        raise ValueError('Windows mirror frozen ref differs from source')
    for workflow in WORKFLOWS:
        path = '.github/workflows/' + workflow
        if source_file(api, path, sha) != (root / path).read_bytes():
            raise ValueError('candidate changed trusted Windows workflow: ' + workflow)
    pubspec = source_file(api, 'pubspec.yaml', sha).decode()
    match = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$', pubspec, re.M)
    if not match or match[1].split('+')[0] != tag[1:]:
        raise ValueError('Windows source version differs')
    sboms = {kind: source_file(api, 'sbom/ocideck.' + kind + '.json', sha) for kind in ('cdx', 'spdx')}
    cdx = json.loads(sboms['cdx'], object_pairs_hook=no_duplicates)
    spdx = json.loads(sboms['spdx'], object_pairs_hook=no_duplicates)
    if (cdx.get('metadata', {}).get('component', {}).get('version') != match[1]
            or not any(package.get('name') == 'ocideck' and package.get('versionInfo') == match[1] for package in spdx.get('packages', []))):
        raise ValueError('Windows SBOM version differs from exact source')
    return sboms


def latest(api, workflow, sha, ref):
    runs = pages(api, '/actions/workflows/' + workflow + '/runs?branch=' + quote(ref, safe='') + '&event=workflow_dispatch', 'workflow_runs')
    selected = []
    seen = set()
    for run in runs:
        if (not isinstance(run, dict) or type(run.get('id')) is not int or run['id'] <= 0 or run['id'] in seen
                or run.get('head_sha') != sha or run.get('head_branch') != ref or run.get('event') != 'workflow_dispatch'
                or run.get('path') != '.github/workflows/' + workflow):
            raise ValueError('Windows run identity differs')
        title = 'Windows candidate ' + ref.split('-candidate-', 1)[1].rsplit('-', 1)[0]
        if workflow == 'release.yml' and not re.fullmatch(re.escape(title) + r'(?: \[operation:[A-Za-z0-9_-]{1,80}\])?', str(run.get('display_title', ''))):
            raise ValueError('Windows release run is not a candidate')
        seen.add(run['id']); selected.append(run)
    return max(selected, key=lambda run: run['id']) if selected else None


def successful(api, run):
    if run is None or run.get('status') != 'completed' or run.get('conclusion') != 'success':
        raise ValueError('latest exact-source Windows run is not terminal success')
    jobs = pages(api, '/actions/runs/' + str(run['id']) + '/jobs', 'jobs')
    required = 'Build Windows' if run['path'].endswith('/release.yml') else 'Test (windows-2022)'
    if (not jobs or sum(job.get('name') == required for job in jobs) != 1
            or not any(job.get('name') == required and job.get('status') == 'completed' and job.get('conclusion') == 'success' for job in jobs)
            or any(job.get('status') != 'completed' or (job.get('conclusion') != 'success' and not (job.get('name') == 'Tag controleren zonder nieuwe build' and job.get('conclusion') == 'skipped')) for job in jobs)):
        raise ValueError('Windows native/build/suite jobs are not terminal successful')


def verify_cohort(dist, tag, sha, run_id):
    version = tag[1:]
    cohort = json.loads((dist / f'ocideck-windows-cohort-{version}.json').read_text(), object_pairs_hook=no_duplicates)
    if (not isinstance(cohort, dict) or set(cohort) != {'tag_commit', 'run_id', 'sha256'} or cohort['tag_commit'] != sha
            or type(cohort['run_id']) is not int or cohort['run_id'] != run_id
            or not isinstance(cohort['sha256'], dict) or set(cohort['sha256']) != {'zip', 'installer'}):
        raise ValueError('Windows cohort identity differs')
    for key, name in [('zip', f'ocideck-windows-x64-{version}.zip'), ('installer', f'ocideck-windows-x64-setup-{version}.exe')]:
        if cohort['sha256'][key] != file_hash(dist / name):
            raise ValueError('Windows cohort bytes differ')


def verify(api, root, dist, tag, sha, ref):
    sboms = source_contract(api, root, tag, sha, ref)
    for kind, content in sboms.items():
        path = dist / f'ocideck-{tag[1:]}.{kind}.json'
        if path.is_symlink() or path.read_bytes() != content:
            raise ValueError('Windows SBOM bytes differ from frozen source')
    runs = {workflow: latest(api, workflow, sha, ref) for workflow in WORKFLOWS}
    for run in runs.values():
        successful(api, run)
    verify_cohort(dist, tag, sha, runs['release.yml']['id'])
    return {workflow: run['id'] for workflow, run in runs.items()}


def owned_run(run, operation_id):
    return bool(run and run.get('display_title', '').endswith(' [operation:' + operation_id + ']'))


def owned_runs(api, sha, ref, operation_id):
    match = re.fullmatch(r'codex/release-candidate-(v[0-9]+\.[0-9]+\.[0-9]+)-' + re.escape(sha), ref)
    if not match or not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', operation_id):
        raise ValueError('invalid Windows cancellation identity')
    identity(match[1], sha, 'windows')
    result, seen = [], set()
    for workflow in WORKFLOWS:
        for run in pages(api, '/actions/workflows/' + workflow + '/runs?branch=' + quote(ref, safe='') + '&event=workflow_dispatch', 'workflow_runs'):
            if (run.get('head_sha') == sha and run.get('head_branch') == ref and run.get('event') == 'workflow_dispatch'
                    and run.get('path') == '.github/workflows/' + workflow and owned_run(run, operation_id)
                    and type(run.get('id')) is int and run['id'] > 0):
                if run['id'] in seen:
                    raise ValueError('duplicate owned Windows run')
                seen.add(run['id'])
                result.append(run)
    return result


def operation_state(state, sha, ref, operation_id):
    if state.is_symlink() or not state.is_file() or state.stat().st_size > 65536:
        raise ValueError('unsafe Windows operation journal')
    saved = json.loads(state.read_text(), object_pairs_hook=no_duplicates)
    fields = {'schema', 'operation_id', 'tag', 'sha', 'ref', 'dispatch_intents', 'closed', 'forge_run_id', 'controller_sha', 'selected_runs'}
    if (not isinstance(saved, dict) or set(saved) - {'outcome'} != fields or type(saved['schema']) is not int
            or saved['schema'] != 1 or type(saved['forge_run_id']) is not int or saved['forge_run_id'] < 0
            or not isinstance(saved['controller_sha'], str)
            or (saved['controller_sha'] != '' and (not re.fullmatch(r'[0-9a-f]{40}', saved['controller_sha']) or saved['controller_sha'] == '0' * 40))
            or saved['sha'] != sha or saved['ref'] != ref
            or saved['operation_id'] != operation_id or type(saved['closed']) is not bool
            or ref != 'codex/release-candidate-' + saved['tag'] + '-' + sha
            or not isinstance(saved['dispatch_intents'], list)
            or not isinstance(saved['selected_runs'], dict)
            or not set(saved['selected_runs']).issubset(WORKFLOWS)
            or any(type(value) is not int or value <= 0 for value in saved['selected_runs'].values())
            or any(not isinstance(name, str) or name not in WORKFLOWS for name in saved['dispatch_intents'])
            or len(set(saved['dispatch_intents'])) != len(saved['dispatch_intents'])):
        raise ValueError('Windows operation journal identity differs')
    if saved.get('outcome', 'completed' if saved['closed'] else 'pending') not in ('pending', 'completed', 'failed'):
        raise ValueError('invalid Windows operation outcome')
    return saved


def owned_status(api, sha, ref, operation_id, state=None, forge_run_id=None, controller_sha=None):
    runs = owned_runs(api, sha, ref, operation_id)
    saved = operation_state(state, sha, ref, operation_id) if state else None
    bound = bool(saved and (saved['closed'] or (saved.get('outcome') == 'pending' and set(saved['selected_runs']) == set(WORKFLOWS)))
                 and forge_run_id and controller_sha
                 and saved['forge_run_id'] == forge_run_id and saved['controller_sha'] == controller_sha)
    expected = set(saved['dispatch_intents']) if bound else set(WORKFLOWS)
    visible = {run['path'].rsplit('/', 1)[1] for run in runs}
    unknown = not expected.issubset(visible)
    selected = saved['selected_runs'] if bound else {}
    selected_verified = bool(bound and saved['closed'] and saved.get('outcome', 'completed') == 'completed'
                             and set(selected) == set(WORKFLOWS))
    if selected_verified:
        try:
            for run in selected_runs(api, sha, ref, saved).values():
                successful(api, run)
        except ValueError:
            selected_verified = False
    return {'operation_id': operation_id, 'terminal': not unknown and all(run.get('status') == 'completed' for run in runs),
            'unknown': unknown,
            'selected_verified': selected_verified,
            'selected_runs': selected if bound else {},
            'runs': [{'id': run['id'], 'status': run.get('status'), 'conclusion': run.get('conclusion')} for run in runs]}


def cancel_owned(api, sha, ref, operation_id, wait=False, state=None, forge_run_id=None, controller_sha=None):
    deadline = time.monotonic() + (15 * 60 if wait else 0)
    attempted = set()
    previous_deadline = getattr(api, 'deadline', None)
    if wait:
        api.deadline = deadline
    try:
        while True:
            if wait and time.monotonic() >= deadline:
                raise TimeoutError('Windows cancellation deadline reached')
            for run in owned_runs(api, sha, ref, operation_id):
                if wait and time.monotonic() >= deadline:
                    raise TimeoutError('Windows cancellation deadline reached')
                if run.get('status') != 'completed' and run['id'] not in attempted:
                    attempted.add(run['id'])
                    try:
                        api.data('/actions/runs/' + str(run['id']) + '/cancel', {})
                    except ValueError:
                        # A lost response is reconciled by GET; never repeat the mutation.
                        pass
            result = owned_status(api, sha, ref, operation_id, state, forge_run_id, controller_sha)
            if result['terminal'] or not wait:
                return result
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Windows cancellation deadline reached')
            time.sleep(min(10, remaining))
    except (TimeoutError, subprocess.TimeoutExpired):
        return {'operation_id': operation_id, 'terminal': False, 'unknown': True,
                'reason': 'Windows cancellation deadline reached', 'runs': []}
    finally:
        if previous_deadline is None:
            if hasattr(api, 'deadline'):
                del api.deadline
        else:
            api.deadline = previous_deadline


def fetch(api, root, dist, tag, sha, ref, operation_id, state, forge_run_id=0, controller_sha='', collect=False, previous_run_id=None, attempt_id=None):
    if type(forge_run_id) is not int or forge_run_id < 0 or (controller_sha and (not re.fullmatch(r'[0-9a-f]{40}', controller_sha) or controller_sha == '0' * 40)):
        raise ValueError('invalid Forge operation provenance')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', operation_id):
        raise ValueError('Windows candidate requires an operation ID')
    api.deadline = time.monotonic() + POLL_SECONDS
    try:
        sboms = source_contract(api, root, tag, sha, ref)
    except BaseException:
        del api.deadline
        raise
    if dist.exists():
        raise ValueError('Windows candidate dist must not exist')
    state = state.absolute()
    wanted = {'schema': 1, 'operation_id': operation_id, 'tag': tag, 'sha': sha, 'ref': ref, 'dispatch_intents': [], 'closed': False, 'forge_run_id': forge_run_id, 'controller_sha': controller_sha, 'selected_runs': {}}
    with locked(state):
        if collect and not state.exists():
            from release_channel_controller import Forgejo, continuation_state
            previous = json.loads(continuation_state(Forgejo(), dict(operation_id=operation_id, tag=tag,
                source=sha, controller=controller_sha, frozen_ref=ref, channel='windows'), previous_run_id,
                forge_run_id, attempt_id), object_pairs_hook=no_duplicates)
            if set(previous['selected_runs']) != set(WORKFLOWS):
                raise ValueError('Windows dispatch remains unknown; exact upstream IDs missing')
            previous.update(forge_run_id=forge_run_id, closed=False, outcome='pending')
            atomic_write(state, previous)
        if state.exists() or state.is_symlink():
            if state.is_symlink() or not state.is_file() or state.stat().st_size > 65536:
                raise ValueError('unsafe Windows operation journal')
            saved = operation_state(state, sha, ref, operation_id)
            if saved['forge_run_id'] != forge_run_id or saved['controller_sha'] != controller_sha:
                raise ValueError('Windows operation provenance differs')
            if saved['closed']:
                raise ValueError('Windows operation is closed; use a new explicit operation')
        else:
            if collect:
                raise ValueError('collect requires authenticated previous operation state')
            saved = wanted
            atomic_write(state, saved)
        try:
            result = fetch_locked(api, root, dist, tag, sha, ref, operation_id, state, saved, sboms, collect)
            saved['closed'] = result is not None
            saved['outcome'] = 'completed' if saved['closed'] else 'pending'
            atomic_write(state, saved)
            return result if result is not None else {'status': 'pending', 'selected_runs': saved['selected_runs']}
        except (TimeoutError, subprocess.TimeoutExpired):
            saved.update(closed=False, outcome='pending')
            atomic_write(state, saved)
            return {'status': 'pending', 'selected_runs': saved['selected_runs']}
        except BaseException:
            # SIGKILL/host loss cannot run this handler; the parent reconciles the same marker from Forge event inputs.
            saved['closed'] = True
            saved['outcome'] = 'failed'
            atomic_write(state, saved)
            if not collect:
                try:
                    cancel_owned(api, sha, ref, operation_id, state=state)
                except (ValueError, OSError, KeyError, TypeError):
                    pass
            raise
        finally:
            if hasattr(api, 'deadline'):
                del api.deadline


def selected_runs(api, sha, ref, saved, allow_missing=False):
    result = {}
    for workflow in WORKFLOWS:
        values = pages(api, '/actions/workflows/' + workflow + '/runs?branch=' + quote(ref, safe='') + '&event=workflow_dispatch', 'workflow_runs')
        chosen = saved['selected_runs'].get(workflow)
        matches = [run for run in values if (run.get('id') == chosen if chosen else owned_run(run, saved['operation_id']))]
        if not matches and allow_missing:
            result[workflow] = None
            continue
        if len(matches) != 1:
            raise ValueError('Windows selected run unavailable or ambiguous; no dispatch allowed')
        run = matches[0]
        if (type(run.get('id')) is not int or run['id'] <= 0 or run.get('head_sha') != sha
                or run.get('head_branch') != ref or run.get('event') != 'workflow_dispatch'
                or run.get('path') != '.github/workflows/' + workflow):
            raise ValueError('Windows selected run identity differs')
        title = 'Windows candidate ' + saved['tag']
        if workflow == 'release.yml' and not re.fullmatch(re.escape(title) + r'(?: \[operation:[A-Za-z0-9_-]{1,80}\])?', str(run.get('display_title', ''))):
            raise ValueError('Windows selected release run is not a candidate')
        result[workflow] = run
    return result


def fetch_locked(api, root, dist, tag, sha, ref, operation_id, state, saved, sboms, collect=False):
    for workflow in WORKFLOWS:
        if collect:
            if workflow not in saved['selected_runs']:
                raise ValueError('collect requires exact existing Windows IDs')
            continue
        run = latest(api, workflow, sha, ref)
        if workflow in saved['dispatch_intents']:
            matches = [value for value in owned_runs(api, sha, ref, operation_id) if value['path'] == '.github/workflows/' + workflow]
            run = max(matches, key=lambda value: value['id']) if matches else None
        if run is not None and run.get('status') == 'completed' and run.get('conclusion') != 'success':
            raise ValueError('existing Windows candidate failed; diagnose and explicitly rerun its GitHub run')
        if run is None:
            if workflow in saved['dispatch_intents']:
                raise ValueError('Windows dispatch outcome unknown; reconcile operation ID before any new dispatch')
            saved['dispatch_intents'].append(workflow)
            atomic_write(state, saved)
            inputs = {'mode': 'candidate', 'version': tag, 'commit_sha': sha} if workflow == 'release.yml' else {}
            inputs['operation_id'] = operation_id
            api.data('/actions/workflows/' + workflow + '/dispatches', {'ref': ref, 'inputs': inputs})
        if run is not None:
            saved['selected_runs'][workflow] = run['id']
            atomic_write(state, saved)
    try:
        while True:
            runs = selected_runs(api, sha, ref, saved, allow_missing=True)
            saved['selected_runs'].update({workflow: run['id'] for workflow, run in runs.items() if run is not None})
            atomic_write(state, saved)
            if any(run and run.get('status') == 'completed' and run.get('conclusion') != 'success' for run in runs.values()):
                raise ValueError('Windows candidate failed; no automatic rerun')
            if all(run and run.get('status') == 'completed' for run in runs.values()):
                break
            remaining = api.deadline - time.monotonic()
            if remaining <= 0:
                return None
            time.sleep(min(30, remaining))
    except (TimeoutError, subprocess.TimeoutExpired):
        return None
    api.deadline = time.monotonic() + COLLECT_SECONDS
    for run in runs.values():
        successful(api, run)
    saved['selected_runs'] = {workflow: run['id'] for workflow, run in runs.items()}
    atomic_write(state, saved)
    artifacts = pages(api, '/actions/runs/' + str(runs['release.yml']['id']) + '/artifacts', 'artifacts')
    artifacts = [artifact for artifact in artifacts if artifact.get('name') == 'ocideck-windows-cohort' and artifact.get('expired') is False]
    if len(artifacts) != 1 or type(artifacts[0].get('id')) is not int or artifacts[0]['id'] <= 0:
        raise ValueError('missing or ambiguous Windows cohort artifact')
    version = tag[1:]
    names = {f'ocideck-windows-x64-{version}.zip', f'ocideck-windows-x64-setup-{version}.exe', f'ocideck-windows-cohort-{version}.json'}
    with tempfile.TemporaryDirectory(prefix='windows-cohort-') as directory:
        staging = Path(directory)
        archive = staging / 'artifact.zip'
        api.download(artifacts[0]['id'], archive)
        with zipfile.ZipFile(archive) as zipped:
            entries = zipped.infolist()
            if (len(entries) != len(names) or {entry.filename for entry in entries} != names
                    or sum(entry.file_size for entry in entries) > MAX_ARCHIVE
                    or any(entry.is_dir() or stat.S_IFMT(entry.external_attr >> 16) not in (0, stat.S_IFREG) for entry in entries)):
                raise ValueError('unsafe Windows artifact members')
            for entry in entries:
                with zipped.open(entry) as source, (staging / entry.filename).open('xb') as output:
                    shutil.copyfileobj(source, output)
        verify_cohort(staging, tag, sha, runs['release.yml']['id'])
        dist.mkdir(parents=True)
        for name in names:
            shutil.copyfile(staging / name, dist / name)
        for kind, content in sboms.items():
            (dist / f'ocideck-{version}.{kind}.json').write_bytes(content)
    verify_cohort(dist, tag, sha, runs['release.yml']['id'])
    return saved['selected_runs']


def stop(_number, _frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('fetch', 'collect', 'verify', 'cancel', 'status'))
    for name in ('tag', 'sha', 'ref'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--root', type=Path)
    parser.add_argument('--dist', type=Path)
    parser.add_argument('--operation-id')
    parser.add_argument('--state', type=Path)
    parser.add_argument('--forge-run-id', type=int)
    parser.add_argument('--controller-sha')
    parser.add_argument('--previous-run-id', type=int)
    parser.add_argument('--attempt-id')
    parser.add_argument('--wait-terminal', action='store_true')
    args = parser.parse_args()
    try:
        api = GitHub()
        if args.mode in ('cancel', 'status'):
            if args.operation_id is None:
                raise ValueError('cancel requires operation-id')
            identity(args.tag, args.sha, 'windows')
            if args.ref != 'codex/release-candidate-' + args.tag + '-' + args.sha:
                raise ValueError('cancellation ref differs')
            result = (cancel_owned(api, args.sha, args.ref, args.operation_id, wait=args.wait_terminal, state=args.state, forge_run_id=args.forge_run_id, controller_sha=args.controller_sha)
                      if args.mode == 'cancel' else owned_status(api, args.sha, args.ref, args.operation_id, args.state, args.forge_run_id, args.controller_sha))
            print(json.dumps(result, sort_keys=True))
            return 0 if result['terminal'] else 2
        if args.root is None or args.dist is None:
            raise ValueError('candidate verification requires root and dist')
        if args.mode in ('fetch', 'collect'):
            if args.operation_id is None or args.state is None:
                raise ValueError('fetch requires operation-id and durable state path')
            signal.signal(signal.SIGTERM, stop)
            result = fetch(api, args.root, args.dist, args.tag, args.sha, args.ref, args.operation_id, args.state,
                           args.forge_run_id or 0, args.controller_sha or '', args.mode == 'collect', args.previous_run_id, args.attempt_id)
        else:
            result = verify(api, args.root, args.dist, args.tag, args.sha, args.ref)
        print(json.dumps(result, sort_keys=True))
        return 0
    except KeyboardInterrupt:
        print('Windows candidate stopped; owned run cancellation was requested; reconcile terminal status', file=sys.stderr)
        return 130
    except (ValueError, OSError, TypeError, KeyError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
