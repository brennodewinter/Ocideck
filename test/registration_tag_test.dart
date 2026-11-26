@Tags(['registration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the `registration` tag itself (#3218).
///
/// `make check-registrations` selects on tag, not on a hand-maintained file
/// list any more — that list was itself a place a silent gap could form. What
/// the tag cannot see, this file guards: a `*_test.dart` that *names* itself
/// `registration` or `invariant` without carrying the tag still runs in the
/// full suite but never in the fast gate before a merge.
void main() {
  final namesItself = RegExp(r'registration|invariant', caseSensitive: false);
  final carriesTag = RegExp(
    r"@Tags\s*\(\s*(?:const\s+)?\[[^\]]*'registration'",
  );

  test('a test naming itself registration/invariant carries the tag', () {
    final offenders = <String>[];
    for (final file
        in Directory('test')
            .listSync(recursive: true)
            .whereType<File>()
            .where((entry) => entry.path.endsWith('_test.dart'))) {
      final name = file.uri.pathSegments.last;
      if (namesItself.hasMatch(name) &&
          !carriesTag.hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these test files name themselves registration/invariant but do not '
          'carry the tag, so check-registrations silently skips them — put '
          "@Tags(['registration']) above the library directive",
    );
  });

  test('check-registrations selects by tag, not by a file list', () {
    final makefile = File('Makefile').readAsStringSync();
    final target = RegExp(
      '^check-registrations:[^\n]*\n((?:\t[^\n]*\n?)+)',
      multiLine: true,
    ).firstMatch(makefile);
    expect(
      target,
      isNotNull,
      reason: 'the check-registrations make target is missing',
    );
    final body = target!.group(1)!;
    expect(body, contains('--tags registration'));
    expect(
      body.contains('_test.dart'),
      isFalse,
      reason:
          'check-registrations names individual test files again — exactly '
          'the second list #3218 removed; select on the tag instead',
    );
  });
}
