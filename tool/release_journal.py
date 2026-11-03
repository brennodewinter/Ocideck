#!/usr/bin/env python3
"""Durable local release history. Explicit commands only; never retries work.

The lock protects journal mutations only. Controllers must separately lease any
external action across its entire lifetime, including publication and dispatch.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import json
import os
import re
from pathlib import Path
import tempfile
import sys

from release_channel import identity, file_hash, no_duplicates


@contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(path) + '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('journal already locked by another writer') from error
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def atomic_write(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, sort_keys=True, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read(path):
    if path.is_symlink():
        raise ValueError('journal must not be a symlink')
    data = json.loads(path.read_text(), object_pairs_hook=no_duplicates)
    if (not isinstance(data, dict)
            or set(data) != {'schema', 'tag', 'source', 'channel', 'workflow_sha256', 'events'}
            or type(data['schema']) is not int or data['schema'] != 1
            or not isinstance(data['events'], list)):
        raise ValueError('invalid journal')
    if not all(isinstance(data[key], str) for key in ('tag', 'source', 'channel')):
        raise ValueError('invalid identity types')
    identity(data['tag'], data['source'], data['channel'])
    if not isinstance(data.get('workflow_sha256'), str) or not re.fullmatch(r'[0-9a-f]{64}', data['workflow_sha256']):
        raise ValueError('invalid workflow digest')
    for event in data['events']:
        if not isinstance(event, dict) or set(event) != {'phase', 'state', 'evidence', 'at'}:
            raise ValueError('invalid journal event')
        if not valid_phase(event['phase']) or not isinstance(event['at'], str):
            raise ValueError('invalid phase or timestamp type')
        try:
            timestamp = datetime.fromisoformat(event['at'])
        except ValueError as error:
            raise ValueError('invalid event timestamp') from error
        if timestamp.tzinfo is None or timestamp.utcoffset() != timezone.utc.utcoffset(timestamp):
            raise ValueError('event timestamp must use UTC')
        if event['state'] not in ('started', 'completed', 'failed', 'cancelled') or not isinstance(event['evidence'], dict):
            raise ValueError('invalid event state or evidence')
        if event['state'] == 'completed' and not event['evidence']:
            raise ValueError('completed event has no evidence')
        for name, digest in event['evidence'].items():
            if not Path(name).is_absolute() or not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
                raise ValueError('invalid evidence reference')
    return data


def initialize(args):
    identity(args.tag, args.sha, args.channel)
    digest = file_hash(args.workflow)
    wanted = dict(schema=1, tag=args.tag, source=args.sha, channel=args.channel,
                  workflow_sha256=digest, events=[])
    with locked(args.journal):
        if args.journal.is_symlink():
            raise ValueError('journal must not be a symlink')
        if args.journal.exists():
            current = read(args.journal)
            if any(current.get(key) != value for key, value in wanted.items() if key != 'events'):
                raise ValueError('immutable journal identity mismatch')
            return current
        atomic_write(args.journal, wanted)
    return wanted


def evidence(paths):
    result = {}
    for path in paths:
        if path.is_symlink():
            raise ValueError('evidence must not be a symlink')
        name = str(path.resolve(strict=True))
        if name in result:
            raise ValueError('duplicate evidence path')
        result[name] = file_hash(path)
    return result


def verify(data):
    checked = 0
    for event in data['events']:
        for name, digest in event['evidence'].items():
            path = Path(name)
            if not path.is_absolute() or path.is_symlink() or path.resolve(strict=True) != path or file_hash(path) != digest:
                raise ValueError('evidence changed: ' + name)
            checked += 1
    return {'valid': True, 'evidence_checked': checked}


def valid_phase(value):
    return isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]+', value) is not None


def record(args):
    if not valid_phase(args.phase):
        raise ValueError('invalid phase name')
    with locked(args.journal):
        data = read(args.journal)
        hashes = evidence(args.evidence)
        latest = next((e for e in reversed(data['events']) if e['phase'] == args.phase), None)
        if latest and latest['state'] == args.state and latest['evidence'] == hashes:
            verify({'events': [latest]})
            return data
        if args.state != 'started' and (not latest or latest['state'] != 'started'):
            raise ValueError('terminal phase requires a preceding explicit start')
        if args.state == 'started' and latest and latest['state'] in ('started', 'completed'):
            raise ValueError('phase already started or completed')
        if args.state == 'completed' and not hashes:
            raise ValueError('completed phase requires durable evidence')
        data['events'].append(dict(phase=args.phase, state=args.state, evidence=hashes,
                                  at=datetime.now(timezone.utc).isoformat()))
        atomic_write(args.journal, data)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--journal', type=Path, required=True)
    commands = parser.add_subparsers(dest='command', required=True)
    init = commands.add_parser('init')
    for name in ('tag', 'sha', 'channel'):
        init.add_argument('--' + name, required=True)
    init.add_argument('--workflow', type=Path, required=True)
    rec = commands.add_parser('record')
    rec.add_argument('--phase', required=True)
    rec.add_argument('--state', choices=['started', 'completed', 'failed', 'cancelled'], required=True)
    rec.add_argument('--evidence', type=Path, action='append', default=[])
    commands.add_parser('status')
    commands.add_parser('verify-evidence')
    args = parser.parse_args()
    try:
        if args.command == 'init':
            result = initialize(args)
        elif args.command == 'record':
            result = record(args)
        else:
            with locked(args.journal):
                result = read(args.journal)
                if args.command == 'verify-evidence':
                    result = verify(result)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
