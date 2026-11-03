#!/usr/bin/env python3
"""Persist a notarization submission before waiting; never retry a submission.

Only a named keychain profile is used. Raw tool output may contain account data
and is deliberately not copied into the journal or error messages.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import stat
import subprocess
import sys
import uuid

from release_channel import file_hash, no_duplicates
from release_journal import atomic_write, locked

STATES = {'submitting', 'unknown', 'submitted', 'pending', 'accepted', 'invalid', 'stapling', 'stapled', 'packaging'}
FIELDS = {'schema', 'archive', 'archive_sha256', 'app', 'app_sha256', 'profile', 'keychain',
          'identity', 'submission_id', 'status'}


def app_hash(app):
    if app.is_symlink() or not app.is_dir():
        raise ValueError('saved app must be a real directory')
    entries = []
    for root, directories, files in os.walk(app, followlinks=False):
        for name in sorted(directories + files):
            path = Path(root) / name
            mode = path.lstat().st_mode
            relative = path.relative_to(app).as_posix()
            if stat.S_ISLNK(mode):
                entries.append((relative, 'link', os.readlink(path)))
            elif stat.S_ISREG(mode):
                # Some signed bundle resources are empty; retain them in the identity.
                digest = hashlib.sha256()
                with path.open('rb') as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                        digest.update(chunk)
                entries.append((relative, 'file', stat.S_IMODE(mode), digest.hexdigest()))
            elif stat.S_ISDIR(mode):
                entries.append((relative, 'directory'))
            else:
                raise ValueError('saved app contains a special file')
    return hashlib.sha256(json.dumps(sorted(entries), ensure_ascii=True).encode()).hexdigest()


def command(arguments):
    # A wait has a generous explicit Apple timeout; no hidden retry loop.
    try:
        return subprocess.run(arguments, capture_output=True, text=True, timeout=7500)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError('notary command unavailable or timed out; resume existing submission') from error


def codesign(app, identity):
    result = command(['codesign', '--verify', '--deep', '--strict', str(app)])
    if result.returncode:
        raise ValueError('saved app signature verification failed')
    detail = command(['codesign', '-d', '--verbose=4', str(app)])
    if detail.returncode or ('Authority=' + identity) not in detail.stderr.splitlines():
        raise ValueError('saved app signing identity differs')


def read_state(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('notary state must be a regular file')
    if path.stat().st_size > 65536:
        raise ValueError('notary state exceeds bound')
    data = json.loads(path.read_text(), object_pairs_hook=no_duplicates)
    if not isinstance(data, dict) or set(data) != FIELDS or type(data['schema']) is not int or data['schema'] != 1:
        raise ValueError('invalid notary state schema')
    if not all(isinstance(data[key], str) and data[key] for key in FIELDS - {'schema', 'submission_id'}):
        raise ValueError('invalid notary state values')
    if data['status'] not in STATES or not all(re.fullmatch(r'[0-9a-f]{64}', data[k]) for k in ('archive_sha256', 'app_sha256')):
        raise ValueError('invalid notary state identity')
    if data['submission_id'] is not None:
        try:
            if str(uuid.UUID(data['submission_id'])) != data['submission_id']:
                raise ValueError('noncanonical submission ID')
        except (ValueError, TypeError, AttributeError) as error:
            raise ValueError('invalid submission ID') from error
    elif data['status'] not in ('submitting', 'unknown'):
        raise ValueError('notary state has no submission ID')
    return data


def parse_result(result, submission=None):
    try:
        data = json.loads(result.stdout, object_pairs_hook=no_duplicates)
    except ValueError as error:
        raise ValueError('notary response is not readable JSON') from error
    if not isinstance(data, dict) or not isinstance(data.get('id'), str):
        raise ValueError('notary response has no submission ID')
    try:
        if str(uuid.UUID(data['id'])) != data['id']:
            raise ValueError('noncanonical ID')
    except ValueError as error:
        raise ValueError('notary response has invalid submission ID') from error
    if submission is not None and data['id'] != submission:
        raise ValueError('Apple returned a different submission ID')
    return data


def guard(directory):
    for path in directory.glob('*.submission.json'):
        if read_state(path)['status'] != 'stapled':
            raise ValueError('unfinished notarization exists; resume its saved app/archive before a new build')


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def copy_app(source, destination):
    shutil.copytree(source, destination, symlinks=True)
    for directory, _, files in os.walk(destination, followlinks=False):
        for name in files:
            path = Path(directory) / name
            if not path.is_symlink():
                with path.open('rb') as stream:
                    os.fsync(stream.fileno())
        sync_directory(directory)


def preserve_app(state, app, digest):
    backup = Path(str(state) + '.pre-staple.app')
    if backup.exists() or backup.is_symlink():
        if app_hash(backup) != digest:
            raise ValueError('pre-staple backup differs; do not resume')
        return backup
    pending = Path(tempfile.mkdtemp(prefix='.notary-backup-', dir=state.parent))
    pending.rmdir()
    try:
        copy_app(app, pending)
        if app_hash(pending) != digest:
            raise ValueError('app changed while preserving pre-staple backup')
        os.rename(pending, backup)
        sync_directory(state.parent)
    finally:
        if pending.exists():
            shutil.rmtree(pending)
    return backup


def restore_app(state, app, digest):
    backup = Path(str(state) + '.pre-staple.app')
    if app_hash(backup) != digest:
        raise ValueError('pre-staple backup differs; do not restore')
    if app.is_symlink():
        raise ValueError('app was replaced with a link; refuse restoration')
    app.parent.mkdir(parents=True, exist_ok=True)
    pending = Path(tempfile.mkdtemp(prefix='.notary-restore-', dir=app.parent))
    pending.rmdir()
    try:
        copy_app(backup, pending)
        if app_hash(pending) != digest:
            raise ValueError('restored app differs from saved submission')
        if app.exists():
            previous = Path(tempfile.mkdtemp(prefix='.notary-interrupted-', dir=app.parent))
            previous.rmdir()
            os.rename(app, previous)
            # Preserve interrupted output for inspection instead of silently deleting it.
        os.rename(pending, app)
        sync_directory(app.parent)
    finally:
        if pending.exists():
            shutil.rmtree(pending)


def package_archive(args, data):
    if data['status'] != 'packaging':
        data['status'] = 'packaging'
        atomic_write(args.state, data)
    target = args.package.absolute()
    target.parent.mkdir(parents=True, exist_ok=True)
    pending = target.with_name('.' + target.name + '.pending')
    receipt = Path(str(args.state) + '.package.json')
    expected = {'schema': 1, 'app_sha256': data['app_sha256'], 'package': str(target)}
    if receipt.exists() or receipt.is_symlink():
        if receipt.is_symlink() or not receipt.is_file():
            raise ValueError('package receipt must be regular')
        saved = json.loads(receipt.read_text(), object_pairs_hook=no_duplicates)
        if (not isinstance(saved, dict) or set(saved) != set(expected) | {'sha256'}
                or type(saved['schema']) is not int
                or any(saved.get(key) != value for key, value in expected.items())
                or not isinstance(saved['sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', saved['sha256'])):
            raise ValueError('package receipt identity differs')
    else:
        if target.exists() or target.is_symlink():
            raise ValueError('unrecorded package exists; do not overwrite')
        if pending.exists() or pending.is_symlink():
            if pending.is_symlink() or not pending.is_file():
                raise ValueError('unsafe pending package')
            pending.unlink()
        result = command(['ditto', '-c', '-k', '--keepParent', str(args.app), str(pending)])
        if result.returncode:
            raise ValueError('package creation failed; original submission is preserved')
        if app_hash(args.app) != data['app_sha256']:
            raise ValueError('saved app changed during packaging')
        digest = file_hash(pending)
        with pending.open('rb') as stream:
            os.fsync(stream.fileno())
        saved = dict(expected, sha256=digest)
        sync_directory(target.parent)
        atomic_write(receipt, saved)
    if target.exists() or target.is_symlink():
        if target.is_symlink() or file_hash(target) != saved['sha256']:
            raise ValueError('published package differs from durable receipt')
    else:
        if pending.is_symlink() or file_hash(pending) != saved['sha256']:
            raise ValueError('pending package differs from durable receipt')
        os.rename(pending, target)
        sync_directory(target.parent)
    checksum = target.parent / 'SHA256SUMS'
    if checksum.is_symlink():
        raise ValueError('checksum must not be a link')
    descriptor, temporary = tempfile.mkstemp(prefix='.SHA256SUMS-', dir=target.parent)
    try:
        with os.fdopen(descriptor, 'w') as output:
            output.write(saved['sha256'] + '  ' + target.name + '\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, checksum)
        sync_directory(target.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    data['status'] = 'stapled'
    atomic_write(args.state, data)
    return data


def run(args):
    args.state = args.state.absolute()
    args.archive = args.archive.absolute()
    args.app = args.app.absolute()
    with locked(args.state):
        if args.archive.is_symlink():
            raise ValueError('archive must not be a symlink')
        archive_digest = file_hash(args.archive)
        identity = dict(schema=1, archive=str(args.archive), archive_sha256=archive_digest,
                        app=str(args.app), profile=args.profile, keychain=args.keychain, identity=args.identity)
        if args.mode != 'submit':
            saved = read_state(args.state)
            if any(saved.get(key) != value for key, value in identity.items()):
                raise ValueError('saved archive, app, profile, keychain or signing identity changed')
            if saved['status'] == 'stapling':
                restore_app(args.state, args.app, saved['app_sha256'])
        app_digest = app_hash(args.app)
        codesign(args.app, args.identity)
        identity['app_sha256'] = app_digest
        auth = ['--keychain', args.keychain, '--keychain-profile', args.profile, '--output-format', 'json']
        if args.mode == 'submit':
            if args.state.exists() or args.state.is_symlink():
                raise ValueError('submission state exists; use --resume-notary, never resubmit')
            data = dict(identity, submission_id=None, status='submitting')
            atomic_write(args.state, data)
            try:
                result = command(['xcrun', 'notarytool', 'submit', str(args.archive), *auth, '--no-wait'])
                response = parse_result(result)
            except (ValueError, KeyboardInterrupt):
                data['status'] = 'unknown'
                atomic_write(args.state, data)
                raise ValueError('submission outcome unknown; reconcile Apple history manually, do not resubmit')
            data['submission_id'], data['status'] = response['id'], 'submitted'
            atomic_write(args.state, data)
        else:
            data = read_state(args.state)
            if any(data.get(key) != value for key, value in identity.items()):
                raise ValueError('saved archive, app, profile, keychain or signing identity changed')
            if data['status'] in ('submitting', 'unknown'):
                raise ValueError('submission outcome unknown; reconcile Apple history manually, do not resubmit')
            if data['status'] == 'invalid':
                raise ValueError('Apple rejected this immutable submission; inspect its saved rejection summary')
        if data['status'] in ('stapled', 'packaging'):
            if command(['xcrun', 'stapler', 'validate', str(args.app)]).returncode:
                raise ValueError('saved app stapled ticket is invalid')
            if args.mode == 'package':
                return package_archive(args, data)
            return data
        if args.mode == 'package':
            raise ValueError('package requires a completed stapled submission')
        submission = data['submission_id']
        result = command(['xcrun', 'notarytool', 'info', submission, *auth])
        response = parse_result(result, submission)
        if result.returncode:
            raise ValueError('Apple status lookup failed; retain submission and resume later')
        status = response.get('status')
        if status == 'In Progress':
            data['status'] = 'pending'
            atomic_write(args.state, data)
            result = command(['xcrun', 'notarytool', 'wait', submission, *auth, '--timeout', '2h'])
            response = parse_result(result, submission)
            status = response.get('status')
        if status == 'In Progress':
            raise ValueError('Apple submission is pending; use --resume-notary later')
        if status not in ('Accepted', 'Invalid', 'Rejected'):
            raise ValueError('unknown Apple status; retain submission and resume after diagnosis')
        if result.returncode and status == 'Accepted':
            raise ValueError('Apple wait failed despite accepted output; verify with info on resume')
        data['status'] = 'accepted' if status == 'Accepted' else 'invalid'
        atomic_write(args.state, data)
        if data['status'] == 'invalid':
            # Persist only a safe summary. Apple logs may disclose account or paths.
            summary = {'schema': 1, 'submission_id': submission, 'status': status, 'issues': []}
            try:
                log = command(['xcrun', 'notarytool', 'log', submission, *auth])
                report = json.loads(log.stdout, object_pairs_hook=no_duplicates)
                if log.returncode == 0 and isinstance(report, dict) and isinstance(report.get('issues'), list):
                    for issue in report['issues']:
                        if not isinstance(issue, dict):
                            continue
                        # Codes/severity explain the rejection without account names or file paths.
                        code, severity = issue.get('code'), issue.get('severity')
                        if type(code) is int and severity in ('error', 'warning'):
                            summary['issues'].append({'code': code, 'severity': severity})
            except (ValueError, TypeError):
                pass
            atomic_write(Path(str(args.state) + '.rejection.json'), summary)
            raise ValueError('Apple rejected submission ' + submission + '; inspect with notarytool log using the saved profile')
        if file_hash(args.archive) != archive_digest or app_hash(args.app) != app_digest:
            raise ValueError('saved app/archive changed while waiting; do not staple')
        preserve_app(args.state, args.app, app_digest)
        data['status'] = 'stapling'
        atomic_write(args.state, data)
        if command(['xcrun', 'stapler', 'staple', str(args.app)]).returncode:
            raise ValueError('stapling failed; resume the same accepted submission')
        if command(['xcrun', 'stapler', 'validate', str(args.app)]).returncode:
            raise ValueError('stapled ticket validation failed')
        codesign(args.app, args.identity)
        data['status'], data['app_sha256'] = 'stapled', app_hash(args.app)
        atomic_write(args.state, data)
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('submit', 'resume', 'guard', 'package'))
    parser.add_argument('--state-dir', type=Path)
    parser.add_argument('--package', type=Path)
    for name in ('state', 'archive', 'app'):
        parser.add_argument('--' + name, type=Path)
    for name in ('profile', 'keychain', 'identity'):
        parser.add_argument('--' + name)
    try:
        args = parser.parse_args()
        if args.mode == 'guard':
            if args.state_dir is None:
                raise ValueError('guard requires --state-dir')
            guard(args.state_dir)
            return 0
        if any(getattr(args, key) is None for key in ('state', 'archive', 'app', 'profile', 'keychain', 'identity')):
            raise ValueError('submission requires state, archive, app, profile, keychain and identity')
        if args.mode == 'package' and args.package is None:
            raise ValueError('package mode requires --package')
        result = run(args)
        print(json.dumps({'submission_id': result['submission_id'], 'status': result['status']}, sort_keys=True))
        return 0
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
