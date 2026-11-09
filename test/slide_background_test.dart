import 'dart:convert';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/slide_background_editor.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'slide_fixtures.dart';

void main() {
  for (final type in SlideType.values) {
    test(
      '$type background survives markdown independently of content images',
      () {
        final slide = slideMetInhoud(type).copyWith(
          marpStyle: const MarpStyle(
            backgroundImage: 'url("images/background.png")',
          ),
        );
        final service = MarkdownService();
        final result = service
            .parseDeck(
              service.generateDeck(Deck(title: 'Test', slides: [slide])),
            )!
            .slides
            .single;
        expect(
          result.marpStyle.backgroundImage,
          slide.marpStyle.backgroundImage,
        );
        expect(result.imagePath, slide.imagePath);
        expect(result.imagePath2, slide.imagePath2);
      },
    );

    testWidgets('$type exposes independent background selection', (
      tester,
    ) async {
      var slide = slideMetInhoud(type);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SlideBackgroundEditor(
                slide: slide,
                onUpdate: (value) => slide = value,
              ),
            ),
          ),
        ),
      );
      final picker = tester.widget<ImagePickerBar>(find.byType(ImagePickerBar));
      picker.onPicked('images/background.png', '');
      expect(
        marpBackgroundAssetPath(slide.marpStyle.backgroundImage),
        'images/background.png',
      );
      expect(slide.imagePath, slideMetInhoud(type).imagePath);
      expect(slide.imagePath2, slideMetInhoud(type).imagePath2);
      final selected = slide;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SlideBackgroundEditor(
                slide: selected,
                onUpdate: (value) => slide = value,
              ),
            ),
          ),
        ),
      );
      tester.widget<ImagePickerBar>(find.byType(ImagePickerBar)).onClear!();
      expect(slide.marpStyle.backgroundImage, 'none');
      expect(
        slide.marpStyle
            .inherit(const MarpStyle(backgroundImage: 'url("deck.png")'))
            .backgroundImage,
        'none',
      );
    });

    testWidgets('$type leaves the background visible at the canvas edge', (
      tester,
    ) async {
      final path = WebAssetStore.put(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEUlEQVR4nGP4wLAAjhiI4wAAj1IZAeWg4cwAAAAASUVORK5CYII=',
        ),
        name: 'background.png',
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
                    slide: slideMetInhoud(type).copyWith(
                      imagePath: '',
                      imagePath2: '',
                      showLogo: false,
                      marpStyle: MarpStyle(backgroundImage: 'url("$path")'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage());
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      image!.dispose();
      final offset = (2 * 640 + 2) * 4;
      expect(data!.buffer.asUint8List().sublist(offset, offset + 3), [
        240,
        0,
        160,
      ]);
      expect(tester.takeException(), isNull);
    });
  }
}
