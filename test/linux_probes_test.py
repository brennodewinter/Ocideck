"""Regression fixtures for the Linux package and startup probes."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'scripts'


@unittest.skipUnless(shutil.which('timeout'), 'requires the desktop supervisor timeout')
class StartupProbeTest(unittest.TestCase):
    def launch(self, fixture, *, session_setup='exit 0'):
        with tempfile.TemporaryDirectory() as work:
            directory = Path(work)
            for tool, code in {
                'xvfb-run': 'shift; exec "$@"',
                'dbus-run-session': 'shift; exec "$@"',
                'gdbus': session_setup,
            }.items():
                command = directory / tool
                command.write_text('#!/bin/sh\n' + code + '\n')
                command.chmod(0o700)
            evidence = directory / 'evidence'
            command = [
                'bash', str(SCRIPTS / 'linux_start_probe.sh'), str(evidence),
                'bash', '-ec', '''
logdir="$XDG_DATA_HOME/com.dewinter.ocideck/logs"
mkdir -p "$logdir"
log="$logdir/ocideck.log"
''' + fixture,
            ]
            result = subprocess.run(
                command, text=True, capture_output=True, timeout=12,
                env=dict(os.environ, PATH=work + os.pathsep + os.environ['PATH'],
                         OCIDECK_PROBE_STARTUP_SECONDS='3',
                         OCIDECK_PROBE_SETTLE_SECONDS='1'),
            )
            saved_log, = evidence.glob('start.*/ocideck.log')
            return result, saved_log.read_text()

    def test_frame_from_current_run_and_stays_alive(self):
        result, log = self.launch(
            "echo '2026-01-01T00:00:00 INFO opstart: eerste frame (+100 ms)' > \"$log\"\nsleep 7"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('eerste frame', log)

    def test_desktop_session_setup_does_not_consume_the_first_frame_budget(self):
        result, log = self.launch(
            "echo '2026-01-01T00:00:00 INFO opstart: eerste frame (+100 ms)' > \"$log\"\nsleep 7",
            session_setup='sleep 4',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('eerste frame', log)

    def test_process_without_frame_fails_even_when_alive(self):
        result, _ = self.launch('sleep 7')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('did not record a first rasterized frame', result.stderr)

    def test_watchdog_and_startup_error_are_fatal(self):
        for message in ('WARN opstart: nog geen eerste frame na 10 s',
                        'ERROR Uncaught zone error'):
            with self.subTest(message=message):
                result, log = self.launch(f"echo '2026-01-01T00:00:00 {message}' > \"$log\"\nsleep 7")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, log)

    def test_frame_followed_by_an_early_exit_fails(self):
        result, _ = self.launch(
            "echo '2026-01-01T00:00:00 INFO opstart: eerste frame (+100 ms)' > \"$log\""
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exited early', result.stderr)


@unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('cc')
                     and shutil.which('readelf'), 'requires the Linux ELF toolchain')
class ElfProbeTest(unittest.TestCase):
    def test_standard_probe_uses_bundle_for_plugins_and_preserves_executable_search(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            libdir = root / 'lib'
            libdir.mkdir()
            source = root / 'fixture.c'
            source.write_text('int fixture_dependency(void) { return 0; }\n')
            soname = 'libocideck_probe_fixture.so.1'
            dependency = libdir / soname
            subprocess.run(['cc', '-shared', '-fPIC', f'-Wl,-soname,{soname}',
                            str(source), '-o', str(dependency)], check=True)
            source.write_text('extern int fixture_dependency(void);\n'
                              'int main(void) { return fixture_dependency(); }\n')
            plugin = libdir / 'plugin.so'
            subprocess.run(['cc', '-shared', '-fPIC', str(source), str(dependency),
                            '-o', str(plugin)], check=True)
            command = ['bash', str(SCRIPTS / 'check_linux_runtime_elf.sh'), str(root)]
            result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)

            executable = root / 'standalone'
            subprocess.run(['cc', '-fPIE', '-pie', str(source), str(dependency),
                            '-o', str(executable)], check=True)
            result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1)
            self.assertIn('standalone: unresolved runtime dependencies', result.stderr)
            self.assertNotIn('lib/plugin.so:', result.stderr)

            executable.unlink()
            dependency.unlink()
            result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1)
            self.assertIn('lib/plugin.so: unresolved runtime dependencies', result.stderr)
            self.assertIn(f'{soname} => not found', result.stderr)

    def test_standalone_plugin_is_checked_and_bundled_dependency_can_resolve(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            libdir = root / 'AppDir' / 'lib'
            libdir.mkdir(parents=True)
            source = root / 'fixture.c'
            source.write_text('int fixture_dependency(void) { return 7; }\n')
            dependency = root / 'libocideck_probe_fixture.so.1'
            subprocess.run(['cc', '-shared', '-fPIC',
                            '-Wl,-soname,libocideck_probe_fixture.so.1',
                            str(source), '-o', str(dependency)], check=True)
            source.write_text('extern int fixture_dependency(void);\n'
                              'int plugin(void) { return fixture_dependency(); }\n')
            subprocess.run(['cc', '-shared', '-fPIC', str(source), str(dependency),
                            '-o', str(libdir / 'plugin.so')], check=True)
            shutil.copyfile(shutil.which('true') or '/usr/bin/true', libdir.parent / 'ocideck')
            command = ['bash', str(SCRIPTS / 'check_linux_runtime_elf.sh'), str(libdir.parent), 'appimage']
            result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn('lib/plugin.so', result.stderr)
            self.assertIn('libocideck_probe_fixture.so.1 => not found', result.stderr)

            subprocess.run(
                ['cc', '-shared', '-fPIC', str(source), str(dependency),
                 f'-Wl,-rpath,{root}', '-o', str(libdir / 'plugin.so')], check=True,
            )
            result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn('undeclared host dependency libocideck_probe_fixture.so.1', result.stderr)
            shutil.move(dependency, libdir / dependency.name)
            result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Inspected 2 ELF objects', result.stdout)


if __name__ == '__main__':
    unittest.main()
