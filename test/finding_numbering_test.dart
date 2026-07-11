import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/finding_group_builder.dart';
import 'package:ocideck/services/finding_numbering.dart';

const _cvss = 'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N';

Deck _deck(List<Slide> slides) =>
    Deck(title: 'Pentest', slides: [Slide.create(SlideType.title), ...slides]);

void main() {
  group('applyFindingPrefix', () {
    test('replaces an existing F-NN prefix', () {
      expect(
        applyFindingPrefix('F-9 · SQL injection', 'F-01'),
        'F-01 · SQL injection',
      );
    });
    test('prepends when there is no prefix', () {
      expect(
        applyFindingPrefix('SQL injection', 'F-02'),
        'F-02 · SQL injection',
      );
    });
    test('an empty heading becomes just the id', () {
      expect(applyFindingPrefix('   ', 'F-03'), 'F-03');
    });
  });

  group('renumberFindings', () {
    test('numbers groups sequentially and rewrites id + heading + members', () {
      final groupA = buildFindingGroup(
        spec: const FindingSpec(
          heading: 'F-9 · SQL injection',
          cvssVector: _cvss,
        ),
        findingId: 'X-9',
        addDetail: true,
      );
      final groupB = buildFindingGroup(
        spec: const FindingSpec(heading: 'XSS'),
        findingId: 'Z-2',
      );
      final out = renumberFindings(_deck([...groupA, ...groupB]));

      final findings = out.slides
          .where((s) => s.type == SlideType.finding)
          .toList();
      expect(findings[0].findingId, 'F-01');
      expect(findings[1].findingId, 'F-02');
      // Header heading prefix is renumbered in place.
      expect(
        FindingSpec.parse(findings[0].customMarkdown).heading,
        'F-01 · SQL injection',
      );
      // Every member of group A inherits F-01.
      final groupAIds = out.slides
          .where((s) => s.findingId == 'F-01')
          .map((s) => s.findingRole)
          .toList();
      expect(groupAIds, containsAll(FindingRole.values.take(2)));
    });

    test('a header with an empty id still gets a number', () {
      final lone = Slide.create(SlideType.finding).copyWith(
        customMarkdown: const FindingSpec(heading: 'Lone').toMarkdown(),
      );
      final out = renumberFindings(_deck([lone]));
      final header = out.slides.firstWhere((s) => s.type == SlideType.finding);
      expect(header.findingId, 'F-01');
    });

    test('a deck without findings is returned unchanged', () {
      final deck = _deck([Slide.create(SlideType.bullets)]);
      expect(identical(renumberFindings(deck), deck), isTrue);
    });
  });

  group('deckFindingList', () {
    test('lists one entry per header with its heading and severity', () {
      final groupA = buildFindingGroup(
        spec: const FindingSpec(heading: 'F-01 · SQLi', cvssVector: _cvss),
        findingId: 'F-01',
        addDetail: true,
      );
      final groupB = buildFindingGroup(
        spec: const FindingSpec(heading: 'F-02 · XSS'),
        findingId: 'F-02',
      );
      final list = deckFindingList(_deck([...groupA, ...groupB]));
      expect(list.map((e) => e.id), ['F-01', 'F-02']);
      expect(list.first.heading, 'F-01 · SQLi');
      expect(list.first.severity, isNot(Cvss4Severity.none));
      expect(list.last.severity, Cvss4Severity.none); // no vector
    });
  });
}
