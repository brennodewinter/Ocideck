import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/reader/documentation_search_tab.dart';

/// Unit tests for the pure query/match logic behind the documentation search
/// (Settings → Documentation). The widget itself only wires these into the UI.
void main() {
  group('parseQueryTerms', () {
    test('splits on whitespace and drops empties', () {
      expect(parseQueryTerms('  export   pdf '), ['export', 'pdf']);
    });

    test('blank query yields no terms', () {
      expect(parseQueryTerms('   '), isEmpty);
      expect(parseQueryTerms(''), isEmpty);
    });
  });

  group('matchDoc', () {
    const content =
        '# Architectuur\n\nDe app gebruikt Riverpod voor state management.\n'
        'Export gebeurt in een isolate zodat de UI vloeiend blijft.';

    test('matches a word from the body, case-insensitively', () {
      final hit = matchDoc(
        title: 'Architectuur',
        content: content,
        terms: parseQueryTerms('RIVERPOD'),
      );
      expect(hit, isNotNull);
      expect(hit!.snippet.toLowerCase(), contains('riverpod'));
      // The matched word is marked for highlighting.
      expect(hit.highlights, isNotEmpty);
      final marked = hit.snippet.substring(
        hit.highlights.first.start,
        hit.highlights.first.end,
      );
      expect(marked.toLowerCase(), 'riverpod');
    });

    test('all terms must be present (AND narrows the results)', () {
      // Both words occur → match.
      expect(
        matchDoc(
          title: 'Architectuur',
          content: content,
          terms: parseQueryTerms('export isolate'),
        ),
        isNotNull,
      );
      // Second word absent → no match.
      expect(
        matchDoc(
          title: 'Architectuur',
          content: content,
          terms: parseQueryTerms('export zeppelin'),
        ),
        isNull,
      );
    });

    test('matches on the title even when absent from the body', () {
      final hit = matchDoc(
        title: 'Sneltoetsen',
        content: 'Geen enkel relevant woord hier.',
        terms: parseQueryTerms('sneltoetsen'),
      );
      expect(hit, isNotNull);
      // Title-only match still offers a body excerpt for context.
      expect(hit!.snippet, isNotEmpty);
    });

    test('no terms yields no hit', () {
      expect(matchDoc(title: 'X', content: content, terms: const []), isNull);
    });

    test('snippet collapses whitespace and brackets a trimmed body', () {
      final long =
          'Voorwoord. ${'vulling ' * 40}NEEDLE ${'staart ' * 40}einde.';
      final hit = matchDoc(
        title: 'Doc',
        content: long,
        terms: parseQueryTerms('needle'),
      );
      expect(hit, isNotNull);
      // No double spaces or newlines survive the collapse.
      expect(hit!.snippet.contains('  '), isFalse);
      expect(hit.snippet.contains('\n'), isFalse);
      // Trimmed on both sides → ellipsis brackets.
      expect(hit.snippet.startsWith('… '), isTrue);
      expect(hit.snippet.endsWith(' …'), isTrue);
    });
  });
}
