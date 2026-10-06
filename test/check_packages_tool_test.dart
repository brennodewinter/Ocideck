import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart' show maxFileLines;
import '../tool/check_packages.dart';

/// Guards the gate that guards packages/ (FORM_INTAKE.md §4.10, §16).
///
/// A gate nobody has watched fail is not known to guard anything, so every rule
/// is checked in both directions: silent on the real repository, and loud on a
/// planted violation.
void main() {
  const rootLicense = 'European Union Public Licence v. 1.2\n';
  const rootPubspec = '''
name: ocideck
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  good_pkg:
    path: packages/good_pkg
''';

  late Directory tmp;
  late Directory packages;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('check_packages_');
    packages = Directory('${tmp.path}/packages')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A package that satisfies every rule; tests then break exactly one thing.
  void writePackage(
    String name, {
    String? pubspec,
    String? license,
    Map<String, String> lib = const {'src/a.dart': "const a = 1;\n"},
  }) {
    final dir = Directory('${packages.path}/$name')..createSync();
    File('${dir.path}/pubspec.yaml').writeAsStringSync(
      pubspec ??
          '''
name: $name
publish_to: 'none'
environment:
  sdk: ^3.12.0
dev_dependencies:
  test: ^1.25.0
''',
    );
    File('${dir.path}/LICENSE').writeAsStringSync(license ?? rootLicense);
    for (final e in lib.entries) {
      File('${dir.path}/lib/${e.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(e.value);
    }
  }

  List<String> problems([String root = rootPubspec]) => packageProblems(
    packagesDir: packages,
    rootPubspec: root,
    rootLicense: rootLicense,
  );

  test('analysis bootstraps first-party package dependencies first', () {
    final result = Process.runSync('make', ['-n', 'analyze']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final output = result.stdout as String;
    final bootstrap = output.indexOf('dart pub get --enforce-lockfile');
    final analyze = output.indexOf('flutter analyze --fatal-infos');
    expect(bootstrap, isNonNegative, reason: output);
    expect(analyze, greaterThan(bootstrap), reason: output);
  });

  test('a package that follows every rule is clean', () {
    writePackage('good_pkg');
    expect(problems(), isEmpty);
  });

  test('no packages/ directory at all is clean', () {
    packages.deleteSync();
    expect(problems(), isEmpty);
  });

  test('publish_to must be none', () {
    writePackage(
      'good_pkg',
      pubspec: 'name: good_pkg\nenvironment:\n  sdk: ^3.12.0\n',
    );
    expect(problems().single, contains('publish_to'));
  });

  test('the directory name and the package name must agree', () {
    writePackage(
      'good_pkg',
      pubspec:
          "name: other\npublish_to: 'none'\nenvironment:\n  sdk: ^3.12.0\n",
    );
    expect(problems().single, contains('name'));
  });

  test('a dependency on the Flutter SDK is refused, in any section', () {
    for (final section in ['dependencies', 'dev_dependencies']) {
      writePackage(
        'good_pkg',
        pubspec:
            "name: good_pkg\npublish_to: 'none'\nenvironment:\n  sdk: ^3.12.0\n"
            '$section:\n  flutter:\n    sdk: flutter\n',
      );
      expect(problems().single, contains('Flutter'), reason: section);
    }
  });

  test('the SDK constraint must equal the root constraint', () {
    writePackage(
      'good_pkg',
      pubspec:
          "name: good_pkg\npublish_to: 'none'\nenvironment:\n  sdk: ^3.0.0\n",
    );
    expect(problems().single, contains('sdk'));
  });

  test('LICENSE must be a copy of the root licence', () {
    writePackage('good_pkg', license: 'something else\n');
    expect(problems().single, contains('LICENSE'));
  });

  test('a missing LICENSE is a problem, not a crash', () {
    writePackage('good_pkg');
    File('${packages.path}/good_pkg/LICENSE').deleteSync();
    expect(problems().single, contains('LICENSE'));
  });

  group('platform imports in lib/', () {
    for (final bad in [
      "import 'dart:io';",
      "import 'dart:ui';",
      "import 'dart:html';",
      "import 'dart:js_interop';",
      "import 'package:flutter/foundation.dart';",
      'export "dart:io";',
    ]) {
      test('refuses $bad', () {
        writePackage('good_pkg', lib: {'src/a.dart': '$bad\nconst a = 1;\n'});
        final found = problems();
        expect(found, hasLength(1), reason: bad);
        expect(found.single, contains('src/a.dart'));
      });
    }

    test('allows dart:convert, dart:typed_data and dart:async', () {
      writePackage(
        'good_pkg',
        lib: {
          'src/a.dart':
              "import 'dart:async';\nimport 'dart:convert';\n"
              "import 'dart:typed_data';\nconst a = 1;\n",
        },
      );
      expect(problems(), isEmpty);
    });

    test('an import inside a comment or string is not an import', () {
      writePackage(
        'good_pkg',
        lib: {
          'src/a.dart':
              "// import 'dart:io';\nconst a = \"import 'dart:ui';\";\n",
        },
      );
      expect(problems(), isEmpty);
    });
  });

  group('conventions the rest of the repo already holds', () {
    test('a file longer than the repo-wide ceiling is refused', () {
      final long = List.generate(maxFileLines + 1, (i) => '// $i').join('\n');
      writePackage('good_pkg', lib: {'src/long.dart': '$long\n'});
      final found = problems();
      expect(found.single, contains('src/long.dart'));
      expect(found.single, contains('${maxFileLines + 1}'));
    });

    test('a file exactly at the ceiling is fine', () {
      final exact = List.generate(maxFileLines, (i) => '// $i').join('\n');
      writePackage('good_pkg', lib: {'src/exact.dart': '$exact\n'});
      expect(problems(), isEmpty);
    });

    test('a bare catch (_) is refused: failures must not vanish silently', () {
      writePackage(
        'good_pkg',
        lib: {'src/a.dart': 'void f() {\n  try {} catch (_) {}\n}\n'},
      );
      final found = problems();
      expect(found.single, contains('src/a.dart:2'));
      expect(found.single, contains('catch'));
    });

    test('catching a named error, or on-clauses, is fine', () {
      writePackage(
        'good_pkg',
        lib: {
          'src/a.dart':
              'void f() {\n  try {} on FormatException catch (e) {print(e);}\n'
              '  try {} catch (e) {print(e);}\n}\n',
        },
      );
      expect(problems(), isEmpty);
    });

    test('a comment that talks about catch (_) is not a violation', () {
      writePackage(
        'good_pkg',
        lib: {'src/a.dart': '// never write catch (_) here\nconst a = 1;\n'},
      );
      expect(problems(), isEmpty);
    });
  });

  group('cryptographic primitives', () {
    for (final library in [
      'dartage',
      'cryptography',
      'pointycastle',
      'pqcrypto',
    ]) {
      test('package:$library outside the allowed files is refused', () {
        writePackage(
          'good_pkg',
          lib: {'src/other.dart': "import 'package:$library/$library.dart';\n"},
        );
        final found = problems();
        expect(found, hasLength(1));
        expect(found.single, contains('lib/src/other.dart'));
        expect(found.single, contains('cryptographic primitive'));
      });
    }

    test('an export counts as an import', () {
      writePackage(
        'good_pkg',
        lib: {'src/other.dart': "export 'package:dartage/dartage.dart';\n"},
      );
      expect(problems(), hasLength(1));
    });

    test('the files meant to touch them may', () {
      writePackage(
        'good_pkg',
        lib: {
          'src/form_seal.dart': "import 'package:dartage/dartage.dart';\n",
          'src/form_bundle.dart':
              "import 'package:cryptography/cryptography.dart';\n",
        },
      );
      expect(problems(), isEmpty);
    });

    test('the same file name in another folder may not', () {
      writePackage(
        'good_pkg',
        lib: {'form_seal.dart': "import 'package:dartage/dartage.dart';\n"},
      );
      expect(problems(), hasLength(1));
    });

    test('hashes are not primitives in this sense', () {
      writePackage(
        'good_pkg',
        lib: {'src/hash.dart': "import 'package:crypto/crypto.dart';\n"},
      );
      expect(problems(), isEmpty);
    });

    test('a comment that mentions an import is not one', () {
      writePackage(
        'good_pkg',
        lib: {'src/note.dart': "// import 'package:dartage/dartage.dart';\n"},
      );
      expect(problems(), isEmpty);
    });
  });

  test('the app must depend on every package, via the right path', () {
    writePackage('good_pkg');
    writePackage('orphan');
    final found = problems();
    expect(found.single, contains('orphan'));
    expect(found.single, contains('dependency'));
  });

  test('a path that points somewhere else is refused', () {
    writePackage('good_pkg');
    final found = problems(
      rootPubspec.replaceFirst('packages/good_pkg', 'third_party/good_pkg'),
    );
    expect(found.single, contains('good_pkg'));
  });

  test('the real repository is clean', () {
    final found = packageProblems(
      packagesDir: Directory('packages'),
      rootPubspec: File('pubspec.yaml').readAsStringSync(),
      rootLicense: File('LICENSE.md').readAsStringSync(),
    );
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
