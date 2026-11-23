// Guards the Wayland scale-factor workaround in the Linux runner.
//
//   dart run tool/check_linux_wayland_scale.dart
//   (or: make check-linux-wayland-scale)
//
// On Wayland, Flutter 3.50's FlViewRendererSubsurface sets the subsurface's
// buffer scale once at creation and never updates it (Flutter #196476). When
// GTK later changes the widget's scale factor — the window lands on an output
// with a different scale, or maps at one scale and settles on another — the
// stale buffer scale leaves the content at half or double size in a corner,
// with misaligned input (issue #3106). The runner works around it by cycling
// the renderer through unrealize/map on "notify::scale-factor".
//
// Nothing in `flutter test` notices the wiring is missing: the Dart suite
// runs on macOS, the C++ runner is never compiled there, and the bug only
// reproduces on Linux/Wayland. This gate is the smallest thing that fails if
// someone removes the hook or Flutter renames the pieces it relies on.
//
// Ceiling: presence checks only. Whether the rebuild actually fixes the
// rendering needs a real Wayland session — verified manually on Hyprland at
// scale 1 and 2. Upgrade path is the post-merge Linux build in
// .forgejo/workflows/linux-build.yml. Remove this gate together with the
// workaround once the engine applies scale changes itself.
//
// Exit codes: 0 = the workaround is wired up
//             1 = a required piece is missing (the report names what to
//                 restore)
//             2 = the check could not run (my_application.cc not found)

import 'dart:io';

const _runnerPath = 'linux/runner/my_application.cc';

void main() {
  final file = File(_runnerPath);
  if (!file.existsSync()) {
    stderr.writeln('$_runnerPath ontbreekt — geen Linux-runner in deze boom.');
    exit(2);
  }

  // Strip comments so a mention in a comment block can't stand in for real
  // code — same principle as check_linux_impeller.
  final code = file
      .readAsStringSync()
      .split('\n')
      .map((line) => line.split('//').first)
      .join('\n');

  final problems = <String>[];

  void require(RegExp pattern, String what, String why) {
    if (!pattern.hasMatch(code)) {
      problems.add('$_runnerPath: $what ontbreekt.\n  → $why');
    }
  }

  const why =
      'zonder deze workaround blijft de Flutter-surface op een verkeerde\n'
      '    bufferschaal hangen zodra Wayland de scale-factor wijzigt\n'
      '    (Flutter #196476, issue #3106).';

  require(
    RegExp(r'g_type_from_name\s*\(\s*"FlViewRendererSubsurface"\s*\)'),
    'de opzoek van FlViewRendererSubsurface',
    why,
  );
  require(
    RegExp(r'"notify::scale-factor"'),
    'de notify::scale-factor-aansluiting',
    why,
  );
  require(
    RegExp(r'follow_subsurface_scale\s*\(\s*view\s*\)'),
    'de aanroep follow_subsurface_scale(view) in my_application_activate',
    why,
  );
  require(
    RegExp(
      r'gtk_widget_unrealize\s*\(\s*renderer\s*\)[\s\S]{0,200}'
      r'gtk_widget_map\s*\(\s*renderer\s*\)',
    ),
    'de unrealize/map-cyclus die de subsurface op de nieuwe schaal herbouwt',
    why,
  );

  if (problems.isEmpty) {
    stdout.writeln(
      'linux wayland-scale OK: subsurface-rebuild op scale-factor is '
      'aangesloten in $_runnerPath.',
    );
    return;
  }
  for (final problem in problems) {
    stderr.writeln(problem);
  }
  exit(1);
}
