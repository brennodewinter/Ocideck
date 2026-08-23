import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/alt_text_field.dart';
import 'package:ocideck/widgets/editors/two_images_editor.dart';

/// Behaviour coverage for [TwoImagesEditor]: a shared subtitle plus a left and
/// a right image picker, each with its own WCAG alt-text field, and a split
/// slider governing the left/right widths.
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1200, height: 2600, child: child)),
  ),
);

void main() {
  setUp(() {
    // The alt-text field watches settingsProvider (AI-availability), which
    // loads SharedPreferences; give it an empty, mockable store.
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is EditorField && w.label == label),
    matching: find.byType(TextField),
  );

  Future<Slide? Function()> pump(WidgetTester tester, Slide slide) async {
    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(TwoImagesEditor(slide: slide, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

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

  testWidgets('typing left alt-text emits it without an AI marker', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.twoImages,
    ).copyWith(imagePath: 'images/left.png');
    final latest = await pump(tester, slide);

    // Only the left image is set, so there is exactly one alt-text field.
    await tester.enterText(
      find.descendant(
        of: find.byType(AltTextField),
        matching: find.byType(TextField),
      ),
      'Beschrijving links',
    );
    await tester.pump();

    expect(latest()!.imageAltText, 'Beschrijving links');
    expect(latest()!.aiAssistedFields.contains('imageAltText'), isFalse);
  });

  testWidgets('typing right alt-text emits imageAltText2', (tester) async {
    final slide = Slide.create(
      SlideType.twoImages,
    ).copyWith(imagePath: 'images/left.png', imagePath2: 'images/right.png');
    final latest = await pump(tester, slide);

    // Both images set → two alt fields; index 1 belongs to the right picker.
    final rightAlt = find.descendant(
      of: find.byType(AltTextField).at(1),
      matching: find.byType(TextField),
    );
    await tester.enterText(rightAlt, 'Beschrijving rechts');
    await tester.pump();

    expect(latest()!.imageAltText2, 'Beschrijving rechts');
    expect(latest()!.aiAssistedFields.contains('imageAltText2'), isFalse);
  });

  testWidgets('marking a left AI-draft alt-text reviewed clears the marker', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.twoImages).copyWith(
      imagePath: 'images/left.png',
      imageAltText: 'AI-tekst',
      aiAssistedFields: const ['imageAltText'],
    );
    final latest = await pump(tester, slide);

    expect(find.text('AI-concept'), findsOneWidget);
    await tester.tap(find.text('Nagekeken'));
    await tester.pump();

    expect(latest()!.aiAssistedFields.contains('imageAltText'), isFalse);
  });

  testWidgets('clearing the left image empties its path', (tester) async {
    final slide = Slide.create(
      SlideType.twoImages,
    ).copyWith(imagePath: 'images/left.png', imageCaption: 'onderschrift');
    final latest = await pump(tester, slide);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(latest()!.imagePath, '');
    expect(latest()!.imageCaption, '');
  });

  testWidgets('the split slider shows the left/right ratio and emits changes', (
    tester,
  ) async {
    final latest = await pump(tester, Slide.create(SlideType.twoImages));

    expect(find.text('Links 50% — Rechts 50%'), findsOneWidget);

    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pump();
    await tester.drag(slider, const Offset(120, 0));
    await tester.pump();

    // Dragging emits an updated split within the editor's 20–80 bounds.
    expect(latest(), isNotNull);
    expect(latest()!.imageSize, inInclusiveRange(20, 80));
    expect(tester.takeException(), isNull);
  });
}
