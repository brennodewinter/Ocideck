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
//   8. No file in `lib/` is longer than the repo-wide ceiling
//      ([maxFileLines], 1000) — the same rule `check_conventions.dart` applies
//      to the app, which does not look under packages/.
//   9. No bare `catch (_)`: a pure engine that "never throws on bad input" must
//      not swallow the failures it did not expect either.
//  10. The cryptographic primitives — the age implementation (`dartage`) and the
//      libraries under it — are imported only by the files that are *meant* to touch
//      them ([primitiveFiles], FORM_INTAKE.md §5.6): sealing and, later, the signed
//      bundle. A third file that "just needs a MAC" is how a second, unreviewed use of
//      the primitives starts; the external review covers those files and no others.
//
// Not covered here, on purpose: print() (the `avoid_print` lint in
// `package:lints/recommended` already fails analysis), method length (the files
// are small by design — one descriptor per field type, FORM_INTAKE.md §4.10) and
// user-visible text (the engine returns issue *codes*; the sentences live in the
// app's l10n).
//
// The checks are a pure function over file contents so a test can plant each
// violation (test/check_packages_tool_test.dart) — a gate nobody has watched
// fail is not known to guard anything.

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'check_conventions.dart' show maxFileLines;

/// Libraries a shared core must not import: each one ties the code to a
/// platform. `dart:io` is VM-only, `dart:ui` and `package:flutter` need the
/// Flutter engine, `dart:html` and `dart:js*` are browser-only.
/// `catch (_)`, with any spacing; an `on X catch (_)` is just as silent.
final RegExp _bareCatch = RegExp(r'catch\s*\(\s*_\s*\)');

final RegExp _forbiddenImport = RegExp(
  r'''^\s*(?:import|export)\s+['"](?:dart:(?:io|ui|html|js|js_util|js_interop|js_interop_unsafe)|package:flutter(?:_[a-z_]+)?/)''',
);

/// The cryptographic libraries only [primitiveFiles] may import. `package:crypto` (hashes)
/// is not among them: a SHA-256 over a file is not a protocol.
final RegExp _primitiveImport = RegExp(
  r'''^\s*(?:import|export)\s+['"]package:(?:dartage|cryptography|pointycastle|pqcrypto)/''',
);

/// The files of a package's `lib/` that may import the cryptographic primitives, relative
/// to the package. `form_bundle.dart` is the Ed25519 signing of the bundle (§5.1) and
/// `intake_request.dart` the Ed25519 signing of an organiser's request (§6.3).
const Set<String> primitiveFiles = {
  'lib/src/form_seal.dart',
  'lib/src/form_bundle.dart',
  'lib/src/intake_request.dart',
};

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
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (_forbiddenImport.hasMatch(line)) {
            problems.add(
              '$where/$rel: platform import (${line.trim()}) — the core must '
              'also run in a browser tab and on a Flutter-free server.',
            );
          }
          // 10
          if (_primitiveImport.hasMatch(line) &&
              !primitiveFiles.contains(rel)) {
            problems.add(
              '$where/$rel: imports a cryptographic primitive '
              '(${line.trim()}) — only ${primitiveFiles.join(', ')} may; '
              'the external review covers those files and no others.',
            );
          }
          if (!line.trimLeft().startsWith('//') && _bareCatch.hasMatch(line)) {
            problems.add(
              '$where/$rel:${i + 1}: bare catch (_) swallows failures '
              'silently — catch a named error or an exception type.',
            );
          }
        }
        // 8
        if (lines.length > maxFileLines) {
          problems.add(
            '$where/$rel: ${lines.length} lines (max $maxFileLines) — split it.',
          );
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
