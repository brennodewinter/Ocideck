// Guards the first-party packages under packages/ (FORM_INTAKE.md §4.10, §16).
//
//   dart run tool/check_packages.dart     (or: make check-packages)
//
// A package under packages/ exists so that something that cannot depend on the
// Flutter SDK — a standalone Dart server, a command-line validator — can share
// code with the app. That promise is only worth something if it is *checked*:
// one `import 'dart:io'` in a shared file and the web form shell stops compiling,
// one `sdk: flutter` and the server cannot resolve it. `flutter analyze` at the
// root already fails a `package:flutter` import inside a package (the package's
// own pubspec does not offer it); these rules cover what analysis cannot:
//
//   1. `publish_to: none` — first-party code is released with the repository.
//   2. The package name equals its directory name.
//   3. No dependency on the Flutter SDK, in any section.
//   4. `environment.sdk` equals the root's, so one toolchain builds everything.
//   5. `LICENSE` is a copy of the root `LICENSE.md`.
//   6. `lib/` imports or exports none of dart:io, dart:ui, dart:html, dart:js*,
//      or package:flutter — the core must also run in a browser tab.
//   7. The app depends on every package, via `path: packages/<name>`. A package
//      nobody uses is dead code the root's dead-code gate cannot see.
//
// The checks are a pure function over file contents so a test can plant each
// violation (test/check_packages_tool_test.dart) — a gate nobody has watched
// fail is not known to guard anything.

import 'dart:io';

import 'package:yaml/yaml.dart';

/// Libraries a shared core must not import: each one ties the code to a
/// platform. `dart:io` is VM-only, `dart:ui` and `package:flutter` need the
/// Flutter engine, `dart:html` and `dart:js*` are browser-only.
final RegExp _forbiddenImport = RegExp(
  r'''^\s*(?:import|export)\s+['"](?:dart:(?:io|ui|html|js|js_util|js_interop|js_interop_unsafe)|package:flutter(?:_[a-z_]+)?/)''',
);

/// Every violation found under [packagesDir], one readable line each. Empty
/// means clean. [rootPubspec] and [rootLicense] are the *contents* of the
/// repository's `pubspec.yaml` and `LICENSE.md`.
List<String> packageProblems({
  required Directory packagesDir,
  required String rootPubspec,
  required String rootLicense,
}) {
  if (!packagesDir.existsSync()) return const [];

  final root = loadYaml(rootPubspec) as YamlMap;
  final rootSdk = (root['environment'] as YamlMap?)?['sdk']?.toString();
  final rootDeps = root['dependencies'] as YamlMap? ?? YamlMap();

  final problems = <String>[];
  final dirs =
      packagesDir
          .listSync()
          .whereType<Directory>()
          .where((d) => File('${d.path}/pubspec.yaml').existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final dir in dirs) {
    final dirName = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final where = 'packages/$dirName';
    final pubspec =
        loadYaml(File('${dir.path}/pubspec.yaml').readAsStringSync())
            as YamlMap;

    // 1
    if (pubspec['publish_to']?.toString() != 'none') {
      problems.add(
        "$where: publish_to must be 'none' — first-party code is released "
        'with the repository, not to pub.dev.',
      );
    }
    // 2
    final name = pubspec['name']?.toString();
    if (name != dirName) {
      problems.add(
        '$where: the package name is "$name" but the directory is "$dirName"; '
        'a path dependency resolves by name.',
      );
    }
    // 3
    for (final section in const [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      final deps = pubspec[section];
      if (deps is! YamlMap) continue;
      for (final entry in deps.entries) {
        final spec = entry.value;
        final isFlutter =
            entry.key.toString() == 'flutter' ||
            (spec is YamlMap && spec['sdk']?.toString() == 'flutter');
        if (isFlutter) {
          problems.add(
            '$where: $section depends on the Flutter SDK '
            '(${entry.key}); a shared core must stay pure Dart.',
          );
        }
      }
    }
    // 4
    final sdk = (pubspec['environment'] as YamlMap?)?['sdk']?.toString();
    if (sdk != rootSdk) {
      problems.add(
        '$where: environment sdk is "$sdk" but the root says "$rootSdk"; '
        'one toolchain builds everything, so the constraints must be equal.',
      );
    }
    // 5
    final license = File('${dir.path}/LICENSE');
    if (!license.existsSync() || license.readAsStringSync() != rootLicense) {
      problems.add(
        '$where: LICENSE is missing or differs from the root LICENSE.md — '
        'copy it (cp LICENSE.md $where/LICENSE).',
      );
    }
    // 6
    final lib = Directory('${dir.path}/lib');
    if (lib.existsSync()) {
      final files =
          lib
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final rel = file.path.substring(dir.path.length + 1);
        for (final line in file.readAsLinesSync()) {
          if (_forbiddenImport.hasMatch(line)) {
            problems.add(
              '$where/$rel: platform import (${line.trim()}) — the core must '
              'also run in a browser tab and on a Flutter-free server.',
            );
          }
        }
      }
    }
    // 7
    final dep = rootDeps[dirName];
    final depPath = dep is YamlMap ? dep['path']?.toString() : null;
    if (depPath != where) {
      problems.add(
        '$where: the app has no `$dirName: {path: $where}` dependency in '
        'pubspec.yaml; an unused package is dead code the dead-code gate '
        'cannot see.',
      );
    }
  }
  return problems;
}

void main() {
  final problems = packageProblems(
    packagesDir: Directory('packages'),
    rootPubspec: File('pubspec.yaml').readAsStringSync(),
    rootLicense: File('LICENSE.md').readAsStringSync(),
  );
  if (problems.isEmpty) {
    stdout.writeln(
      'Packages OK: every package under packages/ follows the rules.',
    );
    return;
  }
  stderr.writeln('${problems.length} problem(s) under packages/:');
  for (final p in problems) {
    stderr.writeln('  - $p');
  }
  exit(1);
}
