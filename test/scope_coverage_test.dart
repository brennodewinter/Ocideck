import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/management_summary.dart';
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

  group('getallen die in een rapport belanden', () {
    Slide matrix(List<List<String>> rows) => Slide.create(
      SlideType.scopeMatrix,
    ).copyWith(title: 'Scope', tableRows: rows);

    test('onbereikbaar telt niet als getoetst', () {
      // "Onbereikbaar" betekent dat de tester er niet bij kón. Meetellen leverde
      // in het dossier "Scope-objecten getoetst: 3/3" op terwijl er één van de
      // drie was getest — en het gatenoverzicht bleef leeg.
      final deck = Deck(
        title: 'R',
        slides: [
          matrix([
            ['Object', 'Type', 'Owner', 'Status'],
            ['10.0.0.1', 'infra', '', 'Unreachable'],
            ['10.0.0.2', 'infra', '', 'Unreachable'],
            ['10.0.0.3', 'infra', '', 'Tested'],
          ]),
        ],
      );
      final summary = deckManagementSummary(deck);
      expect(summary.scopeObjectCount, 3);
      expect(summary.scopeTestedCount, 1);
      expect(deckScopeCoverageGaps(deck), hasLength(2));
    });

    test('afwijkend getest telt wél mee', () {
      final deck = Deck(
        title: 'R',
        slides: [
          matrix([
            ['Object', 'Type', 'Owner', 'Status'],
            ['a', 'web', '', 'Deviation'],
          ]),
        ],
      );
      expect(deckManagementSummary(deck).scopeTestedCount, 1);
      expect(deckScopeCoverageGaps(deck), isEmpty);
    });

    test('hetzelfde object op twee matrices telt één keer', () {
      final deck = Deck(
        title: 'R',
        slides: [
          matrix([
            ['Object', 'Type', 'Owner', 'Status'],
            ['https://c', 'web', '', 'Tested'],
          ]),
          matrix([
            ['Object', 'Type', 'Owner', 'Status'],
            ['https://c', 'web', '', 'Tested'],
            ['https://d', 'web', '', ''],
          ]),
        ],
      );
      final summary = deckManagementSummary(deck);
      expect(summary.scopeObjectCount, 2, reason: 'c en d, niet drie rijen');
      expect(summary.scopeTestedCount, 1);
    });

    test('de uitkomst hangt niet van de volgorde van de dia\'s af', () {
      final a = matrix([
        ['Object', 'Type', 'Owner', 'Status'],
        ['https://api', 'web', '', 'Tested'],
      ]);
      final b = matrix([
        ['Object', 'Type', 'Owner', 'Status'],
        ['https://api', 'web', '', ''],
      ]);
      final voor = deckScopeCoverageGaps(Deck(title: 'R', slides: [a, b]));
      final na = deckScopeCoverageGaps(Deck(title: 'R', slides: [b, a]));
      expect(voor.map((g) => g.object), na.map((g) => g.object));
      expect(
        voor,
        hasLength(1),
        reason: 'één niet-getoetste vermelding volstaat',
      );
    });
  });
}
