#!/usr/bin/env python3
"""Operate one independent release channel; uncertain dispatches are never retried."""
import argparse
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time
import zipfile
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import uuid4

import release_channel
import release_channel_control
import release_journal

API = 'https://pawprint.vigilis.online/api/v1/repos/LibreKAT/Ocideck'
WORKFLOW = 'release-channel.yml'
TERMINAL = {'success', 'failure', 'cancelled', 'skipped', 'error'}
OPERATION_RE = re.compile(r'[A-Za-z0-9_-]{1,80}\Z')


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        raise ValueError('Forgejo API redirect refused')


def token():
    value = os.environ.get('FORGEJO_TOKEN')
    if not value and sys.platform == 'darwin':
        result = subprocess.run(['security', 'find-generic-password', '-s', 'forgejo-pawprint-api', '-w'],
                                capture_output=True, text=True, timeout=15)
        if result.returncode == 0:
            value = result.stdout.strip()
    if not value or any(char in value for char in '\r\n'):
        raise ValueError('Forgejo token unavailable')
    return value


class Forgejo:
    def __init__(self, base=API):
        self.base = base.rstrip('/')
        parsed = urlsplit(self.base)
        if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError('Forgejo API must be credential-free HTTPS')
        self._token = token()
        self._opener = build_opener(NoRedirect)

    def request(self, path, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        request = Request(self.base + path, data=data,
                          headers={'Authorization': 'token ' + self._token,
                                   'Content-Type': 'application/json'},
                          method='GET' if payload is None else 'POST')
        try:
            with self._opener.open(request, timeout=30) as response:
                if response.status not in (200, 201, 202, 204):
                    raise ValueError('unexpected Forgejo HTTP status')
                body = response.read(2 * 1024 * 1024 + 1)
        except HTTPError as error:
            raise ValueError('Forgejo HTTP ' + str(error.code)) from None
        if len(body) > 2 * 1024 * 1024:
            raise ValueError('Forgejo response too large')
        return json.loads(body, object_pairs_hook=release_channel.no_duplicates) if body else None

    def get(self, path):
        return self.request(path)

    def post(self, path, payload):
        return self.request(path, payload)

    def artifact(self, artifact_id):
        if type(artifact_id) is not int or artifact_id <= 0:
            raise ValueError('invalid Forgejo artifact ID')
        request = Request(self.base + f'/actions/artifacts/{artifact_id}/zip',
                          headers={'Authorization': 'token ' + self._token})
        with self._opener.open(request, timeout=30) as response:
            if response.status != 200:
                raise ValueError('Windows journal artifact download failed')
            data = response.read(131073)
        if len(data) > 131072:
            raise ValueError('Windows journal archive too large')
        return data


def windows_state(api, wanted, run_id):
    artifacts = api.get('/actions/runs/' + str(run_id) + '/artifacts')
    name = 'windows-operation-' + wanted['operation_id']
    matches = [value for value in artifacts if isinstance(value, dict)
               and value.get('name') == name and value.get('expired') is False]
    if len(matches) != 1:
        raise ValueError('exact Windows operation artifact unavailable')
    archive = api.artifact(matches[0].get('id'))
    with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
        entries = zipped.infolist()
        if (len(entries) != 1 or entries[0].filename != 'windows-operation.json'
                or entries[0].is_dir() or entries[0].file_size > 65536
                or stat.S_IFMT(entries[0].external_attr >> 16) not in (0, stat.S_IFREG)):
            raise ValueError('unsafe Windows operation artifact')
        content = zipped.read(entries[0])
    state = json.loads(content, object_pairs_hook=release_channel.no_duplicates)
    if (not isinstance(state, dict) or state.get('operation_id') != wanted['operation_id']
            or state.get('tag') != wanted['tag'] or state.get('sha') != wanted['source']
            or state.get('ref') != wanted['frozen_ref'] or state.get('forge_run_id') != run_id
            or state.get('controller_sha') != wanted['controller'] or state.get('closed') is not True):
        raise ValueError('Windows operation provenance differs')
    return content


def identity(args):
    release_channel.identity(args.tag, args.sha, args.channel)
    release_channel.identity(args.tag, args.controller_sha, args.channel)
    if not OPERATION_RE.fullmatch(getattr(args, 'operation_id', '') or ''):
        raise ValueError('invalid operation ID')
    return {'schema': 1, 'operation_id': args.operation_id, 'tag': args.tag,
            'source': args.sha, 'controller': args.controller_sha, 'channel': args.channel,
            'frozen_ref': f'codex/release-candidate-{args.tag}-{args.sha}'}


def operation_path(args):
    return args.state_dir / args.tag / (args.channel + '-operation.json')


def read_operation(args):
    path = operation_path(args)
    if path.is_symlink() or not path.is_file():
        raise ValueError('no saved operation; start must reserve one first')
    data = json.loads(path.read_text(), object_pairs_hook=release_channel.no_duplicates)
    if data != identity(args):
        raise ValueError('saved operation identity differs')
    return data


def reserve(args):
    path = operation_path(args)
    path.parent.mkdir(parents=True, exist_ok=True)
    with release_journal.locked(path):
        if path.exists() or path.is_symlink():
            raise ValueError('operation already reserved; use hervat, never start again')
        data = identity(args)
        release_channel.immutable_write(path, release_channel.encoded(data))
        journal = path.parent / (args.channel + '.json')
        from types import SimpleNamespace
        release_journal.initialize(SimpleNamespace(journal=journal, tag=args.tag, sha=args.sha,
            channel=args.channel, workflow=Path(__file__).resolve().parent.parent / '.forgejo/workflows/release-channel.yml'))
        release_journal.record(SimpleNamespace(journal=journal, phase='dispatch', state='started', evidence=[path]))
    return data


def payload(run):
    raw = run.get('event_payload')
    if isinstance(raw, str):
        raw = json.loads(raw, object_pairs_hook=release_channel.no_duplicates)
    return raw if isinstance(raw, dict) else {}


def run_matches(run, wanted):
    event = payload(run)
    inputs = event.get('inputs')
    if not isinstance(inputs, dict):
        return False
    return (event.get('ref') in ('main', 'refs/heads/main')
            and event.get('workflow') in (None, WORKFLOW, '.forgejo/workflows/' + WORKFLOW)
            and inputs.get('operation_id') == wanted['operation_id']
            and inputs.get('tag') == wanted['tag']
            and inputs.get('source_sha') == wanted['source']
            and inputs.get('frozen_ref') == wanted['frozen_ref']
            and inputs.get('channel') == wanted['channel'])


def runs(api, wanted, allow_controller_drift=False):
    found = []
    seen = set()
    for page in range(1, 51):
        response = api.get(f'/actions/runs?limit=100&page={page}&workflow_id={WORKFLOW}')
        values = response.get('workflow_runs') if isinstance(response, dict) else None
        if not isinstance(values, list) or len(values) > 100:
            raise ValueError('invalid Forgejo run listing')
        for summary in values:
            run_id = summary.get('id') if isinstance(summary, dict) else None
            if type(run_id) is not int or run_id <= 0 or run_id in seen:
                raise ValueError('invalid or duplicate Forgejo run ID')
            seen.add(run_id)
            detail = api.get('/actions/runs/' + str(run_id))
            if not isinstance(detail, dict) or detail.get('id') != run_id:
                raise ValueError('Forgejo run readback differs')
            event = payload(detail)
            inputs = event.get('inputs')
            if isinstance(inputs, dict) and inputs.get('operation_id') == wanted['operation_id'] and not run_matches(detail, wanted):
                raise ValueError('operation ID reused with conflicting release identity')
            if run_matches(detail, wanted):
                if (detail.get('workflow_id') not in (WORKFLOW, '.forgejo/workflows/' + WORKFLOW)
                        or (not allow_controller_drift and detail.get('commit_sha') != wanted['controller'])
                        or detail.get('prettyref') not in ('main', 'refs/heads/main')
                        or detail.get('trigger_event') != 'workflow_dispatch'):
                    raise ValueError('operation ID belongs to a different run identity')
                found.append(detail)
        if len(values) < 100:
            return found
    raise ValueError('Forgejo run history exceeds inspection bound')


def jobs(api, run):
    values = api.get('/actions/runs/' + str(run['id']) + '/jobs')
    if not isinstance(values, list):
        raise ValueError('invalid Forgejo jobs response')
    return values


def snapshot(api, wanted):
    found = runs(api, wanted)
    entries = []
    for run in found:
        work = jobs(api, run)
        first_error = next(({'job': job.get('name'), 'status': job.get('status'),
                             'started_at': job.get('started_at'), 'completed_at': job.get('completed_at')}
                            for job in work if job.get('status') in {'failure', 'error', 'cancelled'}), None)
        entries.append({'id': run['id'], 'status': run.get('status'),
                        'created_at': run.get('created_at'), 'updated_at': run.get('updated_at'),
                        'jobs': work, 'first_error': first_error})
    return {'operation_id': wanted['operation_id'], 'runs': entries,
            'build_metadata': 'success' if len(entries) == 1 and entries[0]['status'] == 'success' else 'unproven',
            'artifact_bytes': 'unverified', 'publication': 'unverified'}


def start(args, api):
    main = api.get('/git/refs/heads/main')
    if (not isinstance(main, dict) or main.get('ref') != 'refs/heads/main'
            or main.get('object', {}).get('sha') != args.controller_sha):
        raise ValueError('main differs from requested controller SHA; dispatch not attempted')
    # The durable file and journal are fsynced before the one external POST.
    wanted = reserve(args)
    print(json.dumps({'operation_id': args.operation_id, 'state': 'reserved'}, sort_keys=True), flush=True)
    if runs(api, wanted):
        raise ValueError('operation already reached Forgejo; use hervat')
    main = api.get('/git/refs/heads/main')
    if (not isinstance(main, dict) or main.get('ref') != 'refs/heads/main'
            or main.get('object', {}).get('sha') != args.controller_sha):
        raise ValueError('main moved from reserved controller SHA; dispatch not attempted')
    api.post('/actions/workflows/' + WORKFLOW + '/dispatches',
             {'ref': 'main', 'inputs': {'tag': args.tag, 'source_sha': args.sha,
                'frozen_ref': wanted['frozen_ref'], 'channel': args.channel,
                'operation_id': args.operation_id}})
    return snapshot(api, wanted)


def status(args, api):
    wanted = read_operation(args)
    result = snapshot(api, wanted)
    journal = operation_path(args).parent / (args.channel + '.json')
    if not journal.is_file() or journal.is_symlink():
        raise ValueError('saved journal missing')
    result['history'] = release_journal.read(journal)['events']
    result['dispatch'] = 'unknown' if not result['runs'] else 'found'
    publication = next((event for event in reversed(result['history'])
                        if event['phase'] == 'publish'), None)
    if publication is not None:
        result['publication'] = ('recorded_' + publication['state']
                                 + '_public_bytes_unverified')
    if args.channel == 'windows':
        helper = Path(__file__).with_name('release_windows_candidate.py')
        if helper.is_file():
            command = [sys.executable, str(helper), 'status', '--tag', args.tag,
                       '--sha', args.sha, '--ref', wanted['frozen_ref'],
                       '--operation-id', args.operation_id, '--controller-sha', args.controller_sha]
            try:
                if len(result['runs']) != 1 or result['runs'][0]['status'] not in TERMINAL:
                    raise ValueError('Forgejo worker is not terminal')
                run_id = result['runs'][0]['id']
                content = windows_state(api, wanted, run_id)
                with tempfile.TemporaryDirectory(prefix='windows-operation-') as directory:
                    state = Path(directory) / 'windows-operation.json'
                    state.write_bytes(content)
                    response = subprocess.run(command + ['--forge-run-id', str(run_id),
                        '--state', str(state)], capture_output=True, text=True, timeout=120)
                result['github'] = json.loads(response.stdout, object_pairs_hook=release_channel.no_duplicates)
                if response.returncode or not isinstance(result['github'], dict):
                    result['github'] = {'status': 'unknown'}
            except (ValueError, TypeError, OSError, zipfile.BadZipFile) as error:
                result['github'] = {'status': 'unknown', 'reason': str(error)}
        else:
            result['github'] = {'status': 'unknown', 'reason': 'Windows helper unavailable'}
    return result


def hervat(args, api):
    result = status(args, api)
    if not result['runs']:
        raise ValueError('dispatch outcome unknown; never redispatch this operation ID')
    if len(result['runs']) != 1:
        raise ValueError('multiple runs for one operation; inspect before resuming')
    save_observation(args, result)
    return result


def save_observation(args, result):
    """Keep a checksum-bound snapshot of exact run/jobs and its first error."""
    from hashlib import sha256
    from types import SimpleNamespace
    journal = operation_path(args).parent / (args.channel + '.json')
    run = result['runs'][0]
    content = release_channel.encoded(run)
    proof = journal.parent / f"{args.channel}-run-{run['id']}-{sha256(content).hexdigest()[:16]}.json"
    release_channel.immutable_write(proof, content)
    current = release_journal.read(journal)
    last_dispatch = next((e for e in reversed(current['events']) if e['phase'] == 'dispatch'), None)
    if last_dispatch and last_dispatch['state'] == 'started':
        release_journal.record(SimpleNamespace(journal=journal, phase='dispatch', state='completed', evidence=[proof]))
    current = release_journal.read(journal)
    last_build = next((e for e in reversed(current['events']) if e['phase'] == 'build'), None)
    if last_build is None:
        release_journal.record(SimpleNamespace(journal=journal, phase='build', state='started', evidence=[proof]))
        last_build = {'state': 'started'}
    if last_build['state'] == 'started' and run['status'] in TERMINAL:
        state = 'completed' if run['status'] == 'success' else 'cancelled' if run['status'] == 'cancelled' else 'failed'
        release_journal.record(SimpleNamespace(journal=journal, phase='build', state=state, evidence=[proof]))


def stop(args, api):
    wanted = read_operation(args)
    found = runs(api, wanted, allow_controller_drift=True)
    if not found:
        raise ValueError('dispatch outcome unknown; no run is not proof of absence')
    for run in found:
        if run.get('status') not in TERMINAL:
            api.post('/actions/runs/' + str(run['id']) + '/cancel', {})
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        latest = runs(api, wanted, allow_controller_drift=True)
        if {r['id'] for r in latest} != {r['id'] for r in found}:
            raise ValueError('new matching run appeared during stop; inspect all owned runs')
        if all(run.get('status') in TERMINAL for run in latest):
            result = snapshot(api, wanted) if latest[0].get('commit_sha') == wanted['controller'] else {
                'operation_id': wanted['operation_id'], 'runs': [
                    {'id': run['id'], 'status': run.get('status'), 'controller_sha': run.get('commit_sha')}
                    for run in latest], 'build_metadata': 'unproven',
                'artifact_bytes': 'unverified', 'publication': 'unverified'}
            if len(result['runs']) != 1:
                raise ValueError('multiple runs for one operation; stop cannot prove one owner')
            if latest[0].get('commit_sha') == wanted['controller']:
                save_observation(args, result)
            # Only a terminal Forgejo worker cannot dispatch more dependent jobs.
            if args.channel == 'windows':
                helper = Path(__file__).with_name('release_windows_candidate.py')
                if not helper.is_file():
                    raise ValueError('Windows ownership helper missing; GitHub state remains unknown')
                command = [sys.executable, str(helper), 'cancel', '--tag', args.tag, '--sha', args.sha,
                           '--ref', wanted['frozen_ref'], '--operation-id', args.operation_id,
                           '--forge-run-id', str(latest[0]['id']), '--controller-sha', args.controller_sha,
                           '--wait-terminal']
                try:
                    content = windows_state(api, wanted, latest[0]['id'])
                except (ValueError, OSError, zipfile.BadZipFile) as error:
                    # Still request cancellation of visible owned GH runs. Without
                    # the authenticated journal, absence cannot prove completion.
                    subprocess.run(command, timeout=960)
                    raise ValueError('Windows journal unavailable; stop remains unknown: ' + str(error)) from error
                with tempfile.TemporaryDirectory(prefix='windows-operation-') as directory:
                    state = Path(directory) / 'windows-operation.json'
                    state.write_bytes(content)
                    if subprocess.run(command + ['--state', str(state)], timeout=960).returncode:
                        raise ValueError('owned GitHub runs not confirmed terminal; stop remains blocked')
            return result
        time.sleep(5)
    raise ValueError('cancel requested but terminal Forgejo state not confirmed')


def publish(args, api):
    result = status(args, api)
    if len(result['runs']) != 1 or result['runs'][0]['status'] != 'success' or str(result['runs'][0]['id']) != str(args.run_id):
        raise ValueError('exact operation build is not terminal green')
    if args.channel == 'windows':
        github = result.get('github', {})
        if (github.get('unknown') is not False or github.get('terminal') is not True
                or github.get('selected_verified') is not True
                or set(github.get('selected_runs', {})) != {'release.yml', 'windows-test-check.yml'}):
            raise ValueError('dependent Windows runs are not proven terminal green')
    if not getattr(args, 'dist', None) or not getattr(args, 'evidence', None):
        raise ValueError('signed candidate files are required; ready for signing, not publication')
    release_channel_control.select_candidate_paths(args, args.state_dir.resolve() / args.tag)
    manifest = args.evidence / ('channel-manifest-' + args.channel + '.json')
    sums = args.evidence / ('SHA256SUMS.' + args.channel)
    if any(not path.is_file() or path.is_symlink() for path in (manifest, sums, Path(str(manifest) + '.minisig'), Path(str(sums) + '.minisig'))):
        raise ValueError('signed evidence missing; ready for signing, not publication')
    command = [sys.executable, str(Path(__file__).with_name('release_channel_control.py')),
        '--state-dir', str(args.state_dir), '--tag', args.tag, '--sha', args.sha,
        '--controller-sha', args.controller_sha, '--channel', args.channel,
        '--run-id', str(args.run_id), '--release-id', str(args.release_id),
        '--dist', str(args.dist), '--evidence', str(args.evidence)]
    if args.create_release:
        command.append('--create-release')
    return subprocess.run(command, timeout=3600).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'start', 'status', 'stop', 'hervat', 'publish'])
    parser.add_argument('--state-dir', type=Path, required=True)
    for name in ('tag', 'sha', 'controller-sha', 'channel'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--operation-id')
    parser.add_argument('--run-id')
    parser.add_argument('--release-id', default='auto')
    parser.add_argument('--create-release', action='store_true')
    parser.add_argument('--dist', type=Path)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    if args.command == 'start':
        args.operation_id = args.operation_id or uuid4().hex
    elif args.command != 'plan' and not args.operation_id:
        path = operation_path(args)
        if path.is_symlink() or not path.is_file():
            parser.error('saved operation ID missing')
        args.operation_id = json.loads(path.read_text(), object_pairs_hook=release_channel.no_duplicates).get('operation_id')
    try:
        if args.command == 'plan':
            args.operation_id = args.operation_id or 'planned'
            result = {'identity': identity(args), 'action': 'read-only plan; no operation reserved'}
        elif args.command == 'publish':
            return publish(args, Forgejo())
        else:
            api = Forgejo()
            result = {'start': start, 'status': status, 'hervat': hervat, 'stop': stop}[args.command](args, api)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (ValueError, OSError, TypeError, KeyError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
