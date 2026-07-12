import 'package:flutter/material.dart';
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
}
