import 'dart:convert';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/title_contrast.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/section_editor.dart';
import 'package:ocideck/widgets/editors/title_editor.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'support/pump_until.dart';

const _profile = ThemeProfile(
  titleBackgroundColor: '#000000',
  sectionBackgroundColor: '#000000',
  titleTextColor: '#FFFFFF',
);

Widget _editorHost(Slide slide, ValueChanged<Slide> update) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: slide.type == SlideType.title
          ? TitleEditor(slide: slide, onUpdate: update)
          : SectionEditor(slide: slide, onUpdate: update),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });
  for (final (type, initial) in [
    (SlideType.title, 95),
    (SlideType.section, 62),
  ]) {
    testWidgets('$type reuses the slider with its own default', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var slide = Slide.create(
        type,
      ).copyWith(imagePath: 'bg.png', imageSize: 0);
      await tester.pumpWidget(_editorHost(slide, (s) => slide = s));
      await tester.pumpAndSettle();
      expect(find.byType(ImageOverlayStrengthControl), findsOneWidget);
      Finder slider() => find.descendant(
        of: find.byType(ImageOverlayStrengthControl),
        matching: find.byType(Slider),
      );
      expect(tester.widget<Slider>(slider()).value, initial);
      tester.widget<Slider>(slider()).onChanged!(25);
      expect(imageOverlayStrengthFor(slide), 25);
      expect(slide.imagePath, 'bg.png');
      slide = slide.copyWith(titleImageOverlay: false);
      await tester.pumpWidget(_editorHost(slide, (s) => slide = s));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider()).onChanged, isNull);
      expect(tester.widget<Slider>(slider()).value, 25);
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Grijze waas over afbeelding'),
      );
      expect(slide.titleImageOverlay, isTrue);
      expect(imageOverlayStrengthFor(slide), 25);
      await tester.pumpWidget(
        _editorHost(slide.copyWith(imagePath: ''), (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImageOverlayStrengthControl), findsNothing);
    });

    test('$type old files retain their default and Marp opacity', () {
      final service = MarkdownService();
      final slide = Slide.create(
        type,
      ).copyWith(title: 'Kop', imagePath: 'bg.png');
      final markdown = service.generateDeck(
        Deck(title: 'Test', slides: [slide]),
      );
      expect(markdown, contains('opacity:.45'));
      expect(markdown, isNot(contains('image_overlay_strength:')));
      final parsed = service.parseDeck(markdown)!.slides.single;
      expect(parsed.type, type);
      expect(imageOverlayStrengthFor(parsed), initial);
    });

    test('$type malformed and bounded strengths use the shared parser', () {
      final service = MarkdownService();
      final source = service.generateDeck(
        Deck(
          title: 'Test',
          slides: [
            Slide.create(type).copyWith(title: 'Kop', imagePath: 'bg.png'),
          ],
        ),
      );
      for (final (raw, expected) in [
        ('bad', initial),
        ('"25"', 25),
        ('-1', 0),
        ('999', 100),
      ]) {
        final modified = source.replaceFirst(
          '# Kop',
          '<!-- ocideck_image_overlay_strength: $raw -->\n# Kop',
        );
        final slide = service.parseDeck(modified)!.slides.single;
        expect(slide.type, type);
        expect(imageOverlayStrengthFor(slide), expected);
      }
    });

    for (final strength in [0, 25, 52, 62, 95, 100]) {
      for (final enabled in [true, false]) {
        test('$type $strength enabled=$enabled survives repeated saving', () {
          final service = MarkdownService();
          var slide = Slide.create(type).copyWith(
            title: 'Kop',
            subtitle: 'Uitleg',
            imagePath: 'bg.png',
            titleImageOverlay: enabled,
            marpStyle: MarpStyle(imageOverlayStrength: strength),
          );
          for (var pass = 0; pass < 2; pass++) {
            final markdown = service.generateDeck(
              Deck(title: 'Test', slides: [slide]),
            );
            expect(
              markdown.contains('ocideck_image_overlay_strength:'),
              strength != initial,
            );
            expect(markdown.contains('opacity:'), enabled);
            if (enabled) {
              expect(
                markdown,
                contains(
                  'opacity:${strength == initial ? '.45' : ((100 - strength) / 100).toStringAsFixed(2)}',
                ),
              );
            }
            slide = service.parseDeck(markdown)!.slides.single;
            expect(slide.type, type);
            expect(imageOverlayStrengthFor(slide), strength);
            expect(slide.titleImageOverlay, enabled);
            expect(slide.notes, isEmpty);
          }
        });
      }
    }

    for (final strength in [null, 0, 25, 100]) {
      testWidgets('$type pixels reflect strength $strength', (tester) async {
        final path = WebAssetStore.put(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEUlEQVR4nGP4wLAAjhiI4wAAj1IZAeWg4cwAAAAASUVORK5CYII=',
          ),
          name: 'heading.png',
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
                      themeProfile: _profile,
                      slide: Slide.create(type).copyWith(
                        imagePath: path,
                        imageSize: 0,
                        showLogo: false,
                        showFooter: false,
                        marpStyle: MarpStyle(imageOverlayStrength: strength),
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
              .any((w) => w.image != null),
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await tester.runAsync(() => boundary.toImage());
        final data = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        image!.dispose();
        final bytes = data!.buffer.asUint8List();
        final actual = strength ?? initial;
        final bottom = (358 * 640 + 2) * 4;
        expect(bytes[bottom], closeTo(240 * (1 - actual / 100), 2));
        final top = (2 * 640 + 2) * 4;
        expect(
          bytes[top],
          closeTo(type == SlideType.title ? 240 : 240 * (1 - actual / 100), 2),
        );
        if (type == SlideType.title && strength == null) {
          final gradients = tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .map((w) => w.decoration)
              .whereType<BoxDecoration>()
              .map((d) => d.gradient)
              .whereType<LinearGradient>();
          expect(
            gradients.any(
              (g) =>
                  g.stops!.join(',') == '0.0,0.45,0.8' &&
                  (g.colors[0].a - 0.95).abs() < 0.001 &&
                  (g.colors[1].a - 0.90).abs() < 0.001,
            ),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    test('$type contrast follows strength and preserves its default', () {
      final slide = Slide.create(
        type,
      ).copyWith(title: 'Kop', imagePath: 'bg.png');
      double ratio(Slide value) => evaluateTitleContrast(
        avgImage: Colors.white,
        theme: _profile,
        slide: value,
      ).ratio;
      expect(
        ratio(slide),
        closeTo(
          ratio(
            slide.copyWith(marpStyle: MarpStyle(imageOverlayStrength: initial)),
          ),
          1e-10,
        ),
      );
      final zero = slide.copyWith(
        marpStyle: const MarpStyle(imageOverlayStrength: 0),
      );
      final full = slide.copyWith(
        marpStyle: const MarpStyle(imageOverlayStrength: 100),
      );
      expect(
        ratio(zero),
        closeTo(ratio(slide.copyWith(titleImageOverlay: false)), 1e-10),
      );
      expect(ratio(full), greaterThan(ratio(slide)));
    });
  }
}
