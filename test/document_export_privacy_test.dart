// De fail-closed garantie van de documentmodus-export (DOCUMENT_MODE.md §11.5
// eis 2): een document met persoonsgegevens dat via het geredigeerde profiel de
// deur uit gaat, mág die gegevens niet meer dragen. De compiler geeft die
// garantie niet — hij dwingt af dát de body via een AudienceDeck reist, niet dát
// de projectie werkelijk redigeert. Deze test meet dat laatste.
//
// Het kop-geleide geval is met opzet gekozen: dat is de dominante documentvorm
// (§11.3), en juist waar het oude `_inferSlideType` een sectie stil naar een lege
// dia liet vallen. Het BSN staat zowel in de prosa (die een `freeMarkdown`-dia
// wordt) als in een tabelcel (een aparte `table`-dia), zodat beide takken van de
// bridge door de scan gaan.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  // Een geldig BSN (elfproef-conform) mét het contextwoord "BSN" ernaast, precies
  // de vorm die `privacy_projection_test.dart` als `certain` bewijst. Zowel in de
  // prosa als in de tabelrij.
  const bsn = '728398242';
  const body =
      '## Bevinding\n'
      '\n'
      'toelichting met BSN $bsn hier\n'
      '\n'
      '| Naam | BSN |\n'
      '| --- | --- |\n'
      '| Jan Jansen | $bsn |\n';

  Future<String> projectedBodyFor(PrivacyExportProfile profile) async {
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: profile,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
    );
    return projectedDocumentBody(bundle);
  }

  test('het geredigeerde profiel haalt het BSN uit de documentbody', () async {
    final out = await projectedBodyFor(PrivacyExportProfile.redacted);

    // Het nummer is weg — in de prosa én in de tabelcel.
    expect(out, isNot(contains(bsn)));
    // En er staat een redactiemarkering voor in de plaats. `kRedactionToken` is
    // exact wat de projectie in de uitvoer zet (privacy_projection_test.dart
    // hanteert dezelfde assertie).
    expect(out, contains(kRedactionToken));
  });

  test(
    'tijdlijn blijft atomair en lekt geen geredigeerde tabelwaarde',
    () async {
      const timeline =
          '<!-- timeline -->\n'
          '| Tijd | Gebeurtenis | Status |\n'
          '| --- | --- | --- |\n'
          '| 13:41 | BSN $bsn bevestigd | Vastgesteld |\n';
      final bundle = await buildDocumentExportBundle(
        timeline,
        projectPath: null,
        profile: PrivacyExportProfile.redacted,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
      );
      final out = projectedDocumentBody(bundle);

      expect(out, isNot(contains(bsn)));
      expect(out, contains('<!-- timeline -->\n| Tijd |'));
    },
  );

  test('samengestelde chrome wordt vóór de projectie gescand', () async {
    final bundle = await buildDocumentExportBundle(
      '# Rapport\n',
      projectPath: null,
      profile: PrivacyExportProfile.redacted,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      fields: const {'local': 'jan.jansen', 'domain': 'andersbureau.nl'},
      theme: const ThemeProfile(documentHeaderText: '{local}@{domain}'),
    );

    expect(
      bundle.audience.deck.themeProfile.documentHeaderText,
      kRedactionToken,
    );
  });

  test(
    'oversize documentvelden stoppen de privacybundel fail-closed',
    () async {
      await expectLater(
        buildDocumentExportBundle(
          '# Rapport\n',
          projectPath: null,
          profile: PrivacyExportProfile.redacted,
          ownIdentity: OwnIdentity.empty,
          regions: defaultPrivacyRegions,
          disabledRules: const {},
          markdownService: MarkdownService(),
          fields: {'klant': 'x' * (kMaxPrivacyDocumentFieldChars + 1)},
        ),
        throwsA(
          isA<PrivacyDocumentLimitExceeded>().having(
            (error) => error.message,
            'message',
            contains('maximaal 4096'),
          ),
        ),
      );
    },
  );

  for (final field in ['title', 'subtitle', 'author']) {
    test('$field wordt begrensd vóór de privacyscanner begint', () async {
      await expectLater(
        buildDocumentExportBundle(
          '# Rapport\n',
          projectPath: null,
          profile: PrivacyExportProfile.redacted,
          ownIdentity: OwnIdentity.empty,
          regions: defaultPrivacyRegions,
          disabledRules: const {},
          markdownService: MarkdownService(),
          fields: {field: 'x' * (kMaxPrivacyDocumentFieldChars + 1)},
        ),
        throwsA(isA<PrivacyDocumentLimitExceeded>()),
      );
    });
  }

  test('een afgeleide H1-titel wordt vóór de detectoren begrensd', () async {
    await expectLater(
      buildDocumentExportBundle(
        '# Rapport\n',
        projectPath: null,
        profile: PrivacyExportProfile.redacted,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
        title: 'x' * (kMaxPrivacyDocumentFieldChars + 1),
      ),
      throwsA(isA<PrivacyDocumentLimitExceeded>()),
    );
  });

  test('te veel documentvelden stoppen de privacybundel fail-closed', () async {
    await expectLater(
      buildDocumentExportBundle(
        '# Rapport\n',
        projectPath: null,
        profile: PrivacyExportProfile.redacted,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
        fields: {
          for (var i = 0; i <= kMaxPrivacyDocumentFields; i++) 'veld-$i': 'x',
        },
      ),
      throwsA(
        isA<PrivacyDocumentLimitExceeded>().having(
          (error) => error.message,
          'message',
          contains('maximaal 100'),
        ),
      ),
    );
  });

  test(
    'het volledige profiel laat het BSN staan — zo meet de test de redactie echt',
    () async {
      // De tegentest: zonder deze zou de redactie-assertie ook slagen als de body
      // toevallig altijd leeg was. Bij het volledige profiel hoort het nummer er
      // nog te zijn.
      final out = await projectedBodyFor(PrivacyExportProfile.full);
      expect(out, contains(bsn));
    },
  );
}
