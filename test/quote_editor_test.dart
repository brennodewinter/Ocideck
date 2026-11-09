import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/markdown_editor_field.dart';
import 'package:ocideck/widgets/editors/quote_editor.dart';

/// Behaviour tests for the `quote` slide editor: it edits the quote and author
/// into the slide, and reveals the background-zoom control only once a
/// background image is set.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          (w is EditorField && w.label == label) ||
          (w is MarkdownEditorField && w.label == label),
    ),
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
            body: QuoteEditor(slide: slide, onUpdate: (s) => updated = s),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  testWidgets('editing the quote and author emits them', (tester) async {
    final latest = await pump(tester, Slide.create(SlideType.quote));

    await tester.enterText(fieldByLabel('Citaat'), 'Trust, but verify.');
    await tester.enterText(fieldByLabel('Auteur'), 'Reagan');
    await tester.pump();

    expect(latest()!.quote, 'Trust, but verify.');
    expect(latest()!.quoteAuthor, 'Reagan');
  });

  testWidgets('the background-zoom control is hidden without an image', (
    tester,
  ) async {
    await pump(tester, Slide.create(SlideType.quote));

    expect(find.text('Zoom achtergrond'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Grijze waas over afbeelding'), findsNothing);
  });

  testWidgets('setting a background image reveals the zoom control', (
    tester,
  ) async {
    await pump(
      tester,
      Slide.create(SlideType.quote).copyWith(imagePath: 'bg.png'),
    );

    expect(find.text('Zoom achtergrond'), findsOneWidget);
  });
  testWidgets('the veil defaults to on and can be disabled', (tester) async {
    final latest = await pump(
      tester,
      Slide.create(SlideType.quote).copyWith(imagePath: 'bg.png'),
    );
    final checkbox = find.widgetWithText(
      CheckboxListTile,
      'Grijze waas over afbeelding',
    );
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
    await tester.tap(checkbox);
    await tester.pump();
    expect(latest()!.titleImageOverlay, isFalse);
  });

  testWidgets('a disabled veil can be enabled again', (tester) async {
    final latest = await pump(
      tester,
      Slide.create(
        SlideType.quote,
      ).copyWith(imagePath: 'bg.png', titleImageOverlay: false),
    );
    final checkbox = find.widgetWithText(
      CheckboxListTile,
      'Grijze waas over afbeelding',
    );
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
    await tester.tap(checkbox);
    await tester.pump();
    expect(latest()!.titleImageOverlay, isTrue);
  });
  testWidgets('strength starts at 52 and the slider changes it', (
    tester,
  ) async {
    final latest = await pump(
      tester,
      Slide.create(SlideType.quote).copyWith(imagePath: 'bg.png'),
    );
    final finder = find.byWidgetPredicate(
      (w) => w is Slider && w.min == 0 && w.max == 100,
    );
    final slider = tester.widget<Slider>(finder);
    expect(slider.value, 52);
    expect(slider.divisions, 100);
    expect(slider.semanticFormatterCallback!(75), '75%');
    slider.onChanged!(75);
    expect(latest()!.marpStyle.effectiveImageOverlayStrength, 75);
    expect(latest()!.titleImageOverlay, isTrue);
    await tester.drag(finder, const Offset(1000, 0));
    expect(latest()!.marpStyle.effectiveImageOverlayStrength, 100);
  });

  testWidgets('disabling the veil retains the selected strength', (
    tester,
  ) async {
    final latest = await pump(
      tester,
      Slide.create(SlideType.quote).copyWith(
        imagePath: 'bg.png',
        marpStyle: const MarpStyle(imageOverlayStrength: 75),
        titleImageOverlay: false,
      ),
    );
    final slider = tester.widget<Slider>(
      find.byWidgetPredicate((w) => w is Slider && w.max == 100),
    );
    expect(slider.value, 75);
    expect(slider.onChanged, isNull);
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Grijze waas over afbeelding'),
    );
    expect(latest()!.titleImageOverlay, isTrue);
    expect(latest()!.marpStyle.effectiveImageOverlayStrength, 75);
  });
}
