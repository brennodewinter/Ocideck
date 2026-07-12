import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/free_markdown_editor.dart';

/// Behaviour tests for the `freeMarkdown` slide editor: a single monospace field
/// whose text is emitted as the slide's `customMarkdown`, laid out either
/// expanded (standalone) or fixed-height (nested in a scroll view).
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<Slide? Function()> pump(
    WidgetTester tester, {
    required bool nested,
    Slide? slide,
  }) async {
    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FreeMarkdownEditor(
            slide: slide ?? Slide.create(SlideType.freeMarkdown),
            onUpdate: (s) => updated = s,
            nestedInScrollView: nested,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  testWidgets('renders a labelled markdown field', (tester) async {
    await pump(tester, nested: false);

    expect(find.text('Markdown inhoud'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('editing emits the text as customMarkdown', (tester) async {
    final latest = await pump(tester, nested: false);

    await tester.enterText(find.byType(TextField), '# Titel\n\nInhoud');
    await tester.pump();

    expect(latest()!.customMarkdown, '# Titel\n\nInhoud');
  });

  testWidgets('starts from the slide\'s existing markdown', (tester) async {
    await pump(
      tester,
      nested: true,
      slide: Slide.create(
        SlideType.freeMarkdown,
      ).copyWith(customMarkdown: 'bestaande inhoud'),
    );

    expect(find.text('bestaande inhoud'), findsOneWidget);
  });

  testWidgets('nested layout also renders and emits', (tester) async {
    final latest = await pump(tester, nested: true);

    await tester.enterText(find.byType(TextField), 'genest');
    await tester.pump();

    expect(latest()!.customMarkdown, 'genest');
  });
}
