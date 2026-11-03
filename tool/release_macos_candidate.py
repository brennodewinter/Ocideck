#!/usr/bin/env python3
"""Build a trusted frozen macOS candidate; preserve notarization across jobs."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from release_channel import identity, immutable_write, encoded, no_duplicates, file_hash
from release_channel_controller import Forgejo, continuation_state, OPERATION_RE
from release_journal import locked, atomic_write

# Toelatingsbeleid, geen gemeten bouwmaximum; de runnerbeheerder kalibreert dit vóór opschaling.
CANDIDATE_RESERVE = 16 * 1024**3
CACHE_BUDGET = 32 * 1024**3
MAX_CANDIDATES = 2


def admission(cache, root):
    used = sum(path.lstat().st_size for path in cache.rglob('*') if not path.is_dir() or path.is_symlink())
    candidates = [path for path in cache.iterdir() if re.fullmatch('[0-9a-f]{40}', path.name)]
    if ((not root.exists() and len(candidates) >= MAX_CANDIDATES)
            or used + CANDIDATE_RESERVE > CACHE_BUDGET
            or shutil.disk_usage(cache).free < CANDIDATE_RESERVE):
        raise ValueError('macOS candidate cache admission refused: reserve 16 GiB, cache budget 32 GiB, '
                         'maximum two candidates; archive retained evidence and review capacity before retry; nothing removed')


def saved_notary(state):
    if state.is_symlink() or not state.is_file() or state.stat().st_size > 65536:
        raise ValueError('saved macOS submission unavailable or unsafe')
    content = state.read_bytes()
    saved = json.loads(content, object_pairs_hook=no_duplicates)
    if not isinstance(saved, dict) or not isinstance(saved.get('submission_id'), str) or not saved['submission_id']:
        raise ValueError('saved macOS submission remains unknown; never submit again')
    return saved, sha256(content).hexdigest()


def quality(api, sha):
    result = {}
    for workflow in ('static-gate.yml', 'scans.yml', 'macos-gate.yml'):
        runs = []
        seen = set()
        for page in range(1, 21):
            response = api.get(f'/actions/runs?limit=100&page={page}&head_sha={sha}&workflow_id={workflow}')
            values = response.get('workflow_runs') if isinstance(response, dict) else None
            if not isinstance(values, list) or len(values) > 100:
                raise ValueError('invalid source quality response')
            for run in values:
                if (not isinstance(run, dict) or type(run.get('id')) is not int or run['id'] <= 0
                        or run['id'] in seen or run.get('commit_sha') != sha
                        or run.get('workflow_id') not in (workflow, '.forgejo/workflows/' + workflow)):
                    raise ValueError('source quality identity differs')
                seen.add(run['id'])
                runs.append(run)
            if len(values) < 100:
                break
        else:
            raise ValueError('source quality history exceeds bound')
        latest = max(runs, key=lambda run: run['id']) if runs else None
        if not latest or latest.get('status') != 'success':
            raise ValueError('run exact-source quality workflow before signing: ' + workflow)
        jobs = api.get('/actions/runs/' + str(latest['id']) + '/jobs')
        if not isinstance(jobs, list) or not jobs or any(job.get('status') != 'success' for job in jobs):
            raise ValueError('source quality jobs are not all successful: ' + workflow)
        result[workflow] = latest['id']
    return result


def command(args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True, timeout=240).stdout.strip()


def source_trusted(root, tag, sha):
    command(['git', 'fetch', '--no-tags', 'origin', 'main'], root)
    if subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'FETCH_HEAD'], cwd=root).returncode == 0:
        return
    ref = 'refs/heads/codex/release-base-' + tag
    tip = command(['git', 'ls-remote', '--exit-code', 'origin', ref], root).split()
    if tip != [sha, ref]:
        raise ValueError('source is neither protected-main ancestry nor exact maintenance-base tip')
    if len(command(['git', 'show', '-s', '--format=%P', sha], root).split()) != 2:
        raise ValueError('maintenance source must be a normal merge')
    if command(['git', 'rev-parse', sha + '^{tree}'], root) != command(['git', 'rev-parse', sha + '^2^{tree}'], root):
        raise ValueError('maintenance merge tree differs from tested head')


def preflight(controller, root, environment):
    # An installed certificate alone does not prove background private-key access.
    with tempfile.TemporaryDirectory(prefix='ocideck-signing-check-') as directory:
        probe = Path(directory) / 'probe'
        shutil.copyfile('/usr/bin/true', probe)
        subprocess.run(['codesign', '--force', '--timestamp=none', '--sign',
                        environment.get('OCIDECK_SIGN_IDENTITY',
                            'Developer ID Application: Brenno de Winter (AMT83P4B3L)'), str(probe)],
                       env=environment, check=True, capture_output=True, timeout=120)
    subprocess.run(['bash', str(controller / 'scripts/notarize_macos.sh'),
                    '--source-root', str(root), '--preflight'], cwd=root,
                   env=environment, check=True, timeout=240)


def consume(archive, directory):
    command(['ditto', '-x', '-k', str(archive), str(directory)], directory)
    app = directory / 'OciDeck.app'
    if app.is_symlink() or not app.is_dir() or {p.name for p in directory.iterdir()} != {'OciDeck.app'}:
        raise ValueError('unexpected macOS archive contents')
    command(['codesign', '--verify', '--deep', '--strict', str(app)], directory)
    detail = subprocess.run(['codesign', '-d', '--verbose=4', str(app)], capture_output=True, text=True, check=True)
    if 'TeamIdentifier=AMT83P4B3L' not in detail.stderr.splitlines():
        raise ValueError('unexpected macOS signing team')
    command(['xcrun', 'stapler', 'validate', str(app)], directory)
    command(['spctl', '-a', '-t', 'exec', str(app)], directory)


def run(args):
    version = identity(args.tag, args.sha, 'macos')
    identity(args.tag, args.controller_sha, 'macos')
    controller = args.controller.resolve()
    if command(['git', 'rev-parse', 'HEAD'], controller) != args.controller_sha:
        raise ValueError('controller checkout differs')
    source_trusted(controller, args.tag, args.sha)
    api = Forgejo()
    quality(api, args.sha)  # No source code or keychain access before all gates pass.
    if not OPERATION_RE.fullmatch(args.operation_id) or args.forge_run_id <= 0:
        raise ValueError('invalid macOS operation provenance')
    previous = None
    wanted_operation = dict(operation_id=args.operation_id, tag=args.tag, source=args.sha,
        controller=args.controller_sha, channel='macos', frozen_ref=f'codex/release-candidate-{args.tag}-{args.sha}')
    if args.previous_run_id is not None:
        previous = json.loads(continuation_state(api, wanted_operation, args.previous_run_id,
            args.forge_run_id, args.attempt_id), object_pairs_hook=no_duplicates)
        if previous['outcome'] not in ('pending', 'completed') or not previous.get('submission_id'):
            raise ValueError('previous macOS attempt has no known resumable submission')
    cache = Path.home() / 'Library/Caches/OciDeck-macos-candidates'
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    if cache.is_symlink() or cache.stat().st_uid != os.getuid() or cache.stat().st_mode & 0o077:
        raise ValueError('candidate cache must be private and owned')
    # De cachebrede lease houdt toelating en gereserveerde extra bouwruimte bij elkaar.
    with locked(cache / 'admission'):
        root = cache / args.sha
        admission(cache, root)
        if args.result.is_symlink():
            raise ValueError('macOS operation receipt must not be a symlink')
        args.result.parent.mkdir(parents=True, exist_ok=True)
        receipt = cache / (args.sha + '.controller.json')
        wanted = {'source_sha': args.sha, 'controller_sha': args.controller_sha, 'tag': args.tag}
        if receipt.exists() and (receipt.is_symlink() or json.loads(receipt.read_text()) != wanted):
            raise ValueError('saved candidate belongs to another controller; preserve and inspect')
        if not root.exists():
            if previous:
                raise ValueError('saved macOS candidate missing; continuation must not rebuild')
            command(['git', 'clone', '--no-checkout', '--no-hardlinks', str(controller), str(root)], cache)
            command(['git', 'checkout', '--detach', args.sha], root)
            immutable_write(receipt, encoded(wanted))
        if root.is_symlink() or not receipt.is_file() or command(['git', 'rev-parse', 'HEAD'], root) != args.sha:
            raise ValueError('saved checkout identity differs')
        if command(['git', 'status', '--porcelain', '--untracked-files=no'], root):
            raise ValueError('saved source contains tracked changes')
        if command(['git', 'show', args.sha + ':pubspec.yaml'], root).split('version: ', 1)[1].split('+', 1)[0].splitlines()[0] != version:
            raise ValueError('source version differs')
        state = root / '.git/ocideck-notary' / (args.sha + '.submission.json')
        if previous:
            saved, digest = saved_notary(state)
            if saved['submission_id'] != previous['submission_id'] or digest != previous['notary_sha256']:
                raise ValueError('saved macOS submission or bytes differ from previous attempt')
        mode = ['--resume-notary'] if state.exists() else []
        environment = {key: value for key, value in os.environ.items()
                       if not any(secret in key.upper() for secret in ('TOKEN', 'SECRET', 'PASSWORD'))}
        if not mode:
            command(['make', 'check-toolchain'], root)
        preflight(controller, root, environment)
        operation = dict(schema=1, operation_id=args.operation_id, tag=args.tag, sha=args.sha,
            ref=wanted_operation['frozen_ref'], forge_run_id=args.forge_run_id,
            controller_sha=args.controller_sha, outcome='failed', submission_id=None, notary_sha256=None)
        try:
            subprocess.run(['bash', str(controller / 'scripts/notarize_macos.sh'), '--source-root', str(root), *mode],
                           cwd=root, env=environment, check=True, timeout=14000)
        except subprocess.CalledProcessError:
            if state.exists():
                saved, digest = saved_notary(state)
                operation.update(submission_id=saved['submission_id'], notary_sha256=digest)
                if saved.get('status') == 'pending':
                    operation['outcome'] = 'pending'
                    atomic_write(args.result, operation)
                    return operation
            atomic_write(args.result, operation)
            raise
        saved, digest = saved_notary(state)
        operation.update(submission_id=saved['submission_id'], notary_sha256=digest, outcome='pending')
        atomic_write(args.result, operation)
        archive = root / f'build/macos/dist/OciDeck-{version}-macos.zip'
        with tempfile.TemporaryDirectory(prefix='ocideck-consumer-') as temp:
            consume(archive, Path(temp))
        if args.dist.is_symlink():
            raise ValueError('macOS distribution path must not be a symlink')
        args.dist.mkdir(parents=True, exist_ok=True)
        target = args.dist / f'ocideck-macos-{version}.zip'
        if target.exists() or target.is_symlink():
            if target.is_symlink() or not target.is_file() or file_hash(target) != file_hash(archive):
                raise ValueError('existing macOS distribution bytes differ')
        else:
            shutil.copyfile(archive, target)
        operation['outcome'] = 'completed'
        atomic_write(args.result, operation)
        return operation


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('tag', 'sha', 'controller-sha'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--controller', type=Path, required=True)
    parser.add_argument('--dist', type=Path, required=True)
    parser.add_argument('--operation-id', required=True)
    parser.add_argument('--forge-run-id', type=int, required=True)
    parser.add_argument('--previous-run-id', type=int)
    parser.add_argument('--attempt-id')
    parser.add_argument('--result', type=Path, required=True)
    run(parser.parse_args())
