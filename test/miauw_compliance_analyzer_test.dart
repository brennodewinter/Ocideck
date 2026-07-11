import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/miauw_compliance.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/miauw_compliance_analyzer.dart';

const _analyzer = MiauwComplianceAnalyzer();

EisStatus _status(MiauwComplianceResult r, String id) =>
    r.results.firstWhere((x) => x.entry.id == id).status;

Slide _completeFinding() => Slide.create(SlideType.finding).copyWith(
  customMarkdown: const FindingSpec(
    heading: 'F-1 · SQLi',
    scopeObject: 'https://app/login',
    cvssVector:
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
    cweId: 89,
    cweName: 'SQL Injection',
    description: 'x',
    confirmation: 'y',
    impact: 'z',
    recommendation: 'w',
  ).toMarkdown(),
);

void main() {
  group('MiauwComplianceAnalyzer', () {
    test('an empty deck leaves automatic and manual EIS open', () {
      final r = _analyzer.analyze(
        Deck(title: 'Leeg', slides: [Slide.create(SlideType.title)]),
      );
      expect(_status(r, '4.2'), EisStatus.open); // no findings
      expect(_status(r, '4.7.2'), EisStatus.open); // per-finding, vacuous false
      expect(_status(r, '1.2'), EisStatus.open); // manual
      expect(r.metCount + r.openCount + r.waivedCount, r.total);
    });

    test('a complete finding satisfies the per-finding requirements', () {
      final r = _analyzer.analyze(
        Deck(
          title: 'Pentest',
          slides: [Slide.create(SlideType.title), _completeFinding()],
        ),
      );
      expect(_status(r, '4.2'), EisStatus.voldaan); // findings present
      expect(_status(r, '4.7.1'), EisStatus.voldaan); // scope object
      expect(_status(r, '4.7.2'), EisStatus.voldaan); // cvss
      expect(_status(r, '4.7.7'), EisStatus.voldaan); // cwe
      expect(_status(r, '3.2'), EisStatus.voldaan); // cvss (shared check)
    });

    test('a finding missing its CVSS keeps 4.7.2 open', () {
      final noCvss = Slide.create(SlideType.finding).copyWith(
        customMarkdown: const FindingSpec(heading: 'F-2').toMarkdown(),
      );
      final r = _analyzer.analyze(
        Deck(title: 'X', slides: [_completeFinding(), noCvss]),
      );
      expect(_status(r, '4.7.2'), EisStatus.open);
    });

    test('presence checks read the right slide types', () {
      final r = _analyzer.analyze(
        Deck(
          title: 'X',
          version: '1.0',
          slides: [
            Slide.create(SlideType.findingsSummary),
            Slide.create(SlideType.scopeMatrix),
            Slide.create(SlideType.checklist),
            Slide.create(SlideType.timeline),
            Slide.create(SlideType.signOff),
          ],
        ),
      );
      expect(_status(r, '4.3'), EisStatus.voldaan); // management summary
      expect(_status(r, '4.4'), EisStatus.voldaan); // scope
      expect(_status(r, '4.13'), EisStatus.voldaan); // checklist
      expect(_status(r, '4.5'), EisStatus.voldaan); // timeline
      expect(_status(r, '1.6'), EisStatus.voldaan); // sign-off
      expect(_status(r, '1.5'), EisStatus.voldaan); // report version
    });

    test('sealing satisfies 1.1', () {
      final open = _analyzer.analyze(Deck(title: 'X'));
      expect(_status(open, '1.1'), EisStatus.open);
      final sealed = _analyzer.analyze(
        Deck(title: 'X', finalized: true, sealHash: 'abc123'),
      );
      expect(_status(sealed, '1.1'), EisStatus.voldaan);
    });

    test('a waiver marks the EIS excluded and carries the reason', () {
      final r = _analyzer.analyze(
        Deck(
          title: 'X',
          miauwWaivers: const {'1.3': 'Klant vereist geen certificering'},
        ),
      );
      final res = r.results.firstWhere((x) => x.entry.id == '1.3');
      expect(res.status, EisStatus.uitgesloten);
      expect(res.waiverReason, 'Klant vereist geen certificering');
    });

    test('waiving a foundational EIS is surfaced but never blocks', () {
      final r = _analyzer.analyze(
        Deck(title: 'X', miauwWaivers: const {'1.6': 'reden'}),
      );
      expect(r.foundationalWaived.map((e) => e.entry.id), contains('1.6'));
    });
  });
}
