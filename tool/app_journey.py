#!/usr/bin/env python3
"""One native app journey, with bounded subprocesses and retained evidence (#3214)."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def scenarios(device, full):
    """PRs exercise two real processes; nights include persistence and navigation."""
    launcher = 'run' if device == 'windows' else '--disable-dart-dev'
    result = [('lifecycle', ['dart', launcher, 'tool/run_desktop_smoke.dart', device]
               + (['--roundtrip'] if full else []), None)]
    if full:
        result.append(('navigation', 'document_navigation_profile_test',
                       'document_navigation_driver'))
        if device == 'windows':
            result.append(('video', 'windows_video_navigation_test',
                           'windows_video_driver'))
    return result


def stop_process_group(child):
    """Stop only the session created for this command, including stubborn children."""
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        child.wait()
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        child.poll()
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            child.wait()
            return
        time.sleep(0.05)
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait(timeout=5)


def run_command(command, log, environment=None, timeout=3600):
    """Keep compiler/app output even when a child fails or times out."""
    with log.open('w', encoding='utf-8') as stream:
        stream.write('Command: ' + repr(command) + '\n')
        stream.flush()
        # Windows' Flutter/Dart launchers are .bat files; COMSPEC resolves them.
        if os.name == 'nt':
            child = subprocess.run(command, cwd=ROOT, env=environment,
                                   stdout=stream, stderr=subprocess.STDOUT,
                                   timeout=timeout, shell=True)
        else:
            child = subprocess.Popen(command, cwd=ROOT, env=environment,
                                     stdout=stream, stderr=subprocess.STDOUT,
                                     start_new_session=True)
            try:
                child.wait(timeout=timeout)
            except BaseException:
                stop_process_group(child)
                raise
            if child.returncode:
                stop_process_group(child)
    if child.returncode:
        raise subprocess.CalledProcessError(child.returncode, command)


def drive(device, target, driver, evidence):
    target = f'integration_test/{target}.dart'
    args = ['flutter', 'drive', '--profile', '-d', device,
            f'--target={target}', f'--driver=test_driver/{driver}.dart']
    if device == 'macos':
        run_command(['bash', 'scripts/with_macos_flutter_semantics_fix.sh',
                     'build', 'macos', '--profile', f'--target={target}'],
                    evidence / 'build.log')
        args.append('--use-application-binary=build/macos/Build/Products/Profile/OciDeck.app')
    if device == 'windows' and 'windows_video_navigation_test.dart' in target:
        args.append('--dart-define=OCIDECK_LIVE_VIDEO_PROBE=false')
    environment = os.environ.copy()
    report = str((evidence / 'result.json').resolve())
    environment['NAVIGATION_RESULT_FILE'] = report
    environment['VIDEO_RESULT_FILE'] = report
    run_command(args, evidence / 'run.log', environment)
    data = json.loads(Path(report).read_text(encoding='utf-8'))
    if not isinstance(data, dict) or not data:
        raise RuntimeError('The app driver did not supply scenario evidence')


def journey(device, full, evidence):
    evidence.mkdir(parents=True, exist_ok=True)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                   text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT))
    report = dict(source_commit=head, working_tree_dirty=dirty, platform=device,
                  mode='full' if full else 'short', scenarios=[], success=False)
    try:
        for name, target, driver in scenarios(device, full):
            output = evidence / name
            output.mkdir(parents=True, exist_ok=True)
            # A previous successful run must never rescue absent new evidence.
            result = output / 'result.json'
            result.unlink(missing_ok=True)
            row = dict(name=name, success=False)
            report['scenarios'].append(row)
            started = time.monotonic()
            try:
                if driver:
                    drive(device, target, driver, output)
                else:
                    try:
                        run_command(target, output / 'run.log')
                    finally:
                        existing = ROOT / 'build' / ('desktop-roundtrip' if full else 'desktop-smoke')
                        if existing.exists():
                            shutil.copytree(existing, output / 'processes', dirs_exist_ok=True)
                row['success'] = True
            finally:
                row['seconds'] = round(time.monotonic() - started, 2)
        report['success'] = True
    finally:
        (evidence / 'journey.json').write_text(json.dumps(report, indent=2) + '\n',
                                             encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--evidence', type=Path, default=ROOT / 'build/app-journey')
    args = parser.parse_args()
    device = {'Darwin': 'macos', 'Linux': 'linux', 'Windows': 'windows'}[platform.system()]
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)
    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        result = journey(device, args.full, args.evidence.resolve())
    finally:
        signal.signal(signal.SIGTERM, previous)
    print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
    main()
