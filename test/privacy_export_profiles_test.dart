import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/redaction_manifest_service.dart';

// Exportprofielen: één bron, twee versies.
//
// Dit is de kern van het pentestrapport-scenario. De opdrachtgever moet de
// bevinding kúnnen natrekken, dus die krijgt alles. De bredere kring krijgt
// hetzelfde rapport met de persoonsgegevens eruit.
//
// Zonder deze keuze zou je moeten kiezen TÚSSEN die twee — en dan wint in de
// praktijk altijd de volledige versie, want die moet nu eenmaal de deur uit.
void main() {
  Deck briefing({PrivacyDisposition? stand}) => Deck(
    title: 'Briefing',
    slides: [
      Slide.create(SlideType.bullets).copyWith(
        bullets: ['BSN 728398242 — mail j.jansen@andersbureau.nl'],
        privacy: stand,
      ),
    ],
  );

  group('volledig — voor de opdrachtgever', () {
    test('een geaccepteerde slide blijft leesbaar', () {
      // Anders kan de opdrachtgever de bevinding niet natrekken, en dan is het
      // rapport waardeloos voor het doel waarvoor het gemaakt is.
      final out = PrivacyProjection.forAudience(
        briefing(stand: PrivacyDisposition.accept),
        profile: PrivacyExportProfile.full,
      );
      expect(out.slides.single.bullets.single, contains('728398242'));
      expect(out.hasRedactions, isFalse);
    });

    test('maar wat de auteur op "weglaten" zette, gaat er wél uit', () {
      final out = PrivacyProjection.forAudience(
        briefing(stand: PrivacyDisposition.redact),
        profile: PrivacyExportProfile.full,
      );
      expect(out.slides.single.bullets.single.contains('728398242'), isFalse);
    });

    test('geen achtervoegsel in de bestandsnaam', () {
      expect(PrivacyExportProfile.full.fileSuffix, '');
    });
  });

  group('geredigeerd — voor de bredere kring', () {
    test('ook een geaccepteerde slide gaat eruit', () {
      // "Deze zaal mag het zien" is niet hetzelfde als "iedereen mag het zien".
      final out = PrivacyProjection.forAudience(
        briefing(stand: PrivacyDisposition.accept),
        profile: PrivacyExportProfile.redacted,
      );
      final bullet = out.slides.single.bullets.single;

      expect(bullet.contains('728398242'), isFalse);
      expect(bullet.contains('j.jansen@andersbureau.nl'), isFalse);
      expect(out.redactionCount, 2);
    });

    test('en een onbesliste slide ook', () {
      final out = PrivacyProjection.forAudience(
        briefing(),
        profile: PrivacyExportProfile.redacted,
      );
      expect(out.slides.single.bullets.single.contains('728398242'), isFalse);
    });

    test('het profiel staat in de bestandsnaam', () {
      // Niet cosmetisch: de duurste fout die je met deze feature kunt maken is
      // het volledige exemplaar naar de brede kring sturen. Een verwisseling moet
      // je kunnen ZIEN, niet hoeven onthouden.
      expect(PrivacyExportProfile.redacted.fileSuffix, '-geredigeerd');
    });
  });

  group('het manifest volgt het profiel', () {
    final service = RedactionManifestService();

    test('volledig: alleen de expliciete redacties', () {
      final manifest = service.build(
        briefing(stand: PrivacyDisposition.accept),
        profile: PrivacyExportProfile.full,
      );
      expect(manifest.isEmpty, isTrue);
    });

    test('geredigeerd: alles wat is weggehaald staat erin', () {
      final manifest = service.build(
        briefing(stand: PrivacyDisposition.accept),
        profile: PrivacyExportProfile.redacted,
      );
      expect(manifest.entries, hasLength(2));
      expect(
        manifest.entries.map((e) => e.rule),
        containsAll(<String>['nl.bsn', 'contact.email']),
      );
    });

    test('en het is verifieerbaar tegen dezelfde bron', () {
      final source = briefing(stand: PrivacyDisposition.accept);
      final manifest = service.build(
        source,
        profile: PrivacyExportProfile.redacted,
      );
      expect(
        service.verifyAgainstSource(
          manifest,
          source,
          profile: PrivacyExportProfile.redacted,
        ),
        isTrue,
      );
    });

    test('tegen de verkeerde lat gelegd verifieert het niet', () {
      // Een geredigeerd exemplaar bevat méér redacties dan een volledig. Zou de
      // verificatie het profiel negeren, dan zou een eerlijk manifest ten
      // onrechte verdacht worden — en dat is precies het valse alarm dat we bij
      // het zegel al wilden voorkomen.
      final source = briefing(stand: PrivacyDisposition.accept);
      final manifest = service.build(
        source,
        profile: PrivacyExportProfile.redacted,
      );
      expect(
        service.verifyAgainstSource(
          manifest,
          source,
          profile: PrivacyExportProfile.full,
        ),
        isFalse,
      );
    });
  });

  test('de sleutels round-trippen', () {
    for (final profile in PrivacyExportProfile.values) {
      expect(PrivacyExportProfileX.fromKey(profile.key), profile);
    }
    expect(PrivacyExportProfileX.fromKey(null), PrivacyExportProfile.full);
    expect(PrivacyExportProfileX.fromKey('onzin'), PrivacyExportProfile.full);
  });
}
