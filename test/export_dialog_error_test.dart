import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';

/// Wat er gebeurt als een export mislukt met een *uitzondering* in plaats van
/// een nette [ExportResult] met `success: false`.
///
/// Aanleiding: de gebruiker meldde "hij hangt gewoon". De app stond op 0% CPU
/// stil — niet te renderen, maar te wachten op iets dat nooit kwam. De oorzaak
/// zat niet in de export zelf maar in het dialoog: `_export()` had geen enkele
/// `try/catch`, dus zodra er íets gooide (een frame-timeout in de rasterizer,
/// een schrijffout, wat dan ook) vloog de uitzondering ongevangen naar buiten
/// en werd de regel die de spinner uitzet nooit bereikt. Eeuwig draaien, geen
/// melding.
///
/// Het HTML-pad is hier met opzet gekozen: dat slaat de rasterizer over en gaat
/// recht naar de geïnjecteerde service, zodat de fout deterministisch te
/// plaatsen is zonder een offscreen render in de testomgeving.
class _ThrowingExportService extends ExportService {
  @override
  Future<ExportResult> export(
    String deckPath,
    ExportFormat format,
    List<Uint8List> images, {
    bool compress = false,
    Object? outputDirectory,
    Object? audience,
    Object? themeProfile,
    Object? cockpitColorScheme,
    Object? tlp,
    Object? enforcementPolicy,
    Object? qualityResult,
    Object? qualityPolicy,
    bool qualityAcknowledged = false,
    Object? metadata,
    Object? redactionManifest,
    Object? privacySummary,
    Object? privacyPolicy,
    bool privacyAcknowledged = false,
    Object? privacyProfile,
    bool includeDetail = true,
    String interfaceLanguageCode = 'nl',
  }) async {
    throw const FileSystemException('schijf vol');
  }
}

ExportBundle _bundleFor(
  PrivacyExportProfile profile, {
  bool includeDetail = true,
}) => ExportBundle(
  audience: PrivacyProjection.forAudience(
    const Deck(title: 'Test'),
    profile: profile,
  ),
  markdown: '# Test\n',
  manifest: RedactionManifest.empty,
  privacySummary: PrivacyExportSummary.empty,
);

void main() {
  testWidgets('een export die gooit toont een fout en blijft niet hangen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            bundleFor: _bundleFor,
            exportService: _ThrowingExportService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('HTML-bestand (werkt offline)'));
    // Bewust pump() in stappen en géén pumpAndSettle: een draaiende spinner
    // "settelt" nooit, dus pumpAndSettle zou hier juist bij de bug voor altijd
    // wachten — precies het gedrag dat we willen uitsluiten.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // De export gooide. Het dialoog hoort dan uit de laadstand te komen: de
    // fase-tekst "…samenstellen…" mag er niet meer staan — die blijven tonen ís
    // de hang die de gebruiker meldde.
    expect(
      find.textContaining('samenstellen'),
      findsNothing,
      reason: 'het dialoog blijft in de laadstand hangen na een fout',
    );

    // En er hoort een foutmelding te staan, net als bij een nette mislukking.
    expect(
      find.byIcon(Icons.error_outline),
      findsOneWidget,
      reason: 'een mislukte export hoort een foutmelding te tonen',
    );

    // De uitzondering mag niet ongevangen ontsnappen; dat is het gat waardoor de
    // UI nooit werd bijgewerkt.
    expect(
      tester.takeException(),
      isNull,
      reason:
          'de fout tijdens de export moet afgevangen worden, niet ontsnappen',
    );

    // En de melding zegt in welke stap het misging, plus de ruwe uitzondering.
    //
    // Zonder die stap stond er alleen de uitzondering, en die kan even
    // nietszeggend zijn als `Invalid argument(s): 1` — de melding uit #714, waar
    // niemand uit kon opmaken dat het renderen was omgevallen en niet het
    // schrijven. HTML rendert niet, dus dit pad hoort de schrijfstap te noemen.
    expect(find.textContaining('opgebouwd of weggeschreven'), findsOneWidget);
    expect(find.textContaining('schijf vol'), findsOneWidget);
  });
}
