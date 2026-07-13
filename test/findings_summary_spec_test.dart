import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/findings_summary_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/markdown_service.dart';

// A CVSS 4.0 vector that scores 9.3 → Critical (the P1-FIND fixture).
const _criticalVector =
    'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N';

Slide _finding(String vector, {FindingRole role = FindingRole.header}) =>
    Slide.create(SlideType.finding).copyWith(
      customMarkdown: FindingSpec(cvssVector: vector).toMarkdown(),
      findingRole: role,
    );

void main() {
  group('FindingsSummarySpec', () {
    test('fromSeverities tallies per band', () {
      final spec = FindingsSummarySpec.fromSeverities('Overzicht', const [
        Cvss4Severity.critical,
        Cvss4Severity.critical,
        Cvss4Severity.high,
        Cvss4Severity.none,
      ]);
      expect(spec.countOf(Cvss4Severity.critical), 2);
      expect(spec.countOf(Cvss4Severity.high), 1);
      expect(spec.countOf(Cvss4Severity.medium), 0);
      expect(spec.countOf(Cvss4Severity.none), 1);
      expect(spec.total, 4);
    });

    test('toTableRows/fromSlide is a fixed point over all five bands', () {
      final spec = FindingsSummarySpec.fromSeverities('Overzicht', const [
        Cvss4Severity.critical,
        Cvss4Severity.medium,
        Cvss4Severity.medium,
        Cvss4Severity.low,
      ]);
      final rows = spec.toTableRows();
      expect(rows.first, FindingsSummarySpec.header);
      // Header + one row per band, worst first, with the stable English token.
      expect(rows.length, 1 + FindingsSummarySpec.order.length);
      expect(rows[1], ['Critical', '1']);
      expect(rows[3], ['Medium', '2']);

      final back = FindingsSummarySpec.fromSlide('Overzicht', rows);
      expect(back.title, 'Overzicht');
      // The table representation is a fixed point (raw maps differ only in
      // whether zero bands are stored explicitly; the counts read the same).
      expect(back.toTableRows(), rows);
      for (final band in FindingsSummarySpec.order) {
        expect(back.countOf(band), spec.countOf(band));
      }
      expect(back.total, 4);
    });

    test('fromSlide ignores unknown bands and non-numeric counts', () {
      final back = FindingsSummarySpec.fromSlide('X', const [
        ['Severity', 'Count'],
        ['Critical', '3'],
        ['Bogus', '9'],
        ['High', 'n/a'],
      ]);
      expect(back.countOf(Cvss4Severity.critical), 3);
      expect(back.countOf(Cvss4Severity.high), 0);
      expect(back.total, 3);
    });
  });

  group('deckFindingSeverities', () {
    test('counts each finding header once; missing vector → informational', () {
      final slides = [
        _finding(_criticalVector),
        _finding(''), // no vector → none/informational
        _finding(_criticalVector, role: FindingRole.detail), // skipped
        Slide.create(SlideType.bullets), // non-finding → skipped
      ];
      expect(deckFindingSeverities(slides), [
        Cvss4Severity.critical,
        Cvss4Severity.none,
      ]);
    });

    test('a rated scope object shifts a finding to its context band', () {
      final scope = Slide.create(SlideType.scopeMatrix).copyWith(
        tableRows: ScopeMatrixSpec(
          rows: const [
            ScopeRow(
              object: 'https://app.example',
              cia: CiaRating(
                confidentiality: CiaLevel.low,
                integrity: CiaLevel.low,
                availability: CiaLevel.low,
              ),
            ),
          ],
        ).toTableRows(),
      );
      final finding = Slide.create(SlideType.finding).copyWith(
        customMarkdown: const FindingSpec(
          scopeObject: 'https://app.example',
          cvssVector: _criticalVector,
        ).toMarkdown(),
      );
      // Base 9.3 (Critical) is weighted down to 8.9 (High) by the low CIA rating.
      expect(deckFindingSeverities([scope, finding]), [Cvss4Severity.high]);
    });
  });

  test('findingsSummary slide round-trips as a Markdown table (P1-SUM)', () {
    final spec = FindingsSummarySpec.fromSeverities(
      'Bevindingenoverzicht',
      const [Cvss4Severity.critical, Cvss4Severity.high, Cvss4Severity.high],
    );
    final slide = Slide.create(
      SlideType.findingsSummary,
    ).copyWith(title: spec.title, tableRows: spec.toTableRows());
    final service = MarkdownService();
    final md = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
    expect(md, contains('<!-- _class: findings-summary -->'));
    expect(md, contains('| Severity | Count |'));

    final out = service.parseDeck(md)!.slides.single;
    expect(out.type, SlideType.findingsSummary);
    expect(out.title, 'Bevindingenoverzicht');
    final back = FindingsSummarySpec.fromSlide(out.title, out.tableRows);
    expect(back.countOf(Cvss4Severity.critical), 1);
    expect(back.countOf(Cvss4Severity.high), 2);
    expect(back.total, 3);
  });
}
