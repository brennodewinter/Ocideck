import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/quality_export_policy.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';

const _qualityWarning = SlideQualityResult([
  SlideQualityIssue(
    slideIndex: 0,
    kind: SlideQualityIssueKind.imageContrastUnverified,
    category: SlideQualityCategory.contrast,
    severity: MarkdownValidationSeverity.warning,
  ),
]);

const _qualityError = SlideQualityResult([
  SlideQualityIssue(
    slideIndex: 0,
    kind: SlideQualityIssueKind.textDensityCritical,
    category: SlideQualityCategory.textDensity,
    severity: MarkdownValidationSeverity.error,
  ),
]);

/// Zelfs een test komt alleen via de projectiegrens aan een AudienceDeck — de
/// constructor is private. Dat is precies de bedoeling.
ExportBundle _emptyBundle(
  PrivacyExportProfile profile, {
  bool includeDetail = true,
}) => _bundleOf(const Deck(title: 'Test'), profile);

ExportBundle _bundleOf(Deck deck, PrivacyExportProfile profile) => ExportBundle(
  audience: PrivacyProjection.forAudience(deck, profile: profile),
  markdown: '',
  manifest: RedactionManifest.empty,
  privacySummary: PrivacyExportSummary.empty,
);

void main() {
  test('quality warnings require acknowledgement before export proceeds', () {
    final decision = const QualityExportPolicy().evaluate(_qualityWarning);
    expect(decision.allowed, isFalse);
    expect(decision.canAcknowledge, isTrue);
    expect(decision.warningCount, 1);
  });

  testWidgets('export dialog offers a normal/compressed image choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            bundleFor: _emptyBundle,
            exportService: ExportService(),
          ),
        ),
      ),
    );

    expect(find.text('Afbeeldingskwaliteit (PDF)'), findsOneWidget);
    // De kwaliteitskeuze zit achter de inklapbare kop (progressive
    // disclosure); openklappen toont de segmentknop.
    //
    // Eerst in beeld scrollen: het dialoog is `scrollable`, en op het 800×600-
    // testoppervlak valt de kop onder de vouw. Zonder dit mist de tik het doel —
    // een artefact van de testmaat, niet van de layout.
    final imageQuality = find.text('Afbeeldingskwaliteit (PDF)');
    await tester.ensureVisible(imageQuality);
    await tester.pumpAndSettle();
    await tester.tap(imageQuality);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SegmentedButton<bool>, 'Normaal'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(SegmentedButton<bool>, 'Gecomprimeerd'),
      findsOneWidget,
    );
    expect(find.text('PDF (plaatje per dia)'), findsOneWidget);
  });

  group('het sleutelbestand wordt bij naam genoemd', () {
    /// Een bundel mét manifest, dus mét salts: dan schrijft de export
    /// `…-redaction-keys.json` in dezelfde map als het rapport.
    ExportBundle bundleMetManifest(
      PrivacyExportProfile profile, {
      bool includeDetail = true,
    }) => ExportBundle(
      audience: PrivacyProjection.forAudience(
        const Deck(title: 'Test'),
        profile: profile,
      ),
      markdown: '',
      manifest: const RedactionManifest(
        derivedFrom: 'seal-abc',
        entries: [
          RedactionEntry(
            id: 'a3f1',
            commitment: 'deadbeef',
            rule: 'nl.bsn',
            slideIndex: 0,
            field: 'bullets',
            salt: 'peper',
          ),
        ],
      ),
      privacySummary: PrivacyExportSummary.empty,
    );

    Future<void> toon(
      WidgetTester tester,
      ExportBundle Function(PrivacyExportProfile, {bool includeDetail})
      bundleFor,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            bundleFor: bundleFor,
            exportService: ExportService(),
          ),
        ),
      ),
    );

    testWidgets(
      'met een manifest staan beide bestanden er, met de waarschuwing',
      (tester) async {
        // OciDeck schreef de sleutel naast de deur zonder het te zeggen: geen
        // tekst in de interface, geen regel in de handleiding. Met de salts is
        // elk weggelakt BSN in seconden terug te rekenen.
        await toon(tester, bundleMetManifest);

        expect(find.textContaining(kRedactionManifestSuffix), findsOneWidget);
        expect(find.textContaining(kRedactionKeysSuffix), findsOneWidget);
        expect(
          find.textContaining('Stuur dit bestand niet mee'),
          findsOneWidget,
        );
      },
    );

    testWidgets('zonder redacties zwijgt het dialoog erover', (tester) async {
      // Een waarschuwing bij een export zonder redacties is ruis, en ruis
      // leert de gebruiker deze alinea over te slaan.
      await toon(tester, _emptyBundle);

      expect(find.textContaining(kRedactionKeysSuffix), findsNothing);
    });
  });

  group('AI-concept: de auteur hoort het vóór de exportknop te lezen', () {
    ExportBundle bundelMetAiVeld(
      PrivacyExportProfile profile, {
      bool includeDetail = true,
    }) => ExportBundle(
      audience: PrivacyProjection.forAudience(
        Deck(
          title: 'Test',
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(aiAssistedFields: const ['description']),
          ],
        ),
        profile: profile,
      ),
      markdown: '',
      manifest: RedactionManifest.empty,
      privacySummary: PrivacyExportSummary.empty,
    );

    Future<void> toon(
      WidgetTester tester,
      ExportBundle Function(PrivacyExportProfile, {bool includeDetail})
      bundleFor,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            bundleFor: bundleFor,
            exportService: ExportService(),
          ),
        ),
      ),
    );

    testWidgets('meldt het achtervoegsel voordat het bestand er is', (
      tester,
    ) async {
      await toon(tester, bundelMetAiVeld);
      // Een naamsverandering die je pas achteraf ziet, is een verrassing —
      // dezelfde reden waarom "-geredigeerd" hier ook wordt aangekondigd.
      expect(find.textContaining('-ai-concept'), findsOneWidget);
    });

    testWidgets('zwijgt zodra de tekst is nagekeken', (tester) async {
      await toon(tester, _emptyBundle);
      expect(find.textContaining('-ai-concept'), findsNothing);
    });
  });

  testWidgets('shows quality banner when issues are present', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            bundleFor: _emptyBundle,
            exportService: ExportService(),
            qualityResult: _qualityWarning,
          ),
        ),
      ),
    );

    expect(find.textContaining('Slidekwaliteit'), findsOneWidget);
    expect(find.text('Bekijk meldingen…'), findsOneWidget);
  });

  testWidgets('blocks export UI when serious quality errors are enforced', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            bundleFor: _emptyBundle,
            exportService: ExportService(),
            qualityResult: _qualityError,
            qualityPolicy: const QualityExportPolicy(blockOnErrors: true),
          ),
        ),
      ),
    );

    expect(
      find.text('Export geblokkeerd vanwege ernstige kwaliteitsproblemen.'),
      findsOneWidget,
    );
    expect(find.text('PDF (plaatje per dia)'), findsNothing);
  });

  testWidgets('de groene balk belooft niets als de privacycontrole uit staat', (
    tester,
  ) async {
    Future<void> pump({required bool privacyChecksEnabled}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExportDialog(
                deckPath: '/tmp/deck.md',
                bundleFor: _emptyBundle,
                exportService: ExportService(),
                privacyChecksEnabled: privacyChecksEnabled,
              ),
            ),
          ),
        );

    await pump(privacyChecksEnabled: true);
    expect(
      find.textContaining('Geen kwaliteitsproblemen gevonden'),
      findsOneWidget,
    );

    // Zelfde deck, zelfde lege uitslag — maar er is niet gekeken. Dan mag de
    // balk dat niet als "schoon" verkopen, en moet hij zeggen waar het
    // aanstaat.
    await pump(privacyChecksEnabled: false);
    expect(
      find.textContaining('Geen kwaliteitsproblemen gevonden'),
      findsNothing,
    );
    expect(find.textContaining('de privacycontrole staat uit'), findsOneWidget);
  });

  // #627: het dialoog zweeg over de classificatie en exporteerde zonder enige
  // drempel. Wie TLP:RED koos zag rode markeringen op elke dia en mocht daar
  // iets van verwachten; als het alleen opmaak is, is dat erger dan geen
  // classificatie — dus zegt het dialoog nu welk van de twee het is.
  group('classificatie in het exportdialoog', () {
    Future<void> pumpMet(
      WidgetTester tester,
      TlpLevel tlp, {
      ClassificationEnforcementPolicy policy =
          const ClassificationEnforcementPolicy(),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportDialog(
              deckPath: '/tmp/deck.md',
              bundleFor: (profile, {bool includeDetail = true}) =>
                  _bundleOf(Deck(title: 'Test', tlp: tlp), profile),
              exportService: ExportService(),
              enforcementPolicy: policy,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('zonder classificatie staat er niets over', (tester) async {
      await pumpMet(tester, TlpLevel.none);
      expect(find.textContaining('TLP:'), findsNothing);
    });

    testWidgets('zonder handhaving zegt het dat het alleen een markering is', (
      tester,
    ) async {
      // Dit is de gewone toestand — handhaving is een aparte instelling — en
      // precies het geval waarin het dialoog eerder zweeg.
      await pumpMet(tester, TlpLevel.amber);
      expect(find.textContaining('TLP:AMBER'), findsOneWidget);
      expect(find.textContaining('geen drempel'), findsOneWidget);
    });

    testWidgets('mét handhaving zegt het dat er wél iets bewaakt wordt', (
      tester,
    ) async {
      await pumpMet(
        tester,
        TlpLevel.amber,
        policy: const ClassificationEnforcementPolicy(
          maxReleaseLevel: TlpLevel.red,
        ),
      );
      expect(find.textContaining('TLP:AMBER'), findsOneWidget);
      expect(find.textContaining('geen drempel'), findsNothing);
    });
  });
}
