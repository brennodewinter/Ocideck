import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps `.github/pinned-ci-versions.json` and the workflows that carry those
/// versions from drifting apart (#802).
///
/// `make check-pins` answers "is there something newer upstream". It cannot
/// answer "is the number in this manifest still the number the workflow uses",
/// because it never opens a workflow — and that second question is the one that
/// goes wrong quietly. The three scanner versions are written out in **two**
/// workflow files (`.forgejo/workflows/scans.yml` runs on every pull request,
/// `.github/workflows/ci.yml` is the mirror definition), so a bump has three
/// places to land and two of them are easy to forget.
///
/// Four properties, and the last one is the important one:
///
///   * Present   — every version in the manifest appears in every workflow the
///                 manifest says carries it.
///   * Agreed    — the workflows agree with each other about each version.
///   * Sound     — every entry has the fields the freshness monitor needs.
///   * Complete  — every `*_VERSION:` pin found in a workflow is listed in the
///                 manifest. Without this the manifest could go stale by
///                 *omission*: add a fourth scanner, forget the manifest, and
///                 nothing watches it — which is precisely the hole #802 was
///                 filed about, reopened one level up.
///
/// Offline and deterministic, so it belongs in the suite rather than in the
/// advisory network check.
void main() {
  const manifestPath = '.github/pinned-ci-versions.json';

  final manifest =
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>;
  final actions = (manifest['actions'] as List).cast<Map<String, dynamic>>();
  final tools = (manifest['tools'] as List).cast<Map<String, dynamic>>();

  /// Every workflow file either list points at, deduplicated.
  final workflowPaths = <String>{
    for (final entry in [...actions, ...tools])
      ...(entry['workflows'] as List).cast<String>(),
  };
  final workflows = {
    for (final path in workflowPaths) path: File(path).readAsStringSync(),
  };

  group('the manifest matches the workflows', () {
    test('every workflow the manifest names exists', () {
      final missing = workflowPaths
          .where((p) => !File(p).existsSync())
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'Listed in $manifestPath but not on disk — a workflow was renamed '
            'or deleted without updating the manifest: $missing',
      );
    });

    test(
      'each tool version is written out in every workflow that carries it',
      () {
        final wrong = <String>[];
        for (final tool in tools) {
          final env = tool['env'] as String;
          final version = tool['version'] as String;
          for (final path in (tool['workflows'] as List).cast<String>()) {
            if (!workflows[path]!.contains('$env: $version')) {
              wrong.add('$path is missing `$env: $version`');
            }
          }
        }
        expect(
          wrong,
          isEmpty,
          reason:
              'A bump landed in some places but not all. Change the workflow(s) '
              'AND $manifestPath in the same commit:\n  ${wrong.join('\n  ')}',
        );
      },
    );

    test('each pinned action is used at the version the manifest claims', () {
      final wrong = <String>[];
      for (final action in actions) {
        final uses = action['uses'] as String;
        final version = action['version'] as String;
        for (final path in (action['workflows'] as List).cast<String>()) {
          if (!workflows[path]!.contains('uses: $uses@$version')) {
            wrong.add('$path is missing `uses: $uses@$version`');
          }
        }
      }
      expect(
        wrong,
        isEmpty,
        reason:
            'A pinned Action and its manifest entry disagree:\n'
            '  ${wrong.join('\n  ')}',
      );
    });

    test('no workflow carries a *_VERSION pin the manifest does not list', () {
      // Deliberately scans EVERY workflow in both directories, not only the
      // ones the manifest already names — a new file is exactly how a pin would
      // slip in unwatched.
      final pattern = RegExp(r'^\s*([A-Z0-9_]+_VERSION):\s*(\S+)\s*$');
      final known = {for (final tool in tools) tool['env'] as String};
      final unlisted = <String>[];

      for (final dir in ['.github/workflows', '.forgejo/workflows']) {
        final directory = Directory(dir);
        if (!directory.existsSync()) continue;
        for (final file in directory.listSync().whereType<File>()) {
          if (!file.path.endsWith('.yml') && !file.path.endsWith('.yaml')) {
            continue;
          }
          for (final line in file.readAsLinesSync()) {
            final match = pattern.firstMatch(line);
            if (match != null && !known.contains(match.group(1))) {
              unlisted.add('${file.path}: ${match.group(1)}');
            }
          }
        }
      }

      expect(
        unlisted.toSet().toList(),
        isEmpty,
        reason:
            'A workflow pins a version that nothing monitors for staleness. '
            'Add it to $manifestPath (see #802 for why an unwatched pin is '
            'worse than no pin):\n  ${unlisted.toSet().join('\n  ')}',
      );
    });
  });

  group('the manifest is sound on its own', () {
    test('every entry carries the fields the freshness check needs', () {
      final broken = <String>[];
      void require(
        Map<String, dynamic> entry,
        List<String> keys,
        String label,
      ) {
        for (final key in keys) {
          final value = entry[key];
          if (value is! String || value.isEmpty) {
            broken.add('$label has no `$key`');
          }
        }
        final workflowList = entry['workflows'];
        if (workflowList is! List || workflowList.isEmpty) {
          broken.add('$label lists no workflows');
        }
      }

      for (final action in actions) {
        require(action, [
          'uses',
          'version',
          'purpose',
          'source',
          'api',
        ], 'action ${action['uses']}');
      }
      for (final tool in tools) {
        require(tool, [
          'name',
          'env',
          'version',
          'purpose',
          'source',
          'api',
        ], 'tool ${tool['name']}');
      }

      expect(broken, isEmpty, reason: broken.join('\n  '));
    });

    test('every source is one the freshness check knows how to read', () {
      // An unknown source would make `make check-pins` exit 2 rather than
      // report a stale pin — a monitor that cannot run is a monitor that says
      // nothing, so it fails here instead, in the gate everyone runs.
      const known = {'github_release', 'pypi'};
      final unknown = [
        for (final entry in [...actions, ...tools])
          if (!known.contains(entry['source']))
            '${entry['uses'] ?? entry['name']}: ${entry['source']}',
      ];
      expect(
        unknown,
        isEmpty,
        reason:
            'Unknown source(s) in $manifestPath — teach '
            'tool/check_pinned_versions.dart to read them first:\n'
            '  ${unknown.join('\n  ')}',
      );
    });
  });
}
