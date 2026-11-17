#!/usr/bin/env python3
"""Run one CI command with redacted logs, heartbeats and its real exit status."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time


def redactor(environment):
    sensitive = re.compile(r'TOKEN|SECRET|PASSWORD|PRIVATE_KEY|API_KEY|ACCESS_KEY|AUTHORIZATION|CREDENTIAL', re.I)
    values = {line for key, value in environment.items() if sensitive.search(key)
              for line in [value, *value.splitlines()] if len(line) >= 4}

    def redact(text):
        for value in sorted(values, key=len, reverse=True):
            text = text.replace(value, '[REDACTED]')
        return re.sub(r'(?i)(authorization:\s*(?:bearer|basic)\s+)\S+', r'\1[REDACTED]', text)
    return redact


def run(args):
    if not re.fullmatch(r'[a-z0-9-]+', args.label):
        raise ValueError('label must contain only lowercase letters, digits and hyphens')
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or args.heartbeat_seconds <= 0 or args.terminate_grace <= 0:
        raise ValueError('command and positive intervals are required')
    directory = Path(args.directory)
    directory.mkdir(parents=True, exist_ok=True)
    redact = redactor(os.environ)
    started = time.monotonic()
    status = {'state': 'running', 'label': args.label,
              'command': [redact(arg) for arg in command],
              'started_at': datetime.now(timezone.utc).isoformat()}
    state_file = directory / (args.label + '.status.json')
    last_output = [started, '']
    failures = []
    received = [None]
    interrupted_at = [None]
    output_lock = threading.Lock()

    def save():
        status['updated_at'] = datetime.now(timezone.utc).isoformat()
        status['elapsed_seconds'] = round(time.monotonic() - started, 3)
        with output_lock:
            status['last_output'] = last_output[1]
            status['quiet_seconds'] = round(time.monotonic() - last_output[0], 3)
        temporary = state_file.with_suffix('.tmp')
        temporary.write_text(json.dumps(status, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temporary.replace(state_file)

    environment = dict(os.environ, PYTHONUNBUFFERED='1')
    try:
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True, encoding='utf-8', errors='backslashreplace',
                                 env=environment, start_new_session=True)
    except OSError as error:
        status.update(state='failed', exit_code=127, error=redact(str(error)))
        save()
        print(redact(str(error)), file=sys.stderr, flush=True)
        return 127
    status['pid'] = child.pid

    def forward(number, _frame):
        if received[0] is None:
            received[0] = number
            interrupted_at[0] = time.monotonic()
        try:
            os.killpg(child.pid, number)
        except ProcessLookupError:
            pass

    previous = {number: signal.signal(number, forward) for number in (signal.SIGTERM, signal.SIGINT)}

    def emit(console, text):
        try:
            console.write(text)
            console.flush()
        except OSError as error:
            message = redact(str(error))
            if message not in failures:
                failures.append(message)

    def pump(stream, name, console):
        try:
            with (directory / (args.label + '.' + name + '.log')).open('w', encoding='utf-8') as log:
                for line in stream:
                    line = redact(line)
                    log.write(line)
                    log.flush()
                    emit(console, line)
                    with output_lock:
                        last_output[:] = [time.monotonic(), line.rstrip()[-500:]]
        except OSError as error:
            failures.append(redact(str(error)))
        finally:
            stream.close()

    threads = [threading.Thread(target=pump, args=(child.stdout, 'stdout', sys.stdout), daemon=True),
               threading.Thread(target=pump, args=(child.stderr, 'stderr', sys.stderr), daemon=True)]
    for thread in threads:
        thread.start()
    save()
    next_heartbeat = started
    try:
        while child.poll() is None:
            now = time.monotonic()
            if received[0] is not None and now - interrupted_at[0] >= args.terminate_grace:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if now >= next_heartbeat:
                save()
                message = f"[ci-gate:{args.label}] running pid={child.pid} elapsed={status['elapsed_seconds']}s quiet={status['quiet_seconds']}s\n"
                with (directory / (args.label + '.heartbeat.log')).open('a', encoding='utf-8') as log:
                    log.write(message)
                emit(sys.stdout, message)
                next_heartbeat = now + args.heartbeat_seconds
            time.sleep(min(0.1, args.heartbeat_seconds))
        for thread in threads:
            thread.join(timeout=2)
        raw_code = child.returncode
        code = 128 + received[0] if received[0] is not None else (128 - raw_code if raw_code < 0 else raw_code)
        if failures and code == 0:
            code = 74
        end_signal = received[0] if received[0] is not None else (-raw_code if raw_code < 0 else None)
        status.update(state='interrupted' if end_signal else ('passed' if code == 0 else 'failed'),
                      child_exit_code=raw_code, exit_code=code, signal=end_signal,
                      logs_complete=not any(thread.is_alive() for thread in threads), log_errors=failures)
        save()
        emit(sys.stdout, f'[ci-gate:{args.label}] {status["state"]} exit={code} child_exit={raw_code}\n')
        return code
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--directory', default='build/ci-diagnostics')
    parser.add_argument('--heartbeat-seconds', type=float, default=30)
    parser.add_argument('--terminate-grace', type=float, default=10)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    return run(parser.parse_args())


if __name__ == '__main__':
    sys.exit(main())
