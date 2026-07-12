import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/quote_editor.dart';

/// Behaviour tests for the `quote` slide editor: it edits the quote and author
/// into the slide, and reveals the background-zoom control only once a
/// background image is set.
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
}
