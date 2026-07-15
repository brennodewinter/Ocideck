import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/two_bullets_editor.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets(
    'two-bullets editor keeps a heading intact in checklist mode (no checkbox)',
    (tester) async {
      // A heading that arrived (e.g. via a type change) in a two-column
      // checklist slide must not be wrapped as a `[ ]` task on the next edit.
      var updated = Slide.create(SlideType.twoBullets).copyWith(
        bullets: [groupHeadingBullet('Blok A'), '[x] Gedaan'],
        bullets2: const ['[ ] Later'],
        listStyle: ListStyle.checklist,
      );

      await tester.pumpWidget(
        _testApp(
          TwoBulletsEditor(
            slide: updated,
            onUpdate: (slide) => updated = slide,
          ),
        ),
      );
      await tester.pump();

      // The heading label shows in a field, without the raw marker.
      expect(find.widgetWithText(TextField, 'Blok A'), findsOneWidget);

      // Toggle the first task's checkbox to force a re-emit, then assert the
      // heading survived as a heading (not a checkbox item).
      await tester.tap(
        find.byKey(const ValueKey('checklist-item-Bullets links-1')),
      );
      await tester.pump();

      expect(updated.bullets.first, groupHeadingBullet('Blok A'));
      expect(isGroupHeading(updated.bullets.first), isTrue);
      // The tapped task flipped to unchecked; still a task, not corrupted.
      expect(updated.bullets[1], '[ ] Gedaan');
      expect(updated.bullets2, const ['[ ] Later']);
    },
  );

  testWidgets('two-bullets "Tussenkop toevoegen" adds a heading to its column', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.twoBullets,
    ).copyWith(bullets: const ['Links'], bullets2: const ['Rechts']);

    await tester.pumpWidget(
      _testApp(
        TwoBulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );
    await tester.pump();

    // Two "add heading" buttons — one per column; tap the first (left column).
    await tester.tap(find.text('Tussenkop toevoegen').first);
    await tester.pump();

    expect(updated.bullets.where(isGroupHeading).length, 1);
    expect(updated.bullets2.where(isGroupHeading).length, 0);
  });
}
