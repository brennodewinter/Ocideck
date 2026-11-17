"""Explicit live cancellation probe against an already owned source server.

Provide its PID and external report path; observes only, never signals processes.
No provider text/audio is saved. Not a substitute for release-UI cancellation.
"""
import argparse
import http.client
import json
import pathlib
import subprocess
import tempfile
import time


def processes():
    rows = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,stat='],
                          check=True, capture_output=True).stdout.splitlines()
    return [(int(p), int(parent), int(group), state.decode())
            for p, parent, group, state in (row.split() for row in rows)]


def probe(server_pid, output):
    before = set(pathlib.Path(tempfile.gettempdir()).glob('ocideck-youtube-*'))
    connection = http.client.HTTPConnection('127.0.0.1', 8866, timeout=130)
    connection.request('POST', '/ocideck-youtube/v1/audio',
                       json.dumps({'video_id': 'M7lc1UVf-VE', 'start_ms': 10000, 'end_ms': 35000}),
                       headers={'Content-Type': 'application/json'})
    deadline = time.monotonic() + 15
    owned = []
    while time.monotonic() < deadline:
        owned = [row for row in processes() if row[1] == server_pid and not row[3].startswith('Z')]
        if owned:
            break
        time.sleep(.02)
    if not owned:
        connection.close()
        raise RuntimeError('No actual provider child observed; cancellation not proved')
    groups = {row[2] for row in owned}
    watch = time.monotonic()
    connection.close()
    deadline = watch + 10
    while time.monotonic() < deadline:
        alive = [row for row in processes() if row[2] in groups and not row[3].startswith('Z')]
        staging = set(pathlib.Path(tempfile.gettempdir()).glob('ocideck-youtube-*')) - before
        if not alive and not staging:
            break
        time.sleep(.05)
    else:
        raise RuntimeError('Provider group/staging survived peer cancellation')
    elapsed = round((time.monotonic() - watch) * 1000)
    healthy = http.client.HTTPConnection('127.0.0.1', 8866, timeout=130)
    try:
        healthy.request('POST', '/ocideck-youtube/v1/metadata', json.dumps({'video_id': 'jNQXAC9IVRw'}), headers={'Content-Type': 'application/json'})
        response = healthy.getresponse()
        data = json.load(response)
        if response.status != 200 or data.get('video_id') != 'jNQXAC9IVRw':
            raise RuntimeError('Capacity not recovered after actual cancellation')
    finally:
        healthy.close()
    output.write_text(json.dumps({'scope': 'real HTTP peer-close during actual provider extraction, not release UI', 'observed_provider_groups': len(groups), 'live_group_members_after_cancel': 0, 'new_private_staging_after_cancel': 0, 'cancel_cleanup_ms': elapsed, 'subsequent_metadata_succeeded': True}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server-pid', type=int, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    probe(args.server_pid, args.output)
