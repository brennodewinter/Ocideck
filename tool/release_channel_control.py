#!/usr/bin/env python3
"""Explicit channel publication with a tag-wide lease and durable progress."""
import argparse
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import release_channel
import release_journal


def run_publisher(command):
    process = subprocess.Popen(command, start_new_session=True)
    try:
        return subprocess.CompletedProcess(command, process.wait())
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise


def stop(_number, _frame):
    raise KeyboardInterrupt


def select_candidate_paths(args, state):
    stage = state / (args.channel + '-candidate')
    if not args.dist.exists() and (stage / 'dist').is_dir():
        args.dist = stage / 'dist'
    if not args.evidence.exists() and (stage / 'evidence').is_dir():
        args.evidence = stage / 'evidence'
    return args


def publisher_command(args, root, state, receipt):
    select_candidate_paths(args, state)
    stage = state / (args.channel + '-candidate')
    command = ['bash', str(root / 'scripts/publish_release_channel.sh')]
    for name in ('release_id', 'run_id', 'tag', 'sha', 'controller_sha', 'channel', 'dist', 'evidence'):
        command += ['--' + name.replace('_', '-'), str(getattr(args, name))]
    if args.create_release:
        command += ['--create-release']
    command += ['--staging-dir', str(stage), '--receipt', str(receipt)]
    if getattr(args, 'status', False):
        command += ['--verify-only']
    return command


def publish(args):
    if not getattr(args, 'status', False) and (args.release_id == 'auto') != args.create_release:
        raise ValueError('auto release ID requires explicit create-release')
    release_channel.identity(args.tag, args.sha, args.channel)
    release_channel.identity(args.tag, args.controller_sha, args.channel)
    root = Path(__file__).resolve().parent.parent
    state = args.state_dir.resolve() / args.tag
    journal = state / (args.channel + '.json')
    receipt = state / (args.channel + '-published.json')
    if getattr(args, 'status', False):
        return run_publisher(publisher_command(args, root, state, receipt)).returncode
    state.mkdir(parents=True, exist_ok=True)
    # The lease covers remote reads, uploads, readback and the final journal write.
    with release_journal.locked(state / 'publication'):
        release_journal.initialize(SimpleNamespace(journal=journal, tag=args.tag,
            sha=args.sha, channel=args.channel,
            workflow=root / '.forgejo/workflows/release-channel.yml'))
        record = SimpleNamespace(journal=journal, phase='publish', state='started', evidence=[])
        current = release_journal.read(journal)
        previous = next((e for e in reversed(current['events']) if e['phase'] == 'publish'), None)
        if previous and previous['state'] == 'completed':
            release_journal.verify(current)
            # Reconcile public bytes again; a local receipt alone is not public proof.
        elif previous and previous['state'] == 'started':
            raise ValueError('interrupted publication: inspect and explicitly record cancelled before resuming')
        else:
            release_journal.record(record)
        command = publisher_command(args, root, state, receipt)
        try:
            result = run_publisher(command)
            if result.returncode:
                if not previous or previous['state'] != 'completed':
                    record.state = 'failed'
                    release_journal.record(record)
                return result.returncode
            if not receipt.is_file() or receipt.is_symlink():
                raise ValueError('publisher returned without durable readback receipt')
            record.state, record.evidence = 'completed', [receipt]
            release_journal.record(record)
            print(json.dumps({'journal': str(journal), 'receipt': str(receipt), 'state': 'completed'}))
            return 0
        except KeyboardInterrupt:
            # A killed upload may have reached the forge; the next run reconciles it.
            if not previous or previous['state'] != 'completed':
                record.state = 'cancelled'
                release_journal.record(record)
            return 130


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, required=True)
    parser.add_argument('--create-release', action='store_true')
    parser.add_argument('--status', action='store_true')
    for name in ('release-id', 'run-id', 'tag', 'sha', 'controller-sha', 'channel'):
        parser.add_argument('--' + name, required=True)
    for name in ('dist', 'evidence'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, stop)
    try:
        return publish(args)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
