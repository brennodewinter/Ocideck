import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/slide_format.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/latex/latex_preamble.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/odp/deck_odp_export.dart';
import 'package:ocideck/services/pptx/deck_pptx_export.dart';

/// Het diaformaat (#2433) deelt zijn vocabulaire met de documentpagina:
/// `papersize:` voor een staand ISO-vel, `geometry:` met alleen het vel voor
/// een liggend. De rode lijnen: een deck zónder aanduiding blijft 16:9, en een
/// handgeschreven Pandoc-`geometry` met marges is niet van ons en mag noch
/// gelezen noch overschreven worden.
void main() {
  final svc = MarkdownService();

  const body = '\n# Titel\n\n- punt\n';

  group('lezen', () {
    test('een deck zonder aanduiding heeft geen papierformaat', () {
      final deck = svc.parseDeck('---\ntheme: default\n---\n$body');
      expect(deck, isNotNull);
      expect(deck!.slideSize, isNull);
      expect(slideAspectRatio(deck.slideSize), kScreenSlideAspect);
    });

    test('papersize: a4 leest het staande vel', () {
      final deck = svc.parseDeck(
        '---\ntheme: default\npapersize: a4\n---\n$body',
      );
      expect(deck!.slideSize, PageSizeSpec.a4);
      expect(slideAspectRatio(deck.slideSize), closeTo(210 / 297, 1e-9));
    });

    test('geometry met alleen het vel leest het liggende vel', () {
      final deck = svc.parseDeck(
        '---\ntheme: default\n'
        'geometry: paperwidth=297mm,paperheight=210mm\n---\n$body',
      );
      expect(deck!.slideSize, PageSizeSpec.a4Landscape);
    });

    test('een geometry met marges is van de auteur, niet van het deck', () {
      const fm =
          'geometry: paperwidth=210mm,paperheight=297mm,'
          'top=30mm,bottom=30mm,left=15mm,right=15mm';
      final deck = svc.parseDeck('---\ntheme: default\n$fm\n---\n$body');
      // Géén diaformaat — en de regel overleeft een round-trip ongewijzigd.
      expect(deck!.slideSize, isNull);
      final out = svc.generateDeck(deck);
      expect(out, contains(fm));
    });
  });

  group('schrijven en teruglezen', () {
    test('staand schrijft papersize, liggend schrijft geometry', () {
      final portrait = svc
          .parseDeck('---\ntheme: default\n---\n$body')!
          .copyWith(slideSize: PageSizeSpec.a4);
      expect(svc.generateDeck(portrait), contains('papersize: a4'));

      final landscape = svc
          .parseDeck('---\ntheme: default\n---\n$body')!
          .copyWith(slideSize: PageSizeSpec.a4Landscape);
      final out = svc.generateDeck(landscape);
      expect(out, contains('geometry: paperwidth=297mm,paperheight=210mm'));
      // Een `papersize: a4` erbij zou bij Pandoc staand betekenen — die liegen
      // we niet.
      expect(out, isNot(contains('papersize')));
    });

    test('round-trip bewaart het gekozen formaat', () {
      for (final spec in [
        PageSizeSpec.a4,
        PageSizeSpec.a4Landscape,
        const PageSizeSpec(series: PaperSeries.b, number: 5, landscape: true),
      ]) {
        final deck = svc
            .parseDeck('---\ntheme: default\n---\n$body')!
            .copyWith(slideSize: spec);
        final again = svc.parseDeck(svc.generateDeck(deck));
        expect(again!.slideSize, spec, reason: 'formaat ${spec.id}');
      }
    });

    test('de schermstandaard schrijft niets', () {
      final deck = svc.parseDeck('---\ntheme: default\n---\n$body')!;
      final out = svc.generateDeck(deck);
      expect(out, isNot(contains('papersize')));
      expect(out, isNot(contains('geometry')));
    });

    test('terug naar scherm wist de sleutel uit het bestand', () {
      final deck = svc.parseDeck(
        '---\ntheme: default\npapersize: a4\n---\n$body',
      )!;
      expect(deck.slideSize, PageSizeSpec.a4);
      final cleared = deck.copyWith(clearSlideSize: true);
      final out = svc.generateDeck(cleared);
      expect(out, isNot(contains('papersize')));
      expect(svc.parseDeck(out)!.slideSize, isNull);
    });
  });

  group('exports dragen het formaat', () {
    final images = [
      Uint8List.fromList(const [1, 2, 3]),
    ];
    const meta = ExportDocumentMetadata();

    String zipEntry(Uint8List bytes, String name) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final file = archive.files.firstWhere((f) => f.name == name);
      return String.fromCharCodes(file.content as List<int>);
    }

    test('PPTX zet sldSz op de verhouding van het deck', () {
      final portrait = buildDeckExportPptx(
        images,
        metadata: meta,
        fallbackTitle: 'deck',
        slideAspect: slideAspectRatio(PageSizeSpec.a4),
      );
      final xml = zipEntry(portrait, 'ppt/presentation.xml');
      // A4 staand — en geen screen16x9-aanduiding meer.
      expect(xml, isNot(contains('type="screen16x9"')));
      final cy = RegExp(
        r'<p:sldSz cx="(\d+)" cy="(\d+)"',
      ).firstMatch(xml)!.group(2)!;
      expect(int.parse(cy), closeTo((12192000 / (210 / 297)).round(), 1));

      final screen = buildDeckExportPptx(
        images,
        metadata: meta,
        fallbackTitle: 'deck',
      );
      expect(
        zipEntry(screen, 'ppt/presentation.xml'),
        contains('type="screen16x9"'),
      );
    });

    test('ODP schrijft de framehoogte uit de verhouding', () {
      final portrait = buildDeckExportOdp(
        images: images,
        metadata: meta,
        fallbackTitle: 'deck',
        slideAspect: slideAspectRatio(PageSizeSpec.a4),
      );
      final expected = odpSlideHeightCm(slideAspectRatio(PageSizeSpec.a4));
      expect(
        zipEntry(portrait, 'content.xml'),
        contains('svg:height="${expected}cm"'),
      );
    });

    test('beamer gebruikt geometry bij papier, aspectratio bij scherm', () {
      expect(
        beamerPreamble(meta),
        contains(r'\documentclass[aspectratio=169]{beamer}'),
      );
      final paper = beamerPreamble(meta, slideSize: PageSizeSpec.a4);
      expect(paper, isNot(contains('aspectratio')));
      expect(paper, contains(r'\geometry{paperwidth=210mm,paperheight=297mm}'));
    });
  });

  group('verhouding', () {
    test('paper volgt het vel, scherm is 16:9', () {
      expect(slideAspectRatio(null), kScreenSlideAspect);
      expect(
        slideAspectRatio(PageSizeSpec.a4Landscape),
        closeTo(297 / 210, 1e-9),
      );
      expect(
        slideAspectRatio(const PageSizeSpec(series: PaperSeries.a, number: 0)),
        lessThan(1),
      );
    });
  });
}
