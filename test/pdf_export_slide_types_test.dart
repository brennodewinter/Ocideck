import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/findings_summary_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/slide_rasterizer.dart';
import 'package:path/path.dart' as p;

/// De weg die een echte PDF-export loopt: elk diatype renderen zoals de app het
/// rendert, en die bytes door [ExportService] duwen.
///
/// De bestaande exporttests voeren een zelfgemaakte PNG in. Die vangen wat er
/// mis kan gaan ná het renderen, maar niet wat één specifiek diatype aan
/// beeldbytes oplevert — en dat is precies waar #714 zat: "Invalid argument(s):
/// 1", reproduceerbaar op een deck met bevindings-, checklist-, scopematrix- en
/// bevindingenoverzichtdia's, terwijl de HTML-export van hetzelfde deck lukte.
Future<BuildContext> _hostContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return captured;
}

/// Draait `rasterize` en pompt ondertussen frames — zie
/// slide_rasterizer_test.dart voor waarom beide nodig zijn.
///
/// De per-type-toetsen draaien op 640 px omdat ze over dékking gaan (past elk
/// type door de keten) en 24 types op exportresolutie de poort onnodig traag
/// maken. De echte exportbreedtes staan apart getoetst, onderaan.
///
/// *Gecorrigeerd 23-07-2026.* Hier stond dat capturen op exportresolutie onder
/// de testbinding "niet meer klaar wordt (gemeten: did not complete)". Dat
/// klopt niet: de lus liep leeg omdat er per ronde maar 1 ms échte tijd
/// voorbijging terwijl het capturen op echte tijd loopt. Met een ruimer
/// tijdsbudget haalt 1920 px het ruim — 41 dia's in acht seconden. Die
/// onterechte beperking stond in de weg bij #714, want ze zette juist de
/// resolutie buiten beeld als verdachte.
Future<List<Uint8List>> _rasterize(
  WidgetTester tester,
  Deck deck, {
  int targetWidth = 640,
}) async {
  final context = await _hostContext(tester);
  final audience = PrivacyProjection.forAudience(deck);

  List<Uint8List>? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      SlideRasterizer.rasterize(
        context: context,
        audience: audience,
        targetWidth: targetWidth,
      ).then(
        (value) => result = value,
        onError: (Object error) => failure = error,
      ),
    );
    for (var i = 0; i < 3000 && result == null && failure == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });

  if (failure != null) fail('rasterize wierp: $failure');
  expect(result, isNotNull, reason: 'rasterize werd niet klaar binnen de lus');
  return result!;
}

/// De drie tabelgedreven types uit de melding, met échte rijen erin.
Slide _populatedChecklist() {
  const spec = ChecklistSpec(
    standardLabel: 'Checklist — OWASP WSTG',
    rows: [
      ChecklistRow(
        id: 'WSTG-CONF-01',
        test: 'Netwerkinfrastructuurconfiguratie',
        status: ChecklistStatus.tested,
        note: 'Geen afwijkingen',
      ),
      ChecklistRow(
        id: 'WSTG-CRYP-01',
        test: 'Zwakke TLS-configuratie',
        status: ChecklistStatus.anomaly,
        findingId: 'F-001',
        note: 'TLS 1.0 geaccepteerd',
      ),
      ChecklistRow(id: 'WSTG-ATHN-02', test: 'Standaardwachtwoorden'),
    ],
  );
  return Slide.create(SlideType.checklist).copyWith(
    title: spec.standardLabel,
    tableRows: spec.toTableRows(),
    // De voortgangsgrafiek is het enige stuk van deze dia dat níét een tabel
    // is; zonder deze vlag tekent de toets hem nooit.
    showChecklistProgress: true,
  );
}

Slide _populatedScopeMatrix() {
  const spec = ScopeMatrixSpec(
    title: 'Scope',
    rows: [
      ScopeRow(
        object: 'portal.example.nl',
        status: ScopeStatus.tested,
        note: 'Volledig getest',
      ),
      ScopeRow(object: 'api.example.nl', status: ScopeStatus.deviation),
      ScopeRow(object: 'vpn.example.nl'),
    ],
  );
  return Slide.create(
    SlideType.scopeMatrix,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

Slide _populatedFindingsSummary() {
  const spec = FindingsSummarySpec(
    title: 'Bevindingen',
    counts: {
      Cvss4Severity.critical: 1,
      Cvss4Severity.high: 3,
      Cvss4Severity.medium: 5,
      Cvss4Severity.low: 2,
    },
    resolved: 4,
  );
  return Slide.create(
    SlideType.findingsSummary,
  ).copyWith(title: spec.title, tableRows: spec.toTableRows());
}

Slide _populatedFinding() => Slide.create(SlideType.finding).copyWith(
  title: 'Verouderde TLS-configuratie',
  bullets: const [
    'De portal accepteert TLS 1.0 en 1.1.',
    'Een aanvaller op het pad kan de verbinding downgraden.',
  ],
);

Slide _slideFor(SlideType type) => switch (type) {
  SlideType.finding => Slide.create(type).copyWith(
    title: 'Verouderde TLS-configuratie',
    bullets: const ['De portal accepteert TLS 1.0.'],
  ),
  SlideType.findingsSummary => Slide.create(
    type,
  ).copyWith(title: 'Bevindingen'),
  SlideType.checklist => Slide.create(type).copyWith(title: 'Checklist'),
  SlideType.scopeMatrix => Slide.create(type).copyWith(title: 'Scope'),
  SlideType.signOff => Slide.create(type).copyWith(title: 'Akkoord'),
  _ => Slide.create(type).copyWith(title: type.name),
};

void main() {
  late Directory tmp;
  late ExportService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ocideck_pdf_types');
    service = ExportService();
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // Het deck uit de melding, met de vier genoemde types bij elkaar.
  testWidgets('het gemelde deck exporteert naar PDF (#714)', (tester) async {
    final deck = Deck(
      title: 'Pentestrapport',
      slides: [
        Slide.create(SlideType.title).copyWith(title: 'Beveiligingsonderzoek'),
        _slideFor(SlideType.finding),
        _slideFor(SlideType.checklist),
        _slideFor(SlideType.scopeMatrix),
        _slideFor(SlideType.findingsSummary),
      ],
    );
    final images = await _rasterize(tester, deck);
    expect(images, hasLength(deck.slides.length));

    ExportResult? result;
    await tester.runAsync(() async {
      result = await service.export(
        p.join(tmp.path, 'deck.md'),
        ExportFormat.pdf,
        images,
      );
    });
    expect(
      result!.error,
      isNull,
      reason: 'PDF-export mislukte: ${result!.error}',
    );
    expect(File(result!.outputPath!).lengthSync(), greaterThan(0));
  });

  // De twee combinaties die de app zelf gebruikt, met gevúlde dia's.
  //
  // `Slide.create` levert de lege startrijen op — een checklist zonder tests,
  // een scopematrix zonder objecten, een bevindingenoverzicht op nul. Dat is
  // niet het deck uit de melding, en het is precies de inhoud die de tabellen
  // en de voortgangsgrafiek laat tekenen. Daarnaast is `compress` een knop in
  // de exportdialoog die de bytes door een héél ander pad stuurt (PNG →
  // decode → resize → JPEG) en die alleen PDF kent — het enige formaat dat in
  // #714 omviel, terwijl HTML op hetzelfde deck lukte.
  for (final mode in const [
    (label: 'onbewerkt op 1920', width: 1920, compress: false),
    (label: 'gecomprimeerd op 1280', width: 1280, compress: true),
  ]) {
    testWidgets('het gemelde deck, gevuld, ${mode.label}', (tester) async {
      final deck = Deck(
        title: 'Pentestrapport',
        organization: 'Voorbeeld BV',
        tlp: TlpLevel.amber,
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'Onderzoek'),
          _populatedFinding(),
          _populatedChecklist(),
          _populatedScopeMatrix(),
          _populatedFindingsSummary(),
        ],
      );
      final images = await _rasterize(tester, deck, targetWidth: mode.width);
      expect(images, hasLength(deck.slides.length));

      ExportResult? result;
      await tester.runAsync(() async {
        result = await service.export(
          p.join(tmp.path, 'deck.md'),
          ExportFormat.pdf,
          images,
          compress: mode.compress,
        );
      });
      expect(
        result!.error,
        isNull,
        reason: 'PDF (${mode.label}) mislukte: ${result!.error}',
      );
      expect(File(result!.outputPath!).lengthSync(), greaterThan(0));
    });
  }

  // En per type apart, zodat een rode test meteen zegt wélk type het is in
  // plaats van "de export is stuk".
  for (final type in SlideType.values) {
    testWidgets('een deck met alleen ${type.name} exporteert naar PDF', (
      tester,
    ) async {
      final deck = Deck(title: 'Rapport', slides: [_slideFor(type)]);
      final images = await _rasterize(tester, deck);

      ExportResult? result;
      await tester.runAsync(() async {
        result = await service.export(
          p.join(tmp.path, 'deck.md'),
          ExportFormat.pdf,
          images,
        );
      });
      expect(
        result!.error,
        isNull,
        reason: '${type.name} liet de PDF-export vallen: ${result!.error}',
      );
    });
  }
}
