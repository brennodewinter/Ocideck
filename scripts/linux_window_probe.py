#!/usr/bin/env python3
"""Drive the real desktop app under X11 or a private, two-output Wayland session."""

import argparse
import csv
import ctypes as C
from dataclasses import asdict, dataclass
import io
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from PIL import Image, ImageGrab, ImageOps, ImageStat

from linux_startup_log import startup_frame


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
        try:
            wait_for('Openbox to manage the X11 display', lambda: re.search(
                rb'window id # 0x[1-9a-f][0-9a-f]*',
                run('xprop', '-root', '_NET_SUPPORTING_WM_CHECK')), self.manager)
        except (RuntimeError, subprocess.TimeoutExpired):
            stop(self.manager)
            raise

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
    def cursor():
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

    def __init__(self, profile, evidence, trace):
        self.trace = trace
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

            def outputs_ready():
                outputs = {item['name']: item for item in self.msg('-t', 'get_outputs')}
                for name, scale, size in zip(self.outputs, (1, 2), ((1600, 1000), (1440, 900))):
                    output = outputs.get(name)
                    if not output or output['scale'] != scale:
                        return False
                    if (output['rect']['width'], output['rect']['height']) != size:
                        return False
                return True

            wait_for('Sway outputs at the requested sizes and scales', outputs_ready, self.manager)
            self.msg('workspace', '1')
            self.pointer = subprocess.Popen([os.environ['OCIDECK_WAYLAND_POINTER']],
                                            stdout=evidence, stderr=subprocess.STDOUT)
            try:
                wait_for('virtual Wayland pointer', self.pointer_attached, self.pointer)
            except BaseException:
                stop(self.pointer)
                raise
        except BaseException:
            stop(self.manager)
            raise

    def pointer_attached(self):
        return any(seat.get('capabilities', 0) & 1 for seat in self.msg('-t', 'get_seats'))

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

    def windows(self, pid):
        def visit(node, output=None):
            if node['type'] == 'output':
                output = node['name']
            if node.get('pid') == pid and output in self.outputs:
                yield {'id': node['id'], 'output': output, 'rect': node['rect'],
                       'fullscreen': node.get('fullscreen_mode', 0)}
            for child in node.get('nodes', []) + node.get('floating_nodes', []):
                yield from visit(child, output)
        return list(visit(self.msg('-t', 'get_tree')))

    @staticmethod
    def capture(rect):
        geometry = f'{rect.x},{rect.y} {rect.width}x{rect.height}'
        return Image.open(io.BytesIO(run('grim', '-g', geometry, '-s', '1', '-'))).convert('RGB')

    def motion(self, x, y):
        self.msg('seat', 'seat0', 'cursor', 'set', str(x), str(y))

    def click(self):
        self.msg('seat', 'seat0', 'cursor', 'press', 'button1')
        self.msg('seat', 'seat0', 'cursor', 'release', 'button1')

    def cursor(self):
        # Screencopy need not composite the cursor on a headless output.
        # GTK sends the actual cursor surface, buffer and hotspot to Wayland.
        cursor = None
        buffers = {}
        with self.trace.open() as stream:
            for line in stream:
                if match := re.search(
                    r'wl_pointer@\d+\.set_cursor\(\d+, wl_surface@(\d+), (-?\d+), (-?\d+)\)',
                    line,
                ):
                    cursor = match.groups()
                if match := re.search(r'wl_surface@(\d+)\.attach\(wl_buffer@(\d+),', line):
                    surface, buffer = match.groups()
                    buffers[surface] = buffer
        if cursor:
            surface, x, y = cursor
            return surface, buffers.get(surface), x, y
        return None


def recognized(image, scale=1, faint=False):
    data = io.BytesIO()
    text_image = image.convert('L')
    if faint:
        text_image = text_image.point(lambda value: 255 if value >= 218 else 0)
    else:
        text_image = ImageOps.autocontrast(text_image)
    if scale > 1:
        text_image = text_image.resize((image.width * scale, image.height * scale), Image.Resampling.LANCZOS)
    text_image.save(data, 'PNG')
    table = run('tesseract', 'stdin', 'stdout', '--psm', '11', 'tsv', data=data.getvalue()).decode()
    rows = list(csv.DictReader(io.StringIO(table), delimiter='\t'))
    if scale > 1:
        for row in rows:
            for field in ('left', 'top', 'width', 'height'):
                row[field] = str(int(row[field]) // scale)
    return rows


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
    left = image.width // 2
    header = image.crop((left, 0, 9 * image.width // 10, image.height // 3))
    rows = recognized(header, scale=3, faint=True)
    starts = {(row['block_num'], row['par_num'], row['line_num'])
              for row in rows if row['text'].lower() in ('search', 'zoek')}
    for row in rows:
        line = row['block_num'], row['par_num'], row['line_num']
        if line in starts and row['text'].lower() in ('setting', 'instelling'):
            return (left + int(row['left']) + int(row['width']) // 2,
                    int(row['top']) + int(row['height']) // 2)
    return None


def check_content(driver, rect, evidence, label):
    # A compositor can report the new size before Flutter paints at that size.
    # Poll the visible content, keeping the last frame as evidence on failure.
    deadline = time.monotonic() + 12
    reason = 'Flutter content stops before a window edge'
    while time.monotonic() < deadline:
        image = driver.capture(rect)
        image.save(evidence / f'{label}.png')
        width, height = image.size
        probes = (
            (width - 48, height // 2, width - 28, height // 2 + 20),
            (width // 2, height - 48, width // 2 + 20, height - 28),
        )
        if all(ImageStat.Stat(image.crop(area).convert('L')).median[0] >= 50 for area in probes):
            reason = 'Settings is not visible in the Flutter footer'
            button = settings_button(image)
            if button:
                return rect.x + button[0], rect.y + button[1]
        else:
            reason = 'Flutter content stops before a window edge'
        time.sleep(0.35)
    raise RuntimeError(f'{label}: {reason}')


def presentation_deck(profile):
    fixture = profile / 'dualprobe.md'
    fixture.write_text('---\nmarp: true\ntitle: Dualprobe\n---\n\n'
                       '# Dualprobe\n\n- Presenter and audience\n')
    return fixture


def exercise_presentation(driver, app, evidence):
    rows = []
    report = evidence / 'presentation-displays.json'

    def note(step, windows):
        outputs = [{'name': output['name'], 'scale': output['scale']}
                   for output in driver.msg('-t', 'get_outputs') if output['active']]
        rows.append({'step': step, 'windows': windows, 'outputs': outputs})
        report.write_text(json.dumps(rows, indent=2) + '\n')

    def text_position(rect, name):
        frame = driver.capture(rect)
        frame.save(evidence / 'last-presenter.png')
        # Tesseract keeps punctuation on words such as the command hint
        # 'commando…' and the opened tab's 'dualprobe.md' label.
        for row in recognized(frame):
            if name in re.findall(r'[a-z0-9]+', row['text'].casefold()):
                return (rect.x + int(row['left']) + int(row['width']) // 2,
                        rect.y + int(row['top']) + int(row['height']) // 2)
        return None

    def open_deck():
        state = driver.window(app.pid)
        if state and state[2] == 'HEADLESS-1' and text_position(state[1], 'dualprobe'):
            return state
        return None

    main, rect, _ = wait_for('opened deck on left output', open_deck, app, seconds=60)

    def focus_presenter():
        replies = driver.msg(f'[con_id={main}]', 'focus')
        if not replies or not all(reply.get('success') for reply in replies):
            raise RuntimeError(f'Sway could not focus the presenter: {replies}')

    def press_keys(*keys):
        # GTK must bind the new keyboard before the first event and retain it
        # through release. Each wtype process creates a keyboard on this seat.
        run('wtype', '-s', '700', *keys, '-s', '350')

    def start():
        focus_presenter()
        press_keys('-M', 'ctrl', '-k', 'k', '-m', 'ctrl')
        wait_for('command palette', lambda: text_position(rect, 'commando'), app)
        command = wait_for('Presenteren command',
                           lambda: text_position(rect, 'presenteren'), app)
        driver.motion(*command)
        driver.click()

    def separate():
        windows = driver.windows(app.pid)
        presenter = next((win for win in windows if win['id'] == main), None)
        audience = [win for win in windows if win['id'] != main]
        if (presenter and presenter['output'] == 'HEADLESS-1' and
                len(audience) == 1 and audience[0]['output'] == 'HEADLESS-2' and
                audience[0]['fullscreen'] and audience[0]['rect']['width'] == 1440):
            return windows
        return None

    def wait_for_placement(step):
        try:
            note(step, wait_for(step, separate, app))
        except RuntimeError:
            note(f'{step}-failed', driver.windows(app.pid))
            driver.capture(rect).save(evidence / 'presentation-placement-failure.png')
            raise

    start()
    wait_for_placement('started-on-separate-outputs')
    driver.msg('output', 'HEADLESS-2', 'disable')

    def removed():
        outputs = driver.msg('-t', 'get_outputs')
        if any(output['name'] == 'HEADLESS-2' and output['active'] for output in outputs):
            return None
        windows = driver.windows(app.pid)
        return windows if all(window['output'] == 'HEADLESS-1' for window in windows) else None

    note('audience-output-disabled', wait_for('native output removal', removed, app))
    driver.msg('output', 'HEADLESS-2', 'enable')

    def reconnected():
        outputs = driver.msg('-t', 'get_outputs')
        return any(output['name'] == 'HEADLESS-2' and output['active'] and
                   output['scale'] == 2 for output in outputs)

    wait_for('second output restored at 200 percent', reconnected, app)
    note('audience-output-enabled', driver.windows(app.pid))

    def finish():
        focus_presenter()
        press_keys('-k', 'Escape')
        try:
            wait_for('audience closed and editor visible',
                     lambda: open_deck() if len(driver.windows(app.pid)) == 1 else None, app)
        except RuntimeError:
            note('presentation-exit-failed', driver.windows(app.pid))
            driver.capture(rect).save(evidence / 'presentation-exit-failure.png')
            raise

    finish()
    note('presentation-ended', driver.windows(app.pid))
    start()
    wait_for_placement('presentation-restarted')
    finish()
    note('final-presentation-ended', driver.windows(app.pid))


def exercise(args, profile):
    args.evidence.mkdir(parents=True, exist_ok=True)
    data = profile / 'data' / 'com.dewinter.ocideck'
    data.mkdir(parents=True)
    preferences = {'flutter.app_consent_accepted': True}
    if args.presentation:
        preferences['flutter.languageCode'] = 'nl'
    (data / 'shared_preferences.json').write_text(json.dumps(preferences))
    runtime = profile / 'runtime'
    runtime.mkdir(mode=0o700)
    (profile / 'cache').mkdir(mode=0o700)
    os.environ.update(HOME=str(profile), XDG_DATA_HOME=str(profile / 'data'),
                      XDG_CONFIG_HOME=str(profile / 'config'), XDG_CACHE_HOME=str(profile / 'cache'),
                      XDG_RUNTIME_DIR=str(runtime), LANG='C.UTF-8', LC_ALL='C.UTF-8',
                      LIBGL_ALWAYS_SOFTWARE='1', OMP_THREAD_LIMIT='1',
                      XCURSOR_THEME='Adwaita', XCURSOR_SIZE='24')
    x11_display = os.environ.get('DISPLAY')
    os.environ['XDG_SESSION_TYPE'] = args.backend
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'SWAYSOCK'):
        os.environ.pop(key, None)
    # dbus-run-session starts before the app profile exists. Give activated
    # services the same private home and runtime directory as OciDeck.
    run('dbus-update-activation-environment', 'HOME', 'XDG_DATA_HOME',
        'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR')
    run('gdbus', 'call', '--session', '--timeout', '5', '--dest', 'org.freedesktop.secrets',
        '--object-path', '/org/freedesktop/secrets', '--method', 'org.freedesktop.DBus.Peer.Ping')
    with (args.evidence / 'compositor.log').open('w') as compositor, (args.evidence / 'app.log').open('w') as app_log:
        if args.backend == 'x11':
            if not x11_display:
                raise RuntimeError('X11 probe requires its private Xvfb display')
            os.environ.update(DISPLAY=x11_display, GDK_BACKEND='x11')
            driver = X11(compositor)
        else:
            driver = Wayland(profile, compositor, args.evidence / 'app.log')
        app = None
        try:
            session = {
                'backend': args.backend,
                'compositor': 'sway-headless' if args.backend == 'wayland' else 'openbox-xvfb',
                'source_commit': os.environ.get('OCIDECK_PROBE_SOURCE_COMMIT'),
                'executable_sha256': hashlib.sha256(args.executable.read_bytes()).hexdigest(),
                'gdk_backend': os.environ['GDK_BACKEND'],
                'display': os.environ.get('DISPLAY'),
                'wayland_display': os.environ.get('WAYLAND_DISPLAY'),
            }
            (args.evidence / 'session.json').write_text(json.dumps(session, indent=2) + '\n')
            app_env = dict(os.environ)
            if args.backend == 'wayland':
                app_env['WAYLAND_DEBUG'] = 'client'
            launch_args = [args.executable]
            if args.presentation:
                launch_args.append(presentation_deck(profile))
            app = subprocess.Popen(launch_args, env=app_env, stdout=app_log,
                                   stderr=subprocess.STDOUT)
            log = data / 'logs' / 'ocideck.log'
            # Allow GTK and the software renderer to initialize on a busy runner.
            launch_timeout = 90
            wait_for('first rasterized frame', lambda: startup_frame(log), app,
                seconds=launch_timeout)
            time.sleep(3)
            if app.poll() is not None or not startup_frame(log):
                raise RuntimeError('OciDeck did not stay running after its first frame')
            session.update(first_frame=True, stayed_running=True)
            (args.evidence / 'session.json').write_text(json.dumps(session, indent=2) + '\n')
            if args.presentation:
                exercise_presentation(driver, app, args.evidence)
                startup_frame(log)
                return
            try:
                window = wait_for('visible native window', lambda: driver.window(app.pid), app,
                                  seconds=launch_timeout)
            except RuntimeError:
                if args.backend == 'x11':
                    with (args.evidence / 'x11-window-tree.log').open('w') as tree:
                        subprocess.run(['timeout', '5s', 'xwininfo', '-root', '-tree'],
                                       stdout=tree, stderr=subprocess.STDOUT, check=False)
                raise
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

                startup_frame(log)
                rect = wait_for(f'logical geometry {target}', configured, app)
                time.sleep(0.75)
                point = check_content(driver, rect, args.evidence, f'window-{index}')
                results.append({'target': target, 'scale': (2 if target == 'HEADLESS-2' else 1), **asdict(rect)})
                print(f'{args.backend} {target}: {rect.width}x{rect.height} with visible Flutter content', flush=True)
                if index != 1:
                    continue
                print(f'{args.backend}: clicking Settings at {point}', flush=True)
                driver.motion(*point)
                time.sleep(0.2)
                driver.click()

                def search_after_click():
                    image = driver.capture(rect)
                    image.save(args.evidence / 'settings-after-click.png')
                    return settings_search(image)

                search = wait_for('Settings search after a native mouse click', search_after_click, app)
                search_point = rect.x + search[0], rect.y + search[1]
                empty = search_point[0], search_point[1] - 35
                driver.motion(*empty)
                time.sleep(0.30)
                cursor_before = wait_for('initial native cursor', driver.cursor, app)
                driver.motion(*search_point)

                def cursor_changed():
                    observed = driver.cursor()
                    return observed is not None and observed != cursor_before

                cursor_after = wait_for('a changed native cursor over Settings search', cursor_changed, app)
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
            startup_frame(log)
            (args.evidence / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
        finally:
            log = data / 'logs' / 'ocideck.log'
            if log.exists():
                (args.evidence / 'startup.log').write_bytes(log.read_bytes())
            stop(app)
            if args.backend == 'wayland':
                stop(driver.pointer)
            stop(driver.manager)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('backend', choices=('x11', 'wayland'))
    parser.add_argument('executable', type=lambda value: Path(value).resolve(strict=True))
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--presentation', action='store_true')
    args = parser.parse_args()
    if args.presentation and args.backend != 'wayland':
        parser.error('--presentation requires the private Wayland compositor')
    with tempfile.TemporaryDirectory(prefix='ocideck-window-') as workspace:
        exercise(args, Path(workspace))
