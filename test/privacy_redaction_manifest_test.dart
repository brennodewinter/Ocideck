import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/redaction_manifest_service.dart';

// Het redactiemanifest: hoe een derde partij een geredigeerd rapport controleert
// zonder dat het zegel breekt.
/// Een deck dat is afgerond én opgeslagen: pas dan bestaat de zegelhash, want
/// die gaat over de bytes van de `.md`.
Deck _verzegeldEnOpgeslagen(Deck deck) {
  final md = MarkdownService();
  final afgerond = DocumentIntegrity(md).seal(deck);
  return DocumentIntegrity.recordWrittenBytes(
    afgerond,
    md.generateDeck(afgerond),
  );
}

void main() {
  final service = RedactionManifestService();

  Deck redactedDeck({String bsn = '728398242'}) => Deck(
    title: 'Pentestrapport',
    slides: [
      Slide.create(SlideType.bullets).copyWith(
        privacy: PrivacyDisposition.redact,
        bullets: ['BSN $bsn van betrokkene', 'mail j.jansen@politie.nl'],
      ),
    ],
  );

  test('bouwt één entry per geredigeerde waarde', () {
    final manifest = service.build(redactedDeck());
    expect(manifest.entries, hasLength(2));
    expect(
      manifest.entries.map((e) => e.rule),
      containsAll(<String>['nl.bsn', 'contact.email']),
    );
  });

  test('een slide die niet op redact staat levert geen entries op', () {
    final deck = Deck(
      title: 'D',
      slides: [
        Slide.create(SlideType.bullets).copyWith(
          privacy: PrivacyDisposition.accept,
          bullets: ['BSN 728398242'],
        ),
      ],
    );
    expect(service.build(deck).isEmpty, isTrue);
  });

  group('de salt is de beveiliging', () {
    test('dezelfde waarde levert in twee decks een ánder commitment op', () {
      // DIT is de test die ertoe doet. Zonder salt is een SHA-256 van een
      // geredigeerd BSN in seconden terug te rekenen — 10⁹ kandidaten — en dan
      // publiceer je precies wat je zojuist hebt weggelakt. Faalt deze test, dan
      // is de redactie waardeloos, hoe zwart de balk ook is.
      final a = service.build(redactedDeck()).entries.first;
      final b = service.build(redactedDeck()).entries.first;

      expect(a.salt, isNot(b.salt));
      expect(a.commitment, isNot(b.commitment));
    });

    test('het commitment bevat de waarde niet in leesbare vorm', () {
      final entry = service.build(redactedDeck()).entries.first;
      expect(entry.commitment.contains('728398242'), isFalse);
      expect(entry.salt.contains('728398242'), isFalse);
    });

    test('het exemplaar voor de geredigeerde versie draagt geen salts', () {
      // Een salt náást een commitment in het geredigeerde rapport zou de hele
      // exercitie ongedaan maken: dan is de waarde weer terug te rekenen.
      final full = service.build(redactedDeck());
      final shipped = full.withoutSalts;

      expect(full.carriesSalts, isTrue);
      expect(shipped.carriesSalts, isFalse);
      expect(shipped.entries, hasLength(full.entries.length));
      expect(shipped.toPrettyJson().contains('"salt"'), isFalse);
    });
  });

  group('verificatie', () {
    test('een eerlijk manifest verifieert tegen de bron', () {
      final source = redactedDeck();
      final manifest = service.build(source);
      expect(service.verifyAgainstSource(manifest, source), isTrue);
    });

    test('een manifest van een ánder deck verifieert niet', () {
      final manifest = service.build(redactedDeck());
      final ander = redactedDeck(bsn: '100000009');
      expect(service.verifyAgainstSource(manifest, ander), isFalse);
    });

    test('een weggelaten redactie valt op', () {
      final source = redactedDeck();
      final manifest = service.build(source);
      final geknipt = RedactionManifest(
        derivedFrom: manifest.derivedFrom,
        entries: [manifest.entries.first],
      );
      expect(service.verifyAgainstSource(geknipt, source), isFalse);
    });

    test('zonder salts valt er niets na te rekenen', () {
      final source = redactedDeck();
      final manifest = service.build(source);
      expect(
        service.verifyAgainstSource(manifest.withoutSalts, source),
        isFalse,
      );
    });

    test('selectieve openbaarmaking: één redactie openen, de rest niet', () {
      // Precies wat een derde partij nodig heeft die één bevinding wil natrekken
      // zonder het hele rapport ongeredigeerd te krijgen: de auteur onthult díé
      // salt en díé waarde, en bewijst daarmee wat redactie #xxxx verborg.
      final manifest = service.build(redactedDeck());
      final betwist = manifest.entries.firstWhere((e) => e.rule == 'nl.bsn');

      expect(
        RedactionManifestService.verifyEntry(
          betwist,
          salt: betwist.salt,
          value: '728398242',
        ),
        isTrue,
      );

      // Een verkeerde waarde bewijst niets — anders zou "openen" niets waard zijn.
      expect(
        RedactionManifestService.verifyEntry(
          betwist,
          salt: betwist.salt,
          value: '100000009',
        ),
        isFalse,
      );

      // En de andere redacties blijven dicht: hun salt is niet prijsgegeven.
      final ander = manifest.entries.firstWhere((e) => e.rule != 'nl.bsn');
      expect(ander.salt, isNot(betwist.salt));
    });
  });

  group('het zegel breekt niet meer', () {
    test('een geredigeerde afleiding geeft geen vals tamper-alarm', () {
      // Zonder deze status zou een auditor die het pakket natrekt tot
      // "GEMANIPULEERD" concluderen — en een vals alarm op een echt rapport is
      // erger dan geen integriteitscontrole hebben.
      final integrity = DocumentIntegrity(MarkdownService());
      final sealed = _verzegeldEnOpgeslagen(redactedDeck());
      final manifest = service.build(sealed);

      expect(integrity.verify(sealed), IntegrityStatus.intact);
      expect(
        integrity.verifyRedactedDerivative(
          manifest,
          sealed,
          verifier: service.verifyAgainstSource,
        ),
        IntegrityStatus.redactedDerivative,
      );
    });

    test('een manifest dat bij een andere bron hoort, is wél verdacht', () {
      final integrity = DocumentIntegrity(MarkdownService());
      final sealed = _verzegeldEnOpgeslagen(redactedDeck());
      final andereBron = _verzegeldEnOpgeslagen(redactedDeck(bsn: '100000009'));
      final manifest = service.build(sealed);

      expect(
        integrity.verifyRedactedDerivative(
          manifest,
          andereBron,
          verifier: service.verifyAgainstSource,
        ),
        IntegrityStatus.changed,
      );
    });

    test('het manifest pint de herkomst vast op de zegelhash', () {
      final sealed = _verzegeldEnOpgeslagen(redactedDeck());
      expect(service.build(sealed).derivedFrom, sealed.sealHash);
    });
  });

  test('round-trip door JSON', () {
    final manifest = service.build(redactedDeck());
    final back = RedactionManifest.fromJson(
      jsonDecode(manifest.toPrettyJson()) as Map<String, dynamic>,
    );
    expect(back.entries, hasLength(manifest.entries.length));
    expect(back.entries.first.commitment, manifest.entries.first.commitment);
    expect(back.entries.first.salt, manifest.entries.first.salt);
  });
}
