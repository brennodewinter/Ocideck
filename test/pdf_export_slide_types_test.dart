import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
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
/// Op 640 px en niet op de 1920 die de app gebruikt, en dat is een echte
/// beperking van deze toets: onder de testbinding loopt het capturen op echte
/// tijd terwijl `pump` op nep-tijd loopt, en op exportresolutie wordt die lus
/// niet meer klaar (gemeten: "did not complete"). Wat hier dus bewaakt wordt is
/// dat elk diatype door de héle keten past — renderen, de PDF opbouwen,
/// wegschrijven — niet dat het op exportresolutie past.
Future<List<Uint8List>> _rasterize(WidgetTester tester, Deck deck) async {
  final context = await _hostContext(tester);
  final audience = PrivacyProjection.forAudience(deck);

  List<Uint8List>? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      SlideRasterizer.rasterize(
        context: context,
        audience: audience,
        targetWidth: 640,
      ).then(
        (value) => result = value,
        onError: (Object error) => failure = error,
      ),
    );
    for (var i = 0; i < 900 && result == null && failure == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });

  if (failure != null) fail('rasterize wierp: $failure');
  expect(result, isNotNull, reason: 'rasterize werd niet klaar binnen de lus');
  return result!;
}

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
