import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/findings_summary_spec.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';
import 'support/pump_until.dart';

/// De exportknop zoals een gebruiker hem indrukt — door de héle dialoog heen.
///
/// `pdf_export_slide_types_test` roept `ExportService.export` rechtstreeks aan.
/// Dat dekt het renderen en het schrijven, maar slaat alles over wat de dialoog
/// er zelf omheen zet: de privacypoort, de kwaliteitspoort, het geprojecteerde
/// deck (`audience`), het stijlprofiel, TLP, het handhavingsbeleid, de
/// metadata en de doelmap. Elk van die zeven is een argument dat in de toets
/// zijn standaardwaarde had en in de app niet — en #714 ("Invalid argument(s):
/// 1", alleen PDF, alleen op een echt deck) is precies het soort fout dat zich
/// daar verstopt.
///
/// **De valkuil die dit bestand koste:** `Directory.systemTemp.createTemp()`
/// hoort in `setUp`, niet in de body van een `testWidgets`. Binnen die body
/// draait alles in een FakeAsync-zone, en een echte `dart:io`-future komt daar
/// nooit terug — de toets loopt dan zonder melding in zijn timeout. Dat kostte
/// bij #714 een verkeerde conclusie ("de dialoog hangt op een
/// bevestigingsvenster"); de dialoog is prima aanstuurbaar.
void main() {
  late Directory tmp;

  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = await Directory.systemTemp.createTemp('ocideck_export_dialog');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Slide checklist() {
    const spec = ChecklistSpec(
      standardLabel: 'Checklist — OWASP WSTG',
      rows: [
        ChecklistRow(
          id: 'WSTG-CRYP-01',
          test: 'Zwakke TLS-configuratie',
          status: ChecklistStatus.anomaly,
          findingId: 'F-001',
        ),
        ChecklistRow(id: 'WSTG-ATHN-02', test: 'Standaardwachtwoorden'),
      ],
    );
    return Slide.create(SlideType.checklist).copyWith(
      title: spec.standardLabel,
      tableRows: spec.toTableRows(),
      showChecklistProgress: true,
    );
  }

  Slide scopeMatrix() {
    const spec = ScopeMatrixSpec(
      title: 'Scope',
      rows: [
        ScopeRow(object: 'portal.example.nl', status: ScopeStatus.tested),
        ScopeRow(object: 'api.example.nl', status: ScopeStatus.deviation),
      ],
    );
    return Slide.create(
      SlideType.scopeMatrix,
    ).copyWith(title: spec.title, tableRows: spec.toTableRows());
  }

  Slide findingsSummary() {
    const spec = FindingsSummarySpec(
      title: 'Bevindingen',
      counts: {Cvss4Severity.critical: 1, Cvss4Severity.high: 3},
      resolved: 2,
    );
    return Slide.create(
      SlideType.findingsSummary,
    ).copyWith(title: spec.title, tableRows: spec.toTableRows());
  }

  /// Het deck uit de melding van #714: de vier types, gevuld, met de
  /// deckgegevens die de dialoog aan de export doorgeeft.
  Deck pentestDeck() => Deck(
    title: 'Pentestrapport',
    organization: 'Voorbeeld BV',
    author: 'B. de Winter',
    tlp: TlpLevel.amber,
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Beveiligingsonderzoek'),
      Slide.create(SlideType.finding).copyWith(
        title: 'Verouderde TLS-configuratie',
        bullets: const ['De portal accepteert TLS 1.0.'],
      ),
      checklist(),
      scopeMatrix(),
      findingsSummary(),
    ],
  );

  Future<void> pumpDialog(WidgetTester tester, Deck deck) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    ExportBundle bundleFor(
      PrivacyExportProfile profile, {
      bool includeDetail = true,
    }) => ExportBundle(
      audience: PrivacyProjection.forAudience(deck, profile: profile),
      markdown: '# ${deck.title}\n',
      manifest: RedactionManifest.empty,
      privacySummary: PrivacyExportSummary.empty,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '${tmp.path}/deck.md',
            bundleFor: bundleFor,
            exportService: ExportService(),
            exportDirectory: tmp.path,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Laat de export echt lopen. Renderen en de PDF-assemblage (een isolate)
  /// lopen op echte tijd; alleen pompen is niet genoeg, alleen wachten ook niet.
  /// Laat de export echt lopen.
  ///
  /// Renderen en de PDF-assemblage (een isolate) lopen op **echte** tijd, maar
  /// de dia's worden getekend door **frames** — en die twee komen uit
  /// verschillende klokken. `pump()` binnen `runAsync()` laat de dialoog leeg
  /// achter; de werkende vorm is afwisselen: echte tijd binnen `runAsync`, en
  /// het frame daarbuiten.
  List<File> pdfsIn(Directory dir) => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList();

  /// De melding die #714 opleverde stond in dit vlak. Faalt de export, dan wil
  /// de toets die tekst zien in plaats van een kaal "geen bestand".
  String? failureTextIn(WidgetTester tester) {
    // De uitslag staat in een `SelectableText` (het is meestal een pad, #646),
    // niet in een gewone `Text` — daar kijken levert een toets op die een
    // mislukking niet ziet.
    for (final e in find.byType(SelectableText).evaluate()) {
      final data = (e.widget as SelectableText).data;
      if (data != null && data.contains('mislukt')) return data;
    }
    return null;
  }

  Future<void> runExport(WidgetTester tester) async {
    // Wachten tot de export een uitkomst heeft: een PDF op schijf, of de
    // mislukkingsmelding. Ruim budget — PDF-generatie rendert elke dia naar een
    // afbeelding, encodeert en schrijft, en op de 4-core Linux-runner onder
    // `--concurrency=14` krijgt elk proces ~28% van een core. Hier stond
    // dezelfde lus met de hand geschreven; `pumpUntil` is hetzelfde patroon en
    // faalt met een leesbare melding in plaats van stil door te lopen naar een
    // toets die "geen bestand" zegt.
    await pumpUntil(
      tester,
      () => pdfsIn(tmp).isNotEmpty || failureTextIn(tester) != null,
      timeout: const Duration(seconds: 12),
      reason: 'de export leverde geen PDF en geen melding',
    );
  }

  testWidgets('de PDF-knop levert een bestand op een pentestdeck (#714)', (
    tester,
  ) async {
    await pumpDialog(tester, pentestDeck());

    final button = find.widgetWithText(OutlinedButton, 'PDF (plaatje per dia)');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);

    await runExport(tester);

    expect(
      failureTextIn(tester),
      isNull,
      reason: 'de dialoog meldde een mislukking',
    );
    expect(
      pdfsIn(tmp),
      hasLength(1),
      reason: 'geen PDF geschreven, en ook geen foutmelding',
    );
    expect(pdfsIn(tmp).single.lengthSync(), greaterThan(0));
  });

  testWidgets('ook gecomprimeerd, want dat is een eigen pad (#714)', (
    tester,
  ) async {
    // Gecomprimeerd rendert op 1280 in plaats van 1920 en stuurt elke dia door
    // decode → verkleinen → JPEG. Alleen PDF kent die tak — en PDF was het
    // enige formaat dat in #714 omviel.
    await pumpDialog(tester, pentestDeck());

    final quality = find.text('Afbeeldingskwaliteit (PDF)');
    await tester.ensureVisible(quality);
    await tester.pump();
    await tester.tap(quality);
    await tester.pump(const Duration(milliseconds: 300));

    final compact = find.text('Gecomprimeerd');
    expect(compact, findsWidgets, reason: 'de compacte keuze staat er niet');
    await tester.tap(compact.first);
    await tester.pump(const Duration(milliseconds: 100));

    final button = find.widgetWithText(OutlinedButton, 'PDF (plaatje per dia)');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);

    await runExport(tester);

    expect(failureTextIn(tester), isNull);
    final produced = pdfsIn(tmp);
    expect(produced, hasLength(1));
    expect(
      produced.single.path,
      contains('-compact'),
      reason: 'de compacte export hoort zijn eigen naam te dragen',
    );
  });
}
