// Tests for the callout clip check — #1853: een doel buiten de zichtbare band
// moet een calloutTargetOutOfView quality finding opleveren.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('callout_clip_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Schrijf een vierkante PNG (100×100) naar schijf en geef het pad terug.
  String writeSquarePng() {
    final png = _minimalPng(100, 100);
    final file = File('${tmp.path}/square.png')..writeAsBytesSync(png);
    return file.path;
  }

  /// Schrijf een brede PNG (400×100) naar schijf en geef het pad terug.
  String writeWidePng() {
    final png = _minimalPng(400, 100);
    final file = File('${tmp.path}/wide.png')..writeAsBytesSync(png);
    return file.path;
  }

  final analyzer = const SlideQualityAnalyzer();

  test('een doel buiten de zichtbare band geeft calloutTargetOutOfView', () {
    // Brede afbeelding (400×100, aspect 4:1) in een slot met aspect
    // 0.40*16/9 ≈ 0.71. Cover schaalt op slot-hoogte, dus de zichtbare band
    // in x is ongeveer 0.36..0.64. Een doel op x=0.05 valt erbuiten.
    final path = writeWidePng();
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      imagePath: path,
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.05, 0.5)],
          description: 'links',
        ),
      ],
    );
    final deck = Deck(title: 'test', slides: [slide]);
    final result = analyzer.analyze(deck);
    final clipIssues = result.issues
        .where((i) => i.kind == SlideQualityIssueKind.calloutTargetOutOfView)
        .toList();
    expect(clipIssues, hasLength(1));
    expect(clipIssues.first.args['ref'], '(A)');
  });

  test('een doel binnen de zichtbare band geeft geen finding', () {
    // Vierkante afbeelding (100×100, aspect 1:1) in een slot met aspect
    // 0.71. Cover schaalt op slot-breedte (want 1 > 0.71), dus de volledige
    // breedte is zichtbaar en een deel van de hoogte wordt afgesneden.
    // Een doel in het midden is altijd zichtbaar.
    final path = writeSquarePng();
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      imagePath: path,
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.5, 0.5)],
          description: 'midden',
        ),
      ],
    );
    final deck = Deck(title: 'test', slides: [slide]);
    final result = analyzer.analyze(deck);
    final clipIssues = result.issues
        .where((i) => i.kind == SlideQualityIssueKind.calloutTargetOutOfView)
        .toList();
    expect(clipIssues, isEmpty);
  });

  test('een gebied dat deels buiten beeld valt geeft een finding', () {
    // Brede afbeelding, gebied dat voorbij de rechterrand reikt.
    final path = writeWidePng();
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      imagePath: path,
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutRegion(0.0, 0.3, 0.9, 0.4)],
          description: 'breed gebied',
        ),
      ],
    );
    final deck = Deck(title: 'test', slides: [slide]);
    final result = analyzer.analyze(deck);
    final clipIssues = result.issues
        .where((i) => i.kind == SlideQualityIssueKind.calloutTargetOutOfView)
        .toList();
    expect(clipIssues, hasLength(1));
  });

  test('geen finding als het beeld ontbreekt', () {
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.05, 0.5)],
          description: 'links',
        ),
      ],
    );
    final deck = Deck(title: 'test', slides: [slide]);
    final result = analyzer.analyze(deck);
    final clipIssues = result.issues
        .where((i) => i.kind == SlideQualityIssueKind.calloutTargetOutOfView)
        .toList();
    expect(clipIssues, isEmpty);
  });

  test('één finding per reference, ook bij meerdere clipped targets', () {
    final path = writeWidePng();
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      imagePath: path,
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.05, 0.5), CalloutPoint(0.95, 0.5)],
          description: 'twee doelen',
        ),
      ],
    );
    final deck = Deck(title: 'test', slides: [slide]);
    final result = analyzer.analyze(deck);
    final clipIssues = result.issues
        .where((i) => i.kind == SlideQualityIssueKind.calloutTargetOutOfView)
        .toList();
    expect(clipIssues, hasLength(1), reason: 'één finding per reference');
  });

  test('zoom houdt rekening met de zichtbare band', () {
    // Vierkant beeld, zoom 200% (zichtbare band is smaller). Een doel
    // bij de rand kan door zoom buiten beeld raken.
    final path = writeSquarePng();
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      imagePath: path,
      imageZoom: 200,
      imageFocalX: 0.5,
      imageFocalY: 0.5,
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.01, 0.5)],
          description: 'rand',
        ),
      ],
    );
    final deck = Deck(title: 'test', slides: [slide]);
    final result = analyzer.analyze(deck);
    final clipIssues = result.issues
        .where((i) => i.kind == SlideQualityIssueKind.calloutTargetOutOfView)
        .toList();
    expect(clipIssues, hasLength(1));
  });
}

/// Bouw een minimale geldige PNG met de gegeven afmetingen.
Uint8List _minimalPng(int width, int height) {
  // PNG signature + IHDR chunk (genoeg voor de dimensie-lezer).
  final bytes = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    0x00, 0x00, 0x00, 0x0D, // IHDR length = 13
    0x49, 0x48, 0x44, 0x52, // "IHDR"
    (width >> 24) & 0xFF,
    (width >> 16) & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    (height >> 24) & 0xFF,
    (height >> 16) & 0xFF,
    (height >> 8) & 0xFF,
    height & 0xFF,
    0x08, 0x02, 0x00, 0x00, 0x00, // bit depth 8, color type 2 (RGB)
  ];
  return Uint8List.fromList(bytes);
}
