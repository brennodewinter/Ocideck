"""Real HTTP disconnect while its owned native worker is alive; no fake provider."""
import argparse
import hashlib
import http.client
import json
from pathlib import Path
import re
import subprocess
import time

BOUNDARY = 'ocideck-native-cancel-probe'
PATH = '/ocideck-asr/v1/transcribe'
HEADERS = {'Content-Type': 'multipart/form-data; boundary=' + BOUNDARY}


def multipart(audio, mode=None):
    fields = [('diarize', b'true'), ('language', b'nl'), ('file', audio)]
    if mode:
        fields.append(('language_mode', mode))
    result = bytearray()
    for name, data in fields:
        result.extend(('--' + BOUNDARY + '\r\nContent-Disposition: form-data; name="' + name + '"' +
                       ('; filename="audio.wav"' if name == 'file' else '') + '\r\n\r\n').encode())
        result.extend(data)
        result.extend(b'\r\n')
    result.extend(('--' + BOUNDARY + '--\r\n').encode())
    return result


def status():
    connection = http.client.HTTPConnection('127.0.0.1', 8093, timeout=10)
    try:
        connection.request('POST', PATH, multipart(b'invalid', b'unsupported'), HEADERS)
        response = connection.getresponse()
        response.read()
        return response.status
    finally:
        connection.close()


def children(pid):
    result = subprocess.run(['pgrep', '-P', str(pid)], capture_output=True, text=True, check=False)
    return [int(value) for value in result.stdout.split()] if result.returncode == 0 else []


def worker(pid):
    for child in children(pid):
        result = subprocess.run(['ps', '-p', str(child), '-o', 'command='],
                                capture_output=True, text=True, check=False)
        command = result.stdout.strip()
        if 'nemo_worker.py' not in command or '--probe' in command:
            continue
        match = re.search(r'--audio (.+?) --output ', command)
        if match:
            audio = Path(match.group(1))
            if audio.is_file() and audio.name == 'audio.wav' and audio.parent.name.startswith('ocideck-diar-'):
                return child, audio.parent
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fixture', type=Path)
    parser.add_argument('server_pid', type=int)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    audio = args.fixture.read_bytes()
    connection = http.client.HTTPConnection('127.0.0.1', 8093, timeout=30)
    connection.request('POST', PATH, multipart(audio), HEADERS)
    deadline, observed = time.monotonic() + 20, None
    while time.monotonic() < deadline and observed is None:
        observed = worker(args.server_pid)
        if observed is None:
            time.sleep(.05)
    if observed is None:
        connection.close()
        raise SystemExit('No active native worker observed; no cancellation claim')
    active, directory = observed
    before = status()
    start = time.monotonic()
    connection.close()
    statuses = []
    while time.monotonic() - start < 10:
        current = status()
        statuses.append(current)
        if current != 429:
            break
        time.sleep(.1)
    report = {'scope': 'real loopback HTTP disconnect with its actual native worker observed',
              'fixture_sha256': hashlib.sha256(audio).hexdigest(),
              'native_worker_seen': True, 'busy_before_disconnect': before == 429,
              'release_seconds': time.monotonic() - start,
              'worker_disappeared': active not in children(args.server_pid),
              'temporary_audio_and_activity_removed': not directory.exists(),
              'statuses_after_disconnect': statuses}
    report['pass'] = (report['busy_before_disconnect'] and report['worker_disappeared'] and
                      report['temporary_audio_and_activity_removed'] and statuses[-1] == 422)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    if not report['pass']:
        raise SystemExit('HTTP cancellation did not release and clean its worker')


if __name__ == '__main__':
    main()
