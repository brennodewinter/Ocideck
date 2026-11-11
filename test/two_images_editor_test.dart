import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/two_images_editor.dart';

/// Behaviour tests for the `twoImages` slide editor: it renders a left and a
/// right image picker plus a shared subtitle, and edits the subtitle into the
/// slide title.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is EditorField && w.label == label),
    matching: find.byType(TextField),
  );

  Future<Slide? Function()> pump(WidgetTester tester, Slide slide) async {
    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TwoImagesEditor(slide: slide, onUpdate: (s) => updated = s),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  testWidgets('renders a left and right image section', (tester) async {
    await pump(tester, Slide.create(SlideType.twoImages));

    expect(fieldByLabel('Ondertitel (optioneel)'), findsOneWidget);
    expect(find.text('Linker afbeelding'), findsOneWidget);
    expect(find.text('Rechter afbeelding'), findsOneWidget);
  });

  testWidgets('editing the subtitle emits it as the slide title', (
    tester,
  ) async {
    final latest = await pump(tester, Slide.create(SlideType.twoImages));

    await tester.enterText(
      fieldByLabel('Ondertitel (optioneel)'),
      'Voor en na',
    );
    await tester.pump();

    expect(latest()!.title, 'Voor en na');
  });

  // #2867 — één weergavekeuze met drie standen: eigen verdeling (contain),
  // gelijke hoogte en panelen vullen (cover). De handmatige waarden worden
  // nooit overschreven, dus terugschakelen herstelt de compositie.
  group('view mode (#2867)', () {
    Slide slide([
      TwoImagesLayout layout = TwoImagesLayout.panels,
      int zoom = 0,
    ]) => Slide.create(SlideType.twoImages).copyWith(
      imagePath: 'images/a.png',
      imagePath2: 'images/b.png',
      imageSize: 60,
      imageZoom: zoom,
      twoImagesLayout: layout,
    );

    testWidgets(
      'selecting Gelijke hoogte sets the layout and keeps the split',
      (tester) async {
        final latest = await pump(tester, slide());

        await tester.tap(find.text('Gelijke hoogte'));
        await tester.pump();

        final out = latest()!;
        expect(out.twoImagesLayout, TwoImagesLayout.equalHeight);
        expect(out.imageSize, 60);
        expect(out.imageZoom, 0);
      },
    );

    testWidgets('equal height hides the split slider and disables crop', (
      tester,
    ) async {
      await pump(tester, slide(TwoImagesLayout.equalHeight));

      expect(find.text('Verdeling (links / rechts)'), findsNothing);
      final crop = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Afbeelding aanpassen').first,
      );
      expect(crop.onPressed, isNull);
    });

    testWidgets('back to Eigen verdeling restores contain with the split', (
      tester,
    ) async {
      final latest = await pump(tester, slide(TwoImagesLayout.equalHeight));

      await tester.tap(find.text('Eigen verdeling'));
      await tester.pump();

      final out = latest()!;
      expect(out.twoImagesLayout, TwoImagesLayout.panels);
      expect(out.imageSize, 60);
      // imageZoom 0 was cover — passen betekent contain.
      expect(out.imageZoom, 100);
    });

    testWidgets('Panelen vullen selects cover without touching the split', (
      tester,
    ) async {
      final latest = await pump(tester, slide(TwoImagesLayout.panels, 100));

      await tester.tap(find.text('Panelen vullen'));
      await tester.pump();

      final out = latest()!;
      expect(out.twoImagesLayout, TwoImagesLayout.panels);
      expect(out.imageZoom, 0);
      expect(out.imageSize, 60);
    });
  });
}
