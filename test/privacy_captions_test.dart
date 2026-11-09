import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/asset_text_reader.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// #2841 — een ondertitelbestand is inhoud: namen en adressen daarin tellen
/// net zo mee als in de sprekersnotities. Het pad zelf wordt altijd gescand;
/// de inhoud alleen waar de scanner een lezer heeft.
void main() {
  final withReader = PrivacyScanner(
    assetTextReader: (path) => 'Spreker: Jan Jansen, jan@klant.nl',
  );

  test('de inhoud van het ondertitelbestand telt mee als bevinding', () {
    final result = withReader.scan(
      Deck(
        title: 'Deck',
        slides: [
          Slide.create(SlideType.video).copyWith(
            videoPath: 'media/film.mp4',
            videoCaptions: 'media/film.vtt',
          ),
        ],
      ),
    );
    expect(
      result.findings.where((f) => f.field == 'videoCaptions'),
      isNotEmpty,
      reason: 'pad én tekst uit het .vtt-bestand horen gescand te worden',
    );
  });

  test('zonder lezer wordt alleen het pad gescand, niet de inhoud', () {
    const scanner = PrivacyScanner();
    final result = scanner.scan(
      Deck(
        title: 'Deck',
        slides: [
          Slide.create(SlideType.video).copyWith(
            videoPath: 'media/film.mp4',
            videoCaptions: 'media/film.vtt',
          ),
        ],
      ),
    );
    expect(result.findings.where((f) => f.field == 'videoCaptions'), isEmpty);
  });

  group('readSlideAssetText', () {
    test('leest een mem:-asset terug als tekst', () {
      final mem = WebAssetStore.put(
        utf8.encode('WEBVTT\n\n00:00.000 --> 00:02.000\nHallo wereld'),
        name: 'film.vtt',
      );
      expect(readSlideAssetText(mem), contains('Hallo wereld'));
    });

    test('een pad buiten het project levert niets op', () {
      expect(
        readSlideAssetText('../../etc/passwd', projectPath: '/tmp/x'),
        isNull,
      );
      expect(readSlideAssetText('/etc/passwd', projectPath: '/tmp/x'), isNull);
    });

    test('een leeg pad levert niets op', () {
      expect(readSlideAssetText(''), isNull);
    });
  });
}
