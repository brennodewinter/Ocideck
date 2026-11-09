import 'dart:convert';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/collab/collab_codec.dart';
import 'package:ocideck/collab/collab_deck_diff.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'support/pump_until.dart';

void main() {
  for (final (overlay, strength) in [
    for (final strength in [0, 25, 52, 75, 100])
      for (final overlay in [true, false]) (overlay, strength),
  ]) {
    test(
      'quote veil $overlay at $strength survives saving and controls Marp opacity',
      () {
        final slide = Slide.create(SlideType.quote).copyWith(
          quote: 'Kennis is macht',
          imagePath: 'images/bg.png',
          titleImageOverlay: overlay,
          marpStyle: MarpStyle(imageOverlayStrength: strength),
        );
        final service = MarkdownService();
        final markdown = service.generateDeck(
          Deck(title: 'Test', slides: [slide]),
        );
        final opacity = strength == 52
            ? '.45'
            : ((100 - strength) / 100).toStringAsFixed(2);
        expect(markdown.contains('opacity:$opacity'), overlay);
        expect(
          markdown.contains('ocideck_quote_image_overlay_strength:'),
          strength != 52,
        );
        expect(
          markdown.contains('ocideck_title_image_overlay: false'),
          !overlay,
        );
        final result = service.parseDeck(markdown)!.slides.single;
        expect(result.titleImageOverlay, overlay);
        expect(result.type, SlideType.quote);
        expect(result.marpStyle.effectiveImageOverlayStrength, strength);
        final second = service
            .parseDeck(
              service.generateDeck(Deck(title: 'Test', slides: [result])),
            )!
            .slides
            .single;
        expect(second.marpStyle.effectiveImageOverlayStrength, strength);
        expect(second.type, SlideType.quote);
        expect(result.quote, slide.quote);
        expect(result.imagePath, slide.imagePath);
      },
    );

    testWidgets('quote veil $overlay at $strength changes the rendered image', (
      tester,
    ) async {
      final path = WebAssetStore.put(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEUlEQVR4nGP4wLAAjhiI4wAAj1IZAeWg4cwAAAAASUVORK5CYII=',
        ),
        name: 'quote.png',
      );
      addTearDown(() => WebAssetStore.retain(const {}));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 640,
                  height: 360,
                  child: SlidePreviewWidget(
                    slide: Slide.create(SlideType.quote).copyWith(
                      quote: 'Kennis is macht',
                      imagePath: path,
                      titleImageOverlay: overlay,
                      marpStyle: MarpStyle(imageOverlayStrength: strength),
                      imageSize: 0,
                      showLogo: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage());
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      image!.dispose();
      final bytes = data!.buffer.asUint8List();
      final offset = (2 * 640 + 2) * 4;
      final factor = overlay ? 1 - strength / 100 : 1.0;
      expect(bytes[offset], closeTo(240 * factor, 1));
      expect(bytes[offset + 1], 0);
      expect(bytes[offset + 2], closeTo(160 * factor, 1));
      expect(tester.takeException(), isNull);
    });
  }
  test(
    'strength is bounded and survives copy, duplication and collaboration',
    () {
      final slide = Slide.create(
        SlideType.quote,
      ).copyWith(marpStyle: const MarpStyle(imageOverlayStrength: 75));
      expect(
        slide.copyWith(quote: 'Anders').marpStyle.effectiveImageOverlayStrength,
        75,
      );
      expect(
        Slide.duplicate(slide).marpStyle.effectiveImageOverlayStrength,
        75,
      );
      expect(
        slideFromJson(
          slideToJson(slide),
        ).marpStyle.effectiveImageOverlayStrength,
        75,
      );
      expect(
        slide
            .copyWith(marpStyle: const MarpStyle(imageOverlayStrength: -5))
            .marpStyle
            .effectiveImageOverlayStrength,
        0,
      );
      expect(
        slide
            .copyWith(marpStyle: const MarpStyle(imageOverlayStrength: 200))
            .marpStyle
            .effectiveImageOverlayStrength,
        100,
      );
      final old = slideToJson(slide);
      old['marpStyle'] = const MarpStyle().toJson();
      expect(slideFromJson(old).marpStyle.effectiveImageOverlayStrength, 52);
      expect(
        () => slideFromJson({
          ...old,
          'marpStyle': {'imageOverlayStrength': 'bad'},
        }),
        throwsFormatException,
      );
    },
  );

  test('missing and malformed markdown strengths retain the old default', () {
    final service = MarkdownService();
    final slide = Slide.create(
      SlideType.quote,
    ).copyWith(quote: 'Citaat', imagePath: 'bg.png');
    final source = service.generateDeck(Deck(title: 'Test', slides: [slide]));
    expect(
      service
          .parseDeck(source)!
          .slides
          .single
          .marpStyle
          .effectiveImageOverlayStrength,
      52,
    );
    for (final (raw, expected) in [('bad', 52), ('-1', 0), ('999', 100)]) {
      final modified = source.replaceFirst(
        '> Citaat',
        '<!-- ocideck_quote_image_overlay_strength: $raw -->\n> Citaat',
      );
      expect(
        service
            .parseDeck(modified)!
            .slides
            .single
            .marpStyle
            .effectiveImageOverlayStrength,
        expected,
      );
    }
  });
  test('the existing style operation synchronises a strength edit', () {
    final slide = Slide.create(SlideType.quote);
    final before = Deck(title: 'Test', slides: [slide]);
    final after = before.copyWith(
      slides: [
        slide.copyWith(
          marpStyle: slide.marpStyle.copyWith(imageOverlayStrength: 75),
        ),
      ],
    );
    final ops = deckDiffToOps(before, after, authorId: 'test');
    expect(ops, hasLength(1));
    expect((ops.single as SetSlideField).field, SlideField.marpStyle);
    expect(
      applyOp(
        before,
        ops.single,
      ).slides.single.marpStyle.effectiveImageOverlayStrength,
      75,
    );
  });

  test('style equality, hashing and inheritance retain strength', () {
    const style = MarpStyle(imageOverlayStrength: 75);
    expect(style.isEmpty, isFalse);
    expect(style.copyWith(color: '#ffffff').effectiveImageOverlayStrength, 75);
    expect(const MarpStyle().inherit(style).effectiveImageOverlayStrength, 75);
    expect(
      const MarpStyle(
        imageOverlayStrength: 52,
      ).inherit(style).effectiveImageOverlayStrength,
      52,
    );
    expect(MarpStyle.fromJson(style.toJson()), style);
    expect(MarpStyle.fromJson(style.toJson()).hashCode, style.hashCode);
    expect(style, isNot(const MarpStyle()));
    expect(
      style.copyWith(imageOverlayStrength: -1).effectiveImageOverlayStrength,
      0,
    );
    expect(
      style.copyWith(imageOverlayStrength: 101).effectiveImageOverlayStrength,
      100,
    );
  });
}
