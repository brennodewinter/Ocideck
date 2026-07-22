import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../tool/license_detect.dart';
import '../tool/sbom_build.dart';

/// `THIRD_PARTY_NOTICES.md` is the human-readable companion to the SBOM: the
/// file a user, a customer or an auditor actually reads. It is written by hand,
/// and a hand-kept list of dependencies falls behind — that is not a risk, it is
/// what happened. Twelve direct dependencies (`webview_flutter`,
/// `flutter_secure_storage`, `http`, `opencv_core`, `crypto`, `flutter_quill`,
/// `flutter_svg`, `web`, `webview_flutter_web`, `markdown`, `markdown_quill`,
/// `xml`) had landed in `pubspec.yaml` without ever reaching it, while the
/// generated SBOM listed every one.
///
/// So the notices file gets the same treatment as every other claim in this
/// repository: it is checked against its source of truth. Adding a dependency,
/// a vendored JS bundle or a font now means adding a row here too, in the same
/// commit — or this test is red.
///
/// The licence column is checked against `tool/license_detect.dart`, the same
/// classifier `make licenses` and `make sbom` use, so the notices cannot claim
/// a licence the package on disk does not carry. That is the exact failure this
/// project already had once: `desktop_multi_window` was listed as MIT while
/// `third_party/desktop_multi_window/LICENSE` was Apache-2.0.
void main() {
  final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

  /// True when the notices mention [name] as a code span (`` `name` ``), which
  /// is how every component is written there. A bare substring match would let
  /// `path` match inside `path_provider`.
  bool mentions(String name) => notices.contains('`$name`');

  group('completeness', () {
    test('every direct dependency appears in the notices', () {
      final deps = (pubspec['dependencies'] as YamlMap).keys
          .map((k) => k.toString())
          .toList();
      final missing = deps.where((d) => !mentions(d)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'These direct dependencies are in pubspec.yaml but not in '
            'THIRD_PARTY_NOTICES.md: $missing. The SBOM has them; the file a '
            'human reads should too. Add a row, then re-run.',
      );
    });

    test('every vendored JS/CSS bundle appears in the notices', () {
      final manifest =
          jsonDecode(File(manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      for (final b
          in (manifest['bundles'] as List).cast<Map<String, dynamic>>()) {
        final npm = b['npm'] as String?;
        final file = b['file'] as String;
        // Bundles are named in prose ("Mermaid", "MathJax"); match on the npm
        // package name case-insensitively, falling back to the filename for the
        // integrity-only assets that have no npm package.
        final needle = npm ?? file;
        expect(
          notices.toLowerCase().contains(needle.toLowerCase()),
          isTrue,
          reason:
              'Bundle "$needle" is inlined into every HTML export but is '
              'not mentioned in THIRD_PARTY_NOTICES.md.',
        );
      }
    });

    test(
      'every bundled font family and its OFL text appear in the notices',
      () {
        final fonts =
            (pubspec['flutter'] as YamlMap)['fonts'] as YamlList? ?? YamlList();
        for (final family in fonts) {
          final name = family['family'].toString();
          expect(
            notices.contains(name),
            isTrue,
            reason:
                'Bundled font family "$name" is not in '
                'THIRD_PARTY_NOTICES.md. OFL-1.1 §2 requires the notice to '
                'travel with the font.',
          );
        }
      },
    );

    test('the vendored forks are named with their upstream commit', () {
      for (final fork in Directory(
        'third_party',
      ).listSync().whereType<Directory>()) {
        final name = fork.path.split(Platform.pathSeparator).last;
        expect(
          mentions(name),
          isTrue,
          reason: 'Vendored fork "$name" is missing from the notices.',
        );
        expect(
          File('${fork.path}/MODIFICATIONS.md').existsSync(),
          isTrue,
          reason:
              'A fork without a MODIFICATIONS.md leaves the reader to diff a '
              'tarball to learn what we changed — and under Apache-2.0 §4(b) '
              'that record is not optional.',
        );
      }
    });
  });

  group('accuracy', () {
    test(
      'the licence stated for each direct dependency is the classified one',
      () {
        final cfg =
            jsonDecode(
                  File('.dart_tool/package_config.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        final roots = <String, Directory>{};
        final base = File('.dart_tool/package_config.json').absolute.parent.uri;
        for (final pkg
            in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
          final uri = pkg['rootUri'] as String;
          final normalised = uri.endsWith('/') ? uri : '$uri/';
          roots[pkg['name'] as String] = Directory.fromUri(
            normalised.startsWith('file:')
                ? Uri.parse(normalised)
                : base.resolve(normalised),
          );
        }

        // One table row per line: "| `a`, `b` | purpose | Licence |".
        final wrong = <String>[];
        for (final line in notices.split('\n')) {
          if (!line.startsWith('| `')) continue;
          final cells = line.split('|').map((c) => c.trim()).toList();
          if (cells.length < 4) continue;
          final stated = cells[3];
          for (final match in RegExp(r'`([a-z0-9_]+)`').allMatches(cells[1])) {
            final name = match.group(1)!;
            final root = roots[name];
            if (root == null) continue;
            final actual = licenseFamily(licenseForPackage(name, root));
            if (!stated.contains(actual)) {
              wrong.add(
                '$name: notices say "$stated", LICENSE file says $actual',
              );
            }
          }
        }
        expect(
          wrong,
          isEmpty,
          reason:
              'THIRD_PARTY_NOTICES.md states a licence that the package\'s own '
              'LICENSE file does not support:\n  ${wrong.join('\n  ')}',
        );
      },
    );
  });
}
