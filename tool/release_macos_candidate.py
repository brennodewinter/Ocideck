#!/usr/bin/env python3
"""Build a trusted frozen macOS candidate; preserve notarization across jobs."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from release_channel import identity, immutable_write, encoded
from release_channel_controller import Forgejo
from release_journal import locked


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
    quality(Forgejo(), args.sha)  # No source code or keychain access before all gates pass.
    cache = Path.home() / 'Library/Caches/OciDeck-macos-candidates'
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    if cache.is_symlink() or cache.stat().st_uid != os.getuid() or cache.stat().st_mode & 0o077:
        raise ValueError('candidate cache must be private and owned')
    with locked(cache / (args.sha + '.lock')):
        root = cache / args.sha
        receipt = cache / (args.sha + '.controller.json')
        wanted = {'source_sha': args.sha, 'controller_sha': args.controller_sha, 'tag': args.tag}
        if receipt.exists() and (receipt.is_symlink() or json.loads(receipt.read_text()) != wanted):
            raise ValueError('saved candidate belongs to another controller; preserve and inspect')
        if not root.exists():
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
        mode = ['--resume-notary'] if state.exists() else []
        environment = {key: value for key, value in os.environ.items()
                       if not any(secret in key.upper() for secret in ('TOKEN', 'SECRET', 'PASSWORD'))}
        subprocess.run(['bash', str(controller / 'scripts/notarize_macos.sh'), '--source-root', str(root), *mode],
                       cwd=root, env=environment, check=True, timeout=14000)
        archive = root / f'build/macos/dist/OciDeck-{version}-macos.zip'
        with tempfile.TemporaryDirectory(prefix='ocideck-consumer-') as temp:
            consume(archive, Path(temp))
        args.dist.mkdir(parents=True, exist_ok=False)
        shutil.copyfile(archive, args.dist / f'ocideck-macos-{version}.zip')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('tag', 'sha', 'controller-sha'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--controller', type=Path, required=True)
    parser.add_argument('--dist', type=Path, required=True)
    run(parser.parse_args())
