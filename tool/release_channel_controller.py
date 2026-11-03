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
from urllib.parse import unquote, quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import uuid4

import release_channel
import release_channel_control
import release_journal
import release_channel_capabilities as capabilities

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
        value = self.request(path)
        if path.startswith('/git/refs/'):
            expected = 'refs/' + unquote(path.removeprefix('/git/refs/'))
            values = value if isinstance(value, list) else [value]
            if (len(values) != 1 or not isinstance(values[0], dict)
                    or values[0].get('ref') != expected):
                raise ValueError('Forgejo exact ref readback differs or is ambiguous')
            return values[0]
        return value

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

    def job_log(self, job_id):
        if type(job_id) is not int or job_id <= 0:
            raise ValueError('invalid Forgejo job ID')
        request = Request(self.base + f'/actions/jobs/{job_id}/logs',
                          headers={'Authorization': 'token ' + self._token})
        with self._opener.open(request, timeout=30) as response:
            if response.status != 200:
                raise ValueError('job log unavailable')
            body = response.read(20 * 1024 * 1024 + 1)
        if len(body) > 20 * 1024 * 1024:
            raise ValueError('job log exceeds whole-log inspection bound')
        return body.decode('utf-8', errors='replace').replace(self._token, '[redacted]')

    def branch_mutation(self, path, method, payload=None, expected=201):
        request = Request(self.base + path, data=None if payload is None else json.dumps(payload).encode(),
                          headers={'Authorization': 'token ' + self._token,
                                   'Content-Type': 'application/json'}, method=method)
        try:
            with self._opener.open(request, timeout=30) as response:
                if response.status != expected:
                    raise ValueError('unexpected Forgejo branch response')
                body = response.read(65537)
        except HTTPError as error:
            raise ValueError('Forgejo branch HTTP ' + str(error.code)) from None
        if len(body) > 65536:
            raise ValueError('Forgejo branch response too large')
        return json.loads(body, object_pairs_hook=release_channel.no_duplicates) if body else None


def claim_name(wanted):
    return 'codex/release-build-lock-' + wanted['tag'] + '-' + wanted['channel']


def claim_path(args, suffix):
    return operation_path(args).parent / (args.channel + '-claim-' + suffix + '.json')


def claim(args, api, wanted):
    branch = claim_name(wanted)
    intent = claim_path(args, 'intent')
    owned = claim_path(args, 'owned')
    receipt = dict(wanted, branch=branch)
    release_channel.immutable_write(intent, release_channel.encoded(receipt))
    # A lost 201 may have created the branch. Only this exact response grants ownership.
    created = api.branch_mutation('/branches', 'POST',
        {'new_branch_name': branch, 'old_ref_name': wanted['controller']}, 201)
    if (not isinstance(created, dict) or created.get('name') != branch
            or created.get('commit', {}).get('id') != wanted['controller']):
        raise ValueError('remote build claim ownership not proven')
    release_channel.immutable_write(owned, release_channel.encoded(receipt))


def release_claim(args, api, wanted):
    with release_journal.locked(claim_path(args, 'release-lease')):
        return _release_claim_locked(args, api, wanted)


def _release_claim_locked(args, api, wanted):
    owned = claim_path(args, 'owned')
    intent = claim_path(args, 'release-intent')
    complete = claim_path(args, 'release-completed')
    receipt = dict(wanted, branch=claim_name(wanted))
    if owned.is_symlink() or not owned.is_file() or json.loads(owned.read_text(), object_pairs_hook=release_channel.no_duplicates) != receipt:
        raise ValueError('build claim ownership receipt missing or changed')
    if complete.exists() or complete.is_symlink():
        if complete.is_symlink() or json.loads(complete.read_text(), object_pairs_hook=release_channel.no_duplicates) != receipt:
            raise ValueError('build claim release receipt differs')
        return
    if intent.exists() or intent.is_symlink():
        raise ValueError('build claim release outcome unknown; never repeat DELETE')
    branch_path = '/branches/' + quote(receipt['branch'], safe='')
    remote = api.get(branch_path)
    if (not isinstance(remote, dict) or remote.get('name') != receipt['branch']
            or remote.get('commit', {}).get('id') != wanted['controller']):
        raise ValueError('remote build claim changed; never delete')
    release_channel.immutable_write(intent, release_channel.encoded(receipt))
    api.branch_mutation(branch_path, 'DELETE', expected=204)
    release_channel.immutable_write(complete, release_channel.encoded(receipt))


def claim_status(args, wanted):
    receipt = dict(wanted, branch=claim_name(wanted))
    owned = claim_path(args, 'owned')
    intent = claim_path(args, 'release-intent')
    completed = claim_path(args, 'release-completed')
    def valid(path):
        return (not path.is_symlink() and path.is_file() and path.stat().st_size <= 4096
                and json.loads(path.read_text(), object_pairs_hook=release_channel.no_duplicates) == receipt)
    try:
        if owned.is_symlink() or (owned.exists() and not valid(owned)):
            return 'unknown'
        if completed.exists() or completed.is_symlink():
            return 'released' if valid(owned) and valid(completed) and valid(intent) else 'unknown'
        if intent.exists() or intent.is_symlink():
            return 'release_unknown' if valid(owned) and valid(intent) else 'unknown'
        return 'owned' if valid(owned) else 'unproven'
    except (ValueError, OSError, TypeError):
        return 'unknown'


def worker_state(api, wanted, run_id, channel):
    if type(run_id) is not int or run_id <= 0:
        raise ValueError('invalid previous Forgejo run ID')
    run = api.get('/actions/runs/' + str(run_id))
    if (not isinstance(run, dict) or run.get('id') != run_id or not run_matches(run, wanted)
            or run.get('commit_sha') != wanted['controller'] or run.get('status') not in TERMINAL
            or run.get('workflow_id') not in (WORKFLOW, '.forgejo/workflows/' + WORKFLOW)
            or run.get('trigger_event') != 'workflow_dispatch'):
        raise ValueError('previous worker run identity differs or is not terminal')
    artifacts = api.get('/actions/runs/' + str(run_id) + '/artifacts')
    name = channel + '-operation-' + wanted['operation_id']
    matches = [value for value in artifacts if isinstance(value, dict)
               and value.get('name') == name and value.get('expired') is False]
    if len(matches) != 1:
        raise ValueError('exact ' + channel + ' operation artifact unavailable')
    archive = api.artifact(matches[0].get('id'))
    with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
        entries = zipped.infolist()
        if (len(entries) != 1 or entries[0].filename != channel + '-operation.json'
                or entries[0].is_dir() or entries[0].file_size > 65536
                or stat.S_IFMT(entries[0].external_attr >> 16) not in (0, stat.S_IFREG)):
            raise ValueError('unsafe ' + channel + ' operation artifact')
        content = zipped.read(entries[0])
    state = json.loads(content, object_pairs_hook=release_channel.no_duplicates)
    if (not isinstance(state, dict) or state.get('operation_id') != wanted['operation_id']
            or state.get('tag') != wanted['tag'] or state.get('sha') != wanted['source']
            or state.get('ref') != wanted['frozen_ref'] or state.get('forge_run_id') != run_id
            or state.get('controller_sha') != wanted['controller']):
        raise ValueError('worker operation provenance differs')
    return content


def windows_state(api, wanted, run_id):
    return worker_state(api, wanted, run_id, 'windows')


def macos_state(api, wanted, run_id):
    content = worker_state(api, wanted, run_id, 'macos')
    saved = json.loads(content, object_pairs_hook=release_channel.no_duplicates)
    if (saved.get('outcome') not in ('pending', 'completed', 'failed')
            or saved.get('schema') != 1
            or (saved.get('submission_id') is not None and (not isinstance(saved['submission_id'], str)
                or not saved['submission_id'] or not re.fullmatch('[0-9a-f]{64}', saved.get('notary_sha256', ''))))):
        raise ValueError('macOS operation receipt differs')
    return content


def continuation_state(api, wanted, previous_run_id, current_run_id, attempt_id):
    if (type(previous_run_id) is not int or previous_run_id <= 0 or type(current_run_id) is not int
            or current_run_id <= previous_run_id or not OPERATION_RE.fullmatch(attempt_id or '')):
        raise ValueError('invalid continuation attempt provenance')
    current = api.get('/actions/runs/' + str(current_run_id))
    inputs = payload(current).get('inputs', {})
    if (not run_matches(current, wanted) or current.get('commit_sha') != wanted['controller']
            or current.get('workflow_id') not in (WORKFLOW, '.forgejo/workflows/' + WORKFLOW)
            or current.get('trigger_event') != 'workflow_dispatch'
            or inputs.get('attempt_id') != attempt_id or inputs.get('previous_run_id') != str(previous_run_id)):
        raise ValueError('current continuation run identity differs')
    return (windows_state if wanted['channel'] == 'windows' else macos_state)(api, wanted, previous_run_id)


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
    continuation = inputs.get('attempt_id', '')
    refs = (claim_name(wanted), 'refs/heads/' + claim_name(wanted)) if continuation else ('main', 'refs/heads/main')
    return (event.get('ref') in refs
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
            summary_inputs = payload(summary).get('inputs')
            if isinstance(summary_inputs, dict) and summary_inputs.get('operation_id') != wanted['operation_id']:
                continue
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
                        or detail.get('prettyref') not in ('main', 'refs/heads/main', claim_name(wanted), 'refs/heads/' + claim_name(wanted))
                        or detail.get('trigger_event') != 'workflow_dispatch'):
                    raise ValueError('operation ID belongs to a different run identity')
                found.append(detail)
        if len(values) < 100:
            return sorted(found, key=lambda run: run['id'])
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
        log_errors = []
        for job in work:
            if job.get('status') in ('running', 'failure', 'error'):
                try:
                    log_errors.append({'job': job.get('name'),
                                       'first_failure': capabilities.first_failure(api.job_log(job.get('id'))),
                                       'inspection': 'whole bounded log'})
                except (ValueError, OSError, AttributeError) as error:
                    log_errors.append({'job': job.get('name'), 'inspection': 'unknown',
                                       'reason': str(error)})
        outcome = 'completed' if run.get('status') == 'success' else 'unknown'
        if wanted['channel'] in ('windows', 'macos'):
            try:
                content = (windows_state if wanted['channel'] == 'windows' else macos_state)(api, wanted, run['id'])
                state = json.loads(content, object_pairs_hook=release_channel.no_duplicates)
                outcome = state.get('outcome', 'completed' if state.get('closed') else 'pending')
            except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile):
                outcome = 'unknown'
        entries.append({'log_errors': log_errors, 'id': run['id'], 'status': run.get('status'),
                        'outcome': outcome, 'inputs': payload(run).get('inputs', {}),
                        'created': run.get('created'), 'updated': run.get('updated'),
                        'started': run.get('started'), 'stopped': run.get('stopped'),
                        'duration': run.get('duration'), 'timing': capabilities.timing(run),
                        'jobs': work, 'first_error': first_error})
    return {'operation_id': wanted['operation_id'], 'runs': entries,
            'build_metadata': 'success' if entries and entries[-1]['status'] == 'success' and entries[-1]['outcome'] == 'completed' else 'unproven',
            'artifact_bytes': 'unverified', 'publication': 'unverified'}


def start(args, api):
    main = api.get('/git/refs/heads/main')
    if (not isinstance(main, dict) or main.get('ref') != 'refs/heads/main'
            or main.get('object', {}).get('sha') != args.controller_sha):
        raise ValueError('main differs from requested controller SHA; dispatch not attempted')
    readiness = capabilities.inspect(api, identity(args))
    if not readiness['ready']:
        raise ValueError('; '.join(readiness['blockers']))
    # The durable file and journal are fsynced before the one external POST.
    wanted = reserve(args)
    print(json.dumps({'operation_id': args.operation_id, 'state': 'reserved'}, sort_keys=True), flush=True)
    if runs(api, wanted):
        raise ValueError('operation already reached Forgejo; use hervat')
    main = api.get('/git/refs/heads/main')
    if (not isinstance(main, dict) or main.get('ref') != 'refs/heads/main'
            or main.get('object', {}).get('sha') != args.controller_sha):
        raise ValueError('main moved from reserved controller SHA; dispatch not attempted')
    claim(args, api, wanted)
    api.post('/actions/workflows/' + WORKFLOW + '/dispatches',
             {'ref': 'main', 'inputs': {'tag': args.tag, 'source_sha': args.sha,
                'frozen_ref': wanted['frozen_ref'], 'channel': args.channel,
                'operation_id': args.operation_id}})
    return snapshot(api, wanted)


def status(args, api):
    wanted = read_operation(args)
    result = snapshot(api, wanted)
    validate_attempts(args, result['runs'])
    journal = operation_path(args).parent / (args.channel + '.json')
    if not journal.is_file() or journal.is_symlink():
        raise ValueError('saved journal missing')
    result['history'] = release_journal.read(journal)['events']
    result['history_timing'] = capabilities.history_timing(result['history'])
    result['dispatch'] = 'unknown' if not result['runs'] else 'found'
    result['build_claim'] = claim_status(args, wanted)
    publication = next((event for event in reversed(result['history'])
                        if event['phase'] == 'publish'), None)
    if publication is not None:
        result['publication'] = ('recorded_' + publication['state']
                                 + '_public_bytes_unverified')
    if len(result['runs']) > 1 and result['build_claim'] != 'owned':
        result['publication'] = 'blocked_missing_continuation_controller_claim'
    if args.channel == 'windows':
        helper = Path(__file__).with_name('release_windows_candidate.py')
        if helper.is_file():
            command = [sys.executable, str(helper), 'status', '--tag', args.tag,
                       '--sha', args.sha, '--ref', wanted['frozen_ref'],
                       '--operation-id', args.operation_id, '--controller-sha', args.controller_sha]
            try:
                if not result['runs'] or result['runs'][-1]['status'] not in TERMINAL:
                    raise ValueError('Forgejo worker is not terminal')
                run_id = result['runs'][-1]['id']
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
    import release_channel_surfaces
    result['public_surfaces'] = release_channel_surfaces.public_status(args)
    return result


def attempt_path(args, previous_run_id):
    return operation_path(args).parent / (args.channel + '-continue-' + str(previous_run_id) + '.json')


def continuable(run):
    return (run['status'] in TERMINAL and (run.get('outcome') == 'pending'
            or (run.get('outcome') == 'completed' and run['status'] != 'success')))


def validate_attempts(args, entries):
    if not entries:
        return
    if entries[0].get('inputs', {}).get('attempt_id'):
        raise ValueError('original operation run unavailable')
    for previous, current in zip(entries, entries[1:]):
        path = attempt_path(args, previous['id'])
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 4096:
            raise ValueError('unowned or ambiguous continuation run')
        saved = json.loads(path.read_text(), object_pairs_hook=release_channel.no_duplicates)
        attempt = saved.get('attempt_id', '')
        expected = dict(identity(args), previous_run_id=previous['id'], attempt_id=attempt)
        inputs = current.get('inputs', {})
        if (saved != expected or not OPERATION_RE.fullmatch(attempt)
                or inputs.get('attempt_id') != attempt or inputs.get('previous_run_id') != str(previous['id'])
                or not continuable(previous)):
            raise ValueError('continuation identity or predecessor differs')


def continue_attempt(args, api, result):
    wanted = read_operation(args)
    with release_journal.locked(operation_path(args).with_suffix('.continuation')):
        current = result['runs'][-1]
        if claim_status(args, wanted) != 'owned':
            raise ValueError('continuation requires the original owned build claim')
        branch = claim_name(wanted)
        remote = api.get('/branches/' + quote(branch, safe=''))
        if remote.get('name') != branch or remote.get('commit', {}).get('id') != wanted['controller']:
            raise ValueError('continuation controller claim ref differs')
        proof = json.loads((windows_state if args.channel == 'windows' else macos_state)(
            api, wanted, current['id']), object_pairs_hook=release_channel.no_duplicates)
        if args.channel == 'windows' and set(proof.get('selected_runs', {})) != {'release.yml', 'windows-test-check.yml'}:
            raise ValueError('Windows continuation needs exact known upstream IDs')
        if args.channel == 'macos' and not proof.get('submission_id'):
            raise ValueError('macOS continuation needs a known existing submission')
        path = attempt_path(args, current['id'])
        if path.exists() or path.is_symlink():
            raise ValueError('continuation dispatch outcome unknown; never repeat POST')
        attempt = uuid4().hex
        receipt = dict(wanted, previous_run_id=current['id'], attempt_id=attempt)
        release_channel.immutable_write(path, release_channel.encoded(receipt))
        api.post('/actions/workflows/' + WORKFLOW + '/dispatches', {'ref': branch, 'inputs': {
            'tag': args.tag, 'source_sha': args.sha, 'frozen_ref': wanted['frozen_ref'], 'channel': args.channel,
            'operation_id': args.operation_id, 'attempt_id': attempt, 'previous_run_id': str(current['id'])}})
        resumed = status(args, api)
        resumed['continuation'] = 'found' if len(resumed['runs']) > len(result['runs']) else 'unknown'
        return resumed


def hervat(args, api):
    result = status(args, api)
    if not result['runs']:
        raise ValueError('dispatch outcome unknown; never redispatch this operation ID')
    save_observation(args, result)
    current = result['runs'][-1]
    if args.channel in ('windows', 'macos') and continuable(current):
        return continue_attempt(args, api, result)
    if (current['status'] in TERMINAL
            and (args.channel not in ('windows', 'macos') or current.get('outcome') in ('completed', 'failed'))
            and len(result['runs']) == 1
            and (args.channel != 'windows' or (result.get('github', {}).get('terminal') is True
                                                and result['github'].get('unknown') is False))):
        release_claim(args, api, read_operation(args))
    return result


def save_observation(args, result):
    """Keep a checksum-bound snapshot of exact run/jobs and its first error."""
    from hashlib import sha256
    from types import SimpleNamespace
    journal = operation_path(args).parent / (args.channel + '.json')
    run = result['runs'][-1]
    content = release_channel.encoded(run)
    proof = journal.parent / f"{args.channel}-run-{run['id']}-{sha256(content).hexdigest()[:16]}.json"
    release_channel.immutable_write(proof, content)
    current = release_journal.read(journal)
    last_dispatch = next((e for e in reversed(current['events']) if e['phase'] == 'dispatch'), None)
    if last_dispatch and last_dispatch['state'] == 'started':
        release_journal.record(SimpleNamespace(journal=journal, phase='dispatch', state='completed', evidence=[proof]))
    current = release_journal.read(journal)
    last_build = next((e for e in reversed(current['events']) if e['phase'] == 'build'), None)
    if last_build is None or (last_build['state'] in ('failed', 'cancelled')
            and str(proof.resolve()) not in last_build['evidence']):
        release_journal.record(SimpleNamespace(journal=journal, phase='build', state='started', evidence=[proof]))
        last_build = {'state': 'started'}
    if (last_build['state'] == 'started' and run['status'] in TERMINAL and run.get('outcome') != 'pending'
            and not (run['status'] == 'success' and run.get('outcome') == 'unknown')):
        state = 'completed' if run['status'] == 'success' and run.get('outcome', 'completed') == 'completed' else 'cancelled' if run['status'] == 'cancelled' else 'failed'
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
            validate_attempts(args, result['runs'])
            if latest[-1].get('commit_sha') == wanted['controller']:
                save_observation(args, result)
            # Only a terminal Forgejo worker cannot dispatch more dependent jobs.
            if args.channel == 'windows':
                helper = Path(__file__).with_name('release_windows_candidate.py')
                if not helper.is_file():
                    raise ValueError('Windows ownership helper missing; GitHub state remains unknown')
                command = [sys.executable, str(helper), 'cancel', '--tag', args.tag, '--sha', args.sha,
                           '--ref', wanted['frozen_ref'], '--operation-id', args.operation_id,
                           '--forge-run-id', str(latest[-1]['id']), '--controller-sha', args.controller_sha,
                           '--wait-terminal']
                try:
                    content = windows_state(api, wanted, latest[-1]['id'])
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
            release_claim(args, api, wanted)
            return result
        time.sleep(5)
    raise ValueError('cancel requested but terminal Forgejo state not confirmed')


def publish(args, api):
    readiness = capabilities.inspect(api, identity(args), 'assets')
    if not readiness['ready']:
        raise ValueError('; '.join(readiness['blockers']))
    result = status(args, api)
    if (not result['runs'] or result['runs'][-1]['status'] != 'success'
            or result['runs'][-1].get('outcome', 'completed') != 'completed'
            or str(result['runs'][-1]['id']) != str(args.run_id)):
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
    parser.add_argument('command', choices=['capabilities', 'plan', 'start', 'status', 'stop', 'hervat', 'publish', 'public', 'rollback'])
    parser.add_argument('--state-dir', type=Path, required=True)
    for name in ('tag', 'sha', 'controller-sha', 'channel'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--rollback-from')
    parser.add_argument('--operation-id')
    parser.add_argument('--phase', choices=['build', 'assets', 'website'], default='build')
    parser.add_argument('--run-id')
    parser.add_argument('--release-id', default='auto')
    parser.add_argument('--create-release', action='store_true')
    parser.add_argument('--dist', type=Path)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    if args.command == 'start':
        args.operation_id = args.operation_id or uuid4().hex
    elif args.command not in ('plan', 'capabilities') and not args.operation_id:
        path = operation_path(args)
        if path.is_symlink() or not path.is_file():
            parser.error('saved operation ID missing')
        args.operation_id = json.loads(path.read_text(), object_pairs_hook=release_channel.no_duplicates).get('operation_id')
    try:
        if args.command == 'capabilities':
            args.operation_id = args.operation_id or 'planned'
            result = capabilities.inspect(Forgejo(), identity(args), args.phase)
        elif args.command == 'plan':
            args.operation_id = args.operation_id or 'planned'
            result = {'identity': identity(args), 'action': 'read-only plan; no operation reserved'}
        elif args.command in ('public', 'rollback'):
            import release_channel_surfaces
            if args.command == 'rollback' and not args.rollback_from:
                raise ValueError('rollback requires --rollback-from CURRENT_TAG')
            if args.command == 'public' and args.rollback_from:
                raise ValueError('use explicit rollback command with rollback-from')
            result = release_channel_surfaces.public(args, Forgejo())
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
