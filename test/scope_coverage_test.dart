import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/scope_coverage.dart';

Slide _scope(List<ScopeRow> rows) =>
    Slide.create(SlideType.scopeMatrix).copyWith(
      title: 'Scope',
      tableRows: ScopeMatrixSpec(title: 'Scope', rows: rows).toTableRows(),
    );

Slide _finding(String scopeObject) => Slide.create(SlideType.finding).copyWith(
  customMarkdown: FindingSpec(
    heading: 'F',
    scopeObject: scopeObject,
  ).toMarkdown(),
);

void main() {
  group('normalizeScopeObject', () {
    test('trims, lower-cases and drops a trailing slash', () {
      expect(normalizeScopeObject('  https://App/API/ '), 'https://app/api');
    });
  });

  group('deckScopeCoverageGaps', () {
    test('flags an untested object with no finding', () {
      final deck = Deck(
        title: 'X',
        slides: [
          _scope([
            const ScopeRow(
              object: 'https://app/login',
              type: ScopeObjectType.web,
            ),
            const ScopeRow(
              object: 'https://app/admin',
              type: ScopeObjectType.web,
              status: ScopeStatus.tested,
            ),
            const ScopeRow(
              object: 'https://app/api/',
              type: ScopeObjectType.api,
            ),
          ]),
          _finding('https://app/api'), // covers the api object (normalized)
        ],
      );
      final gaps = deckScopeCoverageGaps(deck);
      expect(gaps.map((g) => g.object), ['https://app/login']);
      expect(gaps.single.type, ScopeObjectType.web);
    });

    test('a tested object is not a gap even without a finding', () {
      final deck = Deck(
        title: 'X',
        slides: [
          _scope([const ScopeRow(object: 'x', status: ScopeStatus.deviation)]),
        ],
      );
      expect(deckScopeCoverageGaps(deck), isEmpty);
    });

    test('no scope matrix means no gaps', () {
      final deck = Deck(title: 'X', slides: [Slide.create(SlideType.title)]);
      expect(deckScopeCoverageGaps(deck), isEmpty);
    });
  });
}
