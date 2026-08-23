import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/code_editor.dart';

/// Behaviour tests for the `code` slide editor: it edits the title and source
/// (stored in `customMarkdown`), picks a highlight language, and keeps a
/// language that is not in the built-in list selectable.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder titleField() => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is EditorField && w.label == 'Titel (optioneel)',
    ),
    matching: find.byType(TextField),
  );
  // The title lives in an EditorField (first TextField); the monospace source
  // field is the second and last TextField.
  Finder codeField() => find.byType(TextField).last;

  Future<Slide? Function()> pump(WidgetTester tester, Slide slide) async {
    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(slide: slide, onUpdate: (s) => updated = s),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => updated;
  }

  testWidgets('renders a title, language picker and code field', (
    tester,
  ) async {
    await pump(tester, Slide.create(SlideType.code));

    expect(titleField(), findsOneWidget);
    expect(find.text('Programmeertaal'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.widgetWithText(TextField, ''), findsWidgets);
  });

  testWidgets('editing the title emits it', (tester) async {
    final latest = await pump(tester, Slide.create(SlideType.code));

    await tester.enterText(titleField(), 'Voorbeeld');
    await tester.pump();

    expect(latest()!.title, 'Voorbeeld');
  });

  testWidgets('editing the source emits it as customMarkdown', (tester) async {
    final latest = await pump(tester, Slide.create(SlideType.code));

    await tester.enterText(codeField(), 'print("hi")');
    await tester.pump();

    expect(latest()!.customMarkdown, 'print("hi")');
  });

  testWidgets('choosing a language emits its highlight id', (tester) async {
    final latest = await pump(tester, Slide.create(SlideType.code));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Python').last);
    await tester.pumpAndSettle();

    expect(latest()!.codeLanguage, 'python');
  });

  testWidgets('a language outside the built-in list stays selected', (
    tester,
  ) async {
    // `cobol` is not in the built-in list; the editor appends it so the current
    // value stays selectable rather than silently resetting to plain text.
    await pump(
      tester,
      Slide.create(SlideType.code).copyWith(codeLanguage: 'cobol'),
    );

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, 'cobol');
  });
}
