// Guards the Impeller opt-out in the Linux runner.
//
//   dart run tool/check_linux_impeller.dart   (or: make check-linux-impeller)
//
// Flutter 3.47 enables Impeller on Linux by default. Impeller's EGL-context
// conflicts with GTK3's own GL-context on Wayland (Flutter #191775):
// eglMakeCurrent fails during a redraw and GDK segfaults in
// gdk_window_end_draw_frame with rdi=0x0. The fix is a one-liner in
// my_application.cc — fl_dart_project_set_enable_impeller(project, FALSE) —
// that falls back to Skia, which does not take a second GL context.
//
// Nothing in `flutter test` notices that the line is missing: the Dart suite
// runs on macOS, the C++ runner is never compiled, and the crash only
// reproduces on Linux/Wayland. This gate is the smallest thing that fails if
// someone removes the opt-out (or upgrades Flutter and the API changes name).
//
// Ceiling: this checks that the call is present and passes FALSE. It cannot
// verify that Skia actually renders correctly on every Wayland compositor —
// that needs a real Linux build. Upgrade path is the post-merge Linux build
// in .forgejo/workflows/linux-build.yml.
//
// Exit codes: 0 = the opt-out is present and disables Impeller
//             1 = it is missing or does not pass FALSE (the report names the
//                 file to edit)
//             2 = the check could not run (my_application.cc not found)

import 'dart:io';

const _runnerPath = 'linux/runner/my_application.cc';

void main() {
  final file = File(_runnerPath);
  if (!file.existsSync()) {
    stderr.writeln('$_runnerPath ontbreekt — geen Linux-runner in deze boom.');
    exit(2);
  }

  final source = file.readAsStringSync();
  final problems = <String>[];

  // Strip comments so a line in a comment block can't stand in for the real
  // call — same principle as check_linux_pkgconfig's _fileContains.
  final code = source
      .split('\n')
      .map((line) => line.split('//').first)
      .join('\n');

  final enableImpeller = RegExp(
    r'fl_dart_project_set_enable_impeller\s*\(\s*project\s*,\s*(\w+)\s*\)',
  );
  final match = enableImpeller.firstMatch(code);

  if (match == null) {
    problems.add(
      '$_runnerPath roept fl_dart_project_set_enable_impeller niet aan.\n'
      '  → Impeller is de standaard-renderer op Linux sinds Flutter 3.47 en\n'
      '    botst met GTK3\'s GL-context op Wayland (Flutter #191775, issue\n'
      '    #2058). Voeg fl_dart_project_set_enable_impeller(project, FALSE)\n'
      '    toe na fl_dart_project_set_dart_entrypoint_arguments.',
    );
  } else {
    final arg = match.group(1)!.toUpperCase();
    if (arg != 'FALSE' && arg != '0') {
      problems.add(
        '$_runnerPath roept fl_dart_project_set_enable_impeller(project, $arg)\n'
        '  → Impeller moet uitgeschakeld zijn (FALSE) vanwege de Wayland-crash\n'
        '    (Flutter #191775, issue #2058).',
      );
    }
  }

  if (problems.isEmpty) {
    stdout.writeln(
      'linux impeller OK: Impeller uitgeschakeld in $_runnerPath.',
    );
    return;
  }
  for (final problem in problems) {
    stderr.writeln(problem);
  }
  exit(1);
}
