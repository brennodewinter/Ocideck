import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that the pull-request template does not hard-code the set of
/// supported languages.
///
/// It did, and it went stale in the worst possible way: the checklist named
/// eight (`nl/en/it/de/fr/es/fy/pap`) while `AppLocalizations.languageNames`
/// held 32. A contributor who ticked that box honestly was 24 languages short
/// and had no way to know it — the checklist was actively misleading rather
/// than merely incomplete.
///
/// The fix is not a fresher list; a fresher list rots the same way on the next
/// language. The template must point at the source of truth instead, so this
/// test asserts the *absence* of an enumeration rather than its correctness.
void main() {
  test('the PR template enumerates no language codes', () {
    final template = File('.github/PULL_REQUEST_TEMPLATE.md');
    expect(
      template.existsSync(),
      isTrue,
      reason: '.github/PULL_REQUEST_TEMPLATE.md is expected to exist',
    );

    // Three or more slash-separated two- or three-letter codes in a row. Three
    // is the threshold on purpose: a genuine sentence will not produce it,
    // while any attempt to re-list the languages will. Paths like `lib/l10n/x`
    // do not match because the segments there are longer than three letters or
    // contain non-letters.
    final enumeration = RegExp(r'\b[a-z]{2,3}(?:/[a-z]{2,3}){2,}\b');

    final lines = template.readAsLinesSync();
    final offenders = <String>[];
    for (var i = 0; i < lines.length; i++) {
      for (final match in enumeration.allMatches(lines[i])) {
        offenders.add('line ${i + 1}: ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The template hard-codes what looks like a language list:\n'
          '  ${offenders.join('\n  ')}\n'
          'Point at AppLocalizations.languageNames and `make add-l10n` instead — '
          'a list written out here goes stale the next time a language is added, '
          'and a stale checklist is worse than no checklist.',
    );
  });

  test('the PR template asks about the trade-off', () {
    final text = File(
      '.github/PULL_REQUEST_TEMPLATE.md',
    ).readAsStringSync().toLowerCase();

    // The gates in `make check` cover what can be mechanised. The weighing —
    // does this quietly make the user's decks less portable, does it add a
    // party that has to be trusted — cannot be. The template is the only place
    // an outside contributor ever sees it asked.
    expect(
      text,
      contains('file format'),
      reason: 'the trade-off item should name the file format as a trigger',
    );
    expect(
      text,
      anyOf(contains('trade-off'), contains('trade off')),
      reason:
          'the template should ask the contributor to describe the trade-off '
          'when a change touches the format, storage, a dependency, outgoing '
          'traffic or a promise',
    );
  });
}
