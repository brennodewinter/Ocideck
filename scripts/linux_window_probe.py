#!/usr/bin/env python3
"""Drive the real desktop app under X11 or a private, two-output Wayland session."""

import argparse
import csv
import ctypes as C
from dataclasses import asdict, dataclass
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from PIL import Image, ImageChops, ImageGrab, ImageStat


@dataclass(frozen=True)
class Rect:
    x: int
    y: int
    width: int
    height: int

    @property
    def bounds(self):
        return self.x, self.y, self.x + self.width, self.y + self.height


def run(*argv, data=None):
    return subprocess.run(argv, input=data, capture_output=True, check=True,
                          timeout=10).stdout


def wait_for(label, action, process, seconds=20):
    deadline = time.monotonic() + seconds
    last = None
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f'{label}: process exited with status {process.returncode}')
        try:
            result = action()
            if result:
                return result
        except (FileNotFoundError, subprocess.CalledProcessError) as error:
            last = error
        time.sleep(0.25)
    raise RuntimeError(f'Timed out waiting for {label}: {last}')


def stop(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


class X11:
    def __init__(self, evidence):
        self.manager = subprocess.Popen(['openbox', '--sm-disable'],
                                        stdout=evidence, stderr=subprocess.STDOUT)

    def window(self, pid):
        ids = run('xdotool', 'search', '--onlyvisible', '--pid', str(pid)).split()
        for window in ids:
            window = window.decode()
            info = run('xwininfo', '-id', window).decode()
            fields = [re.search(rf'{key}:\s*(-?\d+)', info)
                      for key in ('Absolute upper-left X', 'Absolute upper-left Y', 'Width', 'Height')]
            if all(fields):
                rect = Rect(*(int(field[1]) for field in fields))
                if rect.width >= 950 and rect.height >= 560:
                    return window, rect
        return None

    def resize(self, window, size):
        run('xdotool', 'windowsize', window, *map(str, size))

    @staticmethod
    def capture(rect):
        return ImageGrab.grab(bbox=rect.bounds).convert('RGB')

    @staticmethod
    def motion(x, y):
        run('xdotool', 'mousemove', str(x), str(y))

    @staticmethod
    def click():
        run('xdotool', 'click', '1')

    @staticmethod
    def cursor(_rect, _point):
        class CursorImage(C.Structure):
            _fields_ = [('x', C.c_short), ('y', C.c_short), ('width', C.c_ushort),
                        ('height', C.c_ushort), ('xhot', C.c_ushort), ('yhot', C.c_ushort),
                        ('serial', C.c_ulong), ('pixels', C.POINTER(C.c_ulong))]

        xlib = C.CDLL('libX11.so.6')
        xfixes = C.CDLL('libXfixes.so.3')
        xlib.XOpenDisplay.argtypes = [C.c_char_p]
        xlib.XOpenDisplay.restype = C.c_void_p
        xlib.XCloseDisplay.argtypes = [C.c_void_p]
        xlib.XFree.argtypes = [C.c_void_p]
        xfixes.XFixesGetCursorImage.argtypes = [C.c_void_p]
        xfixes.XFixesGetCursorImage.restype = C.POINTER(CursorImage)
        display = xlib.XOpenDisplay(None)
        if not display:
            raise RuntimeError('Could not inspect the visible X11 cursor')
        cursor = xfixes.XFixesGetCursorImage(display)
        try:
            if not cursor:
                raise RuntimeError('XFixes did not return a cursor')
            image = cursor.contents
            return image.width, image.height, tuple(image.pixels[:image.width * image.height])
        finally:
            if cursor:
                xlib.XFree(cursor)
            xlib.XCloseDisplay(display)


class Wayland:
    outputs = ('HEADLESS-1', 'HEADLESS-2')

    def __init__(self, profile, evidence):
        runtime = Path(os.environ['XDG_RUNTIME_DIR'])
        config = profile / 'sway.conf'
        config.write_text(
            'output HEADLESS-1 mode --custom 1600x1000 position 0 0 scale 1\n'
            'output HEADLESS-2 mode --custom 2880x1800 position 1600 0 scale 2\n'
            'default_border none\nworkspace 1 output HEADLESS-1\nworkspace 2 output HEADLESS-2\n'
            'seat seat0 fallback true\nxwayland disable\n'
        )
        env = dict(os.environ, WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='2',
                   WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1')
        self.manager = subprocess.Popen(['sway', '-c', str(config)], env=env,
                                        stdout=evidence, stderr=subprocess.STDOUT)
        try:
            socket = wait_for('Sway IPC socket', lambda: next(runtime.glob('sway-ipc.*.sock'), None),
                              self.manager)
            display = wait_for('Wayland display', lambda: next(
                (entry for entry in runtime.glob('wayland-*') if entry.is_socket()), None
            ), self.manager)
            os.environ.update(SWAYSOCK=str(socket), WAYLAND_DISPLAY=display.name, GDK_BACKEND='wayland')
            outputs = {item['name']: item for item in self.msg('-t', 'get_outputs')}
            for name, scale, size in zip(self.outputs, (1, 2), ((1600, 1000), (1440, 900))):
                output = outputs[name]
                if output['scale'] != scale or (output['rect']['width'], output['rect']['height']) != size:
                    raise RuntimeError(f'Sway output did not reach requested size/scale: {output}')
            self.msg('workspace', '1')
        except BaseException:
            stop(self.manager)
            raise

    @staticmethod
    def msg(*command):
        return json.loads(run('swaymsg', '-r', *command))

    def window(self, pid):
        def visit(node, output=None):
            if node['type'] == 'output':
                output = node['name']
            if node.get('pid') == pid and node.get('app_id') == 'com.dewinter.ocideck':
                return node['id'], Rect(**node['rect']), output
            for child in node.get('nodes', []) + node.get('floating_nodes', []):
                result = visit(child, output)
                if result:
                    return result
            return None
        return visit(self.msg('-t', 'get_tree'))

    def resize(self, window, output):
        self.msg(f'[con_id={window}]', 'move', 'container', 'to', 'output', output)
        self.msg(f'[con_id={window}]', 'focus')

    @staticmethod
    def capture(rect, cursor=False):
        geometry = f'{rect.x},{rect.y} {rect.width}x{rect.height}'
        options = ('-c',) if cursor else ()
        return Image.open(io.BytesIO(run('grim', *options, '-g', geometry, '-s', '1', '-'))).convert('RGB')

    def motion(self, x, y):
        self.msg('seat', 'seat0', 'cursor', 'set', str(x), str(y))

    def click(self):
        self.msg('seat', 'seat0', 'cursor', 'press', 'button1')
        self.msg('seat', 'seat0', 'cursor', 'release', 'button1')

    def cursor(self, _rect, point):
        x, y = point
        patch = Rect(x - 20, y - 20, 40, 40)
        without = self.capture(patch)
        with_cursor = self.capture(patch, cursor=True)
        return ImageChops.difference(without, with_cursor).convert('L').point(
            lambda value: 255 if value >= 12 else 0).tobytes()


def recognized(image):
    data = io.BytesIO()
    image.save(data, 'PNG')
    table = run('tesseract', 'stdin', 'stdout', '--psm', '11', 'tsv', data=data.getvalue()).decode()
    return list(csv.DictReader(io.StringIO(table), delimiter='\t'))


def settings_button(image):
    footer = image.crop((0, image.height - 100, image.width, image.height))
    for row in recognized(footer):
        if row['text'].strip().lower() in ('settings', 'instellingen'):
            return (
                int(row['left']) + int(row['width']) // 2,
                image.height - 100 + int(row['top']) + int(row['height']) // 2,
            )
    return None


def settings_search(image):
    rows = recognized(image)
    starts = {(row['block_num'], row['par_num'], row['line_num'])
              for row in rows if row['text'].lower() in ('search', 'zoek')}
    for row in rows:
        line = row['block_num'], row['par_num'], row['line_num']
        if line in starts and row['text'].lower() in ('setting', 'instelling'):
            return (int(row['left']) + int(row['width']) // 2,
                    int(row['top']) + int(row['height']) // 2)
    return None


def check_content(driver, rect, evidence, label):
    image = driver.capture(rect)
    image.save(evidence / f'{label}.png')
    width, height = image.size
    for area in ((width - 48, height // 2, width - 28, height // 2 + 20),
                 (width // 2, height - 48, width // 2 + 20, height - 28)):
        if ImageStat.Stat(image.crop(area).convert('L')).median[0] < 50:
            raise RuntimeError(f'{label}: Flutter content stops before a window edge')
    button = settings_button(image)
    if not button:
        raise RuntimeError(f'{label}: Settings is not visible in the Flutter footer')
    return rect.x + button[0], rect.y + button[1]


def exercise(args, profile):
    args.evidence.mkdir(parents=True, exist_ok=True)
    data = profile / 'data' / 'com.dewinter.ocideck'
    data.mkdir(parents=True)
    (data / 'shared_preferences.json').write_text('{"flutter.app_consent_accepted":true}')
    runtime = profile / 'runtime'
    runtime.mkdir(mode=0o700)
    os.environ.update(HOME=str(profile), XDG_DATA_HOME=str(profile / 'data'),
                      XDG_CONFIG_HOME=str(profile / 'config'), XDG_CACHE_HOME=str(profile / 'cache'),
                      XDG_RUNTIME_DIR=str(runtime), LANG='C.UTF-8', LC_ALL='C.UTF-8')
    with (args.evidence / 'compositor.log').open('w') as compositor, (args.evidence / 'app.log').open('w') as app_log:
        if args.backend == 'x11':
            os.environ['GDK_BACKEND'] = 'x11'
            driver = X11(compositor)
        else:
            driver = Wayland(profile, compositor)
        app = None
        try:
            app = subprocess.Popen([args.executable], stdout=app_log, stderr=subprocess.STDOUT)
            log = data / 'logs' / 'ocideck.log'
            wait_for('first rasterized frame', lambda: re.search(
                r' INFO opstart: eerste frame \(\+\d+ ms\)', log.read_text()), app)
            window = wait_for('visible native window', lambda: driver.window(app.pid), app)
            sizes = ((1060, 700), (1420, 900), (1060, 700))
            targets = sizes if args.backend == 'x11' else ('HEADLESS-1', 'HEADLESS-2', 'HEADLESS-1')
            results = []
            for index, target in enumerate(targets):
                driver.resize(window[0], target)

                def configured():
                    state = driver.window(app.pid)
                    if not state:
                        return None
                    rect = state[1]
                    if args.backend == 'x11':
                        return rect if (rect.width, rect.height) == target else None
                    expected = (1600, 1000) if target == 'HEADLESS-1' else (1440, 900)
                    if state[2] == target and (rect.width, rect.height) == expected:
                        return rect
                    return None

                rect = wait_for(f'logical geometry {target}', configured, app)
                time.sleep(0.75)
                point = check_content(driver, rect, args.evidence, f'window-{index}')
                results.append({'target': target, **asdict(rect)})
                if index != 1:
                    continue
                driver.motion(*point)
                driver.click()
                search = wait_for('Settings search after a native mouse click',
                                  lambda: settings_search(driver.capture(rect)), app)
                driver.capture(rect).save(args.evidence / 'settings-after-click.png')
                search_point = rect.x + search[0], rect.y + search[1]
                empty = search_point[0], search_point[1] - 35
                driver.motion(*empty)
                time.sleep(0.30)
                cursor_before = driver.cursor(rect, empty)
                if not any(cursor_before):
                    raise RuntimeError('Could not observe the initial native cursor')
                driver.motion(*search_point)
                cursor_after = wait_for('a changed native cursor over Settings search', lambda: (
                    driver.cursor(rect, search_point) != cursor_before
                ), app)
                results[-1].update(cursor_changed=cursor_after, clicked=True)
                if args.backend == 'x11':
                    run('xdotool', 'key', 'Escape')
                else:
                    # Closing the popup by clicking outside keeps input native.
                    driver.motion(rect.x + 25, rect.y + 90)
                    driver.click()
                def welcome_again():
                    image = driver.capture(rect)
                    return settings_button(image) if not settings_search(image) else None

                wait_for('welcome screen after Settings closes', welcome_again, app)
            (args.evidence / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
        finally:
            stop(app)
            stop(driver.manager)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('backend', choices=('x11', 'wayland'))
    parser.add_argument('executable', type=lambda value: Path(value).resolve(strict=True))
    parser.add_argument('evidence', type=Path)
    with tempfile.TemporaryDirectory(prefix='ocideck-window-') as workspace:
        exercise(parser.parse_args(), Path(workspace))
