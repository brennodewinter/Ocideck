import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/management_summary.dart';

Slide _scope(List<ScopeRow> rows) =>
    Slide.create(SlideType.scopeMatrix).copyWith(
      title: 'Scope',
      tableRows: ScopeMatrixSpec(title: 'Scope', rows: rows).toTableRows(),
    );

Slide _checklist(String title) =>
    Slide.create(SlideType.checklist).copyWith(title: title);

Slide _finding(String vector) => Slide.create(SlideType.finding).copyWith(
  customMarkdown: FindingSpec(heading: 'F', cvssVector: vector).toMarkdown(),
);

const _critical =
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H';

Deck _deck() => Deck(
  title: 'Pentest',
  slides: [
    _scope([
      const ScopeRow(
        object: 'a',
        type: ScopeObjectType.web,
        status: ScopeStatus.tested,
      ),
      const ScopeRow(
        object: 'b',
        type: ScopeObjectType.api,
      ), // WSTG again → dedup
      const ScopeRow(object: 'c', type: ScopeObjectType.infra), // PTES
      const ScopeRow(object: 'd', type: ScopeObjectType.other), // no standard
    ]),
    _checklist('MASTG mobile checks'),
    _finding(_critical),
    _finding(''), // no vector → informational
  ],
);

void main() {
  group('deckStandardsUsed', () {
    test('collects scope standards + checklist labels, de-duplicated', () {
      expect(deckStandardsUsed(_deck()), [
        'WSTG',
        'PTES',
        'MASTG mobile checks',
      ]);
    });

    test('a deck with no scope or checklist has no standards', () {
      final deck = Deck(title: 'X', slides: [_finding(_critical)]);
      expect(deckStandardsUsed(deck), isEmpty);
    });
  });

  group('deckManagementSummary', () {
    test('derives findings, severities, standards and scope coverage', () {
      final s = deckManagementSummary(_deck());
      expect(s.findingCount, 2);
      expect(s.severities.countOf(Cvss4Severity.critical), 1);
      expect(s.severities.countOf(Cvss4Severity.none), 1);
      expect(s.standards, ['WSTG', 'PTES', 'MASTG mobile checks']);
      expect(s.scopeObjectCount, 4);
      expect(s.scopeTestedCount, 1);
    });

    test('an empty deck derives a zeroed summary', () {
      final s = deckManagementSummary(Deck(title: 'X'));
      expect(s.findingCount, 0);
      expect(s.standards, isEmpty);
      expect(s.scopeObjectCount, 0);
    });
  });
}
