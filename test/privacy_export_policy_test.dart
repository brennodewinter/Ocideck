import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

import 'support/export_bundle_fixture.dart';

// De export-gate.
//
// De kern: hij straft geen persoonsgegevens af, hij straft ONOPGEMERKTE
// persoonsgegevens af. Een briefing waarin alles bewust geaccepteerd is, moet er
// zonder onderbreking doorheen — anders leert de gebruiker precies één ding: dat
// hij dit dialoog kan wegklikken.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const scanner = PrivacyScanner();

  Deck deckMet({PrivacyDisposition? stand, PrivacyDisposition? deckStand}) =>
      Deck(
        title: 'Briefing',
        privacy: deckStand ?? PrivacyDisposition.warn,
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            bullets: ['BSN 728398242', 'mail j.jansen@andersbureau.nl'],
            privacy: stand,
          ),
        ],
      );

  PrivacyExportSummary summarise(Deck deck) =>
      summarisePrivacyForExport(deck, scanner.scan(deck));

  group('samenvatting', () {
    test('telt onafgehandelde bevindingen', () {
      final s = summarise(deckMet());
      expect(s.unresolved, 2);
      expect(s.accepted, 0);
      expect(s.total, 2);
    });

    test('telt geaccepteerd, geshield en geredigeerd apart', () {
      expect(summarise(deckMet(stand: PrivacyDisposition.accept)).accepted, 2);
      expect(summarise(deckMet(stand: PrivacyDisposition.shield)).shielded, 2);
      expect(summarise(deckMet(stand: PrivacyDisposition.redact)).redacted, 2);

      for (final stand in [
        PrivacyDisposition.accept,
        PrivacyDisposition.shield,
        PrivacyDisposition.redact,
      ]) {
        expect(
          summarise(deckMet(stand: stand)).unresolved,
          0,
          reason: '$stand',
        );
      }
    });

    test('de deckstand telt mee', () {
      expect(
        summarise(deckMet(deckStand: PrivacyDisposition.accept)).unresolved,
        0,
      );
    });

    test('een informatieve hint telt niet als onafgehandeld', () {
      // Een 9-cijferig getal zonder contextwoord halen we er wel uit, maar we
      // weten zelf niet zeker of het een BSN is. Daarop een export blokkeren zou
      // de gate meteen ongeloofwaardig maken.
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(bullets: ['Ordernummer 728398242 verwerkt']),
        ],
      );
      final s = summarisePrivacyForExport(deck, scanner.scan(deck));
      expect(s.unresolved, 0);
      expect(s.isEmpty, isTrue);
    });
  });

  group('de gate', () {
    const summary = PrivacyExportSummary(unresolved: 2, accepted: 1);
    const schoon = PrivacyExportSummary(accepted: 3, redacted: 2);

    test('uit: altijd toestaan', () {
      const policy = PrivacyExportPolicy(gate: PrivacyExportGate.off);
      expect(policy.evaluate(summary).allowed, isTrue);
    });

    test('waarschuwen: onderbreken, maar er mag bewust langs', () {
      const policy = PrivacyExportPolicy(gate: PrivacyExportGate.warn);
      final decision = policy.evaluate(summary);

      expect(decision.allowed, isFalse);
      expect(decision.canAcknowledge, isTrue);
      expect(decision.hardBlocked, isFalse);
      expect(decision.summary.unresolved, 2);
    });

    test('blokkeren: geen weg eromheen', () {
      const policy = PrivacyExportPolicy(gate: PrivacyExportGate.block);
      final decision = policy.evaluate(summary);

      expect(decision.allowed, isFalse);
      expect(decision.canAcknowledge, isFalse);
      expect(decision.hardBlocked, isTrue);
    });

    test('een deck waarin alles is afgehandeld gaat er zonder kik doorheen', () {
      // Dit is het punt van de hele gate. De briefing van de recherche bevat
      // persoonsgegevens, bewust, en die mag niet elke keer onderbroken worden —
      // anders klikt de gebruiker het dialoog straks blind weg.
      for (final gate in PrivacyExportGate.values) {
        expect(
          PrivacyExportPolicy(gate: gate).evaluate(schoon).allowed,
          isTrue,
          reason: '$gate',
        );
      }
    });

    test('de harde blokkade werkt óók zonder de UI', () async {
      // De gate zit op het chokepoint in ExportService, niet alleen in het
      // dialoog. Een gate die alleen in een dialoog leeft, is er geen: elk pad
      // dat de dialoog omzeilt, omzeilt dan ook de blokkade.
      final result = await ExportService().export(
        '/tmp/deck.md',
        ExportFormat.html,
        const [],
        audience: bundleFor(const Deck(title: 'Kop'), markdown: '# Kop'),
        privacySummary: summary,
        privacyPolicy: const PrivacyExportPolicy(gate: PrivacyExportGate.block),
        // Zelfs mét een "de gebruiker heeft het gezien" gaat hij niet door.
        privacyAcknowledged: true,
      );

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });

    test('standaard is waarschuwen', () {
      expect(const PrivacyExportPolicy().gate, PrivacyExportGate.warn);
      expect(PrivacyExportGateX.fromKey(null), PrivacyExportGate.warn);
      expect(PrivacyExportGateX.fromKey('onzin'), PrivacyExportGate.warn);
      expect(PrivacyExportGateX.fromKey('block'), PrivacyExportGate.block);
    });
  });
}
