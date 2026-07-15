import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/bullets_image_editor.dart';
import 'package:ocideck/widgets/editors/two_bullets_editor.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  FlutterQuillLocalizations.delegate,
];

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

/// The bullets+image editor's image bar is a Riverpod `ConsumerWidget`, so it
/// needs a `ProviderScope` and a bounded canvas.
Widget _imageHost(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: _delegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 1400, height: 2000, child: child)),
    ),
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

  testWidgets('two-bullets divider button toggles a bullet ⇄ heading', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.twoBullets,
    ).copyWith(bullets: const ['Blok A', 'Punt'], bullets2: const ['R']);

    await tester.pumpWidget(
      _testApp(
        TwoBulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('toggle-heading-Bullets links-0')),
    );
    await tester.pumpAndSettle();
    expect(updated.bullets.first, groupHeadingBullet('Blok A'));

    await tester.tap(
      find.byKey(const ValueKey('toggle-heading-Bullets links-0')),
    );
    await tester.pumpAndSettle();
    expect(updated.bullets.first, 'Blok A');
    expect(isGroupHeading(updated.bullets.first), isFalse);
  });

  testWidgets('bullets+image editor adds, types and toggles a heading', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: const ['Punt']);

    await tester.pumpWidget(
      _imageHost(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (slide) => updated = slide,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Tussenkop toevoegen'));
    await tester.pumpAndSettle();
    expect(updated.bullets.length, 2);
    expect(isGroupHeading(updated.bullets.last), isTrue);
    await tester.enterText(find.byType(TextField).last, 'Middag');
    await tester.pump();
    expect(updated.bullets.last, groupHeadingBullet('Middag'));

    // Toggle the first row into a heading and back.
    await tester.tap(find.byKey(const ValueKey('toggle-heading-0')));
    await tester.pumpAndSettle();
    expect(updated.bullets.first, groupHeadingBullet('Punt'));
    await tester.tap(find.byKey(const ValueKey('toggle-heading-0')));
    await tester.pumpAndSettle();
    expect(updated.bullets.first, 'Punt');
  });

  testWidgets(
    'bullets+image editor loads a heading and keeps it in checklist mode',
    (tester) async {
      var updated = Slide.create(SlideType.bulletsImage).copyWith(
        bullets: [groupHeadingBullet('Blok'), '[x] Taak'],
        listStyle: ListStyle.checklist,
      );

      await tester.pumpWidget(
        _imageHost(
          BulletsImageEditor(
            slide: updated,
            onUpdate: (slide) => updated = slide,
            imageService: ImageService(),
          ),
        ),
      );
      await tester.pump();

      // The heading's label shows in its field, not the raw marker.
      expect(find.widgetWithText(TextField, 'Blok'), findsOneWidget);
      // Toggling the task re-emits; the heading survives (never a checkbox).
      await tester.tap(find.byKey(const ValueKey('checklist-item-1')));
      await tester.pump();
      expect(updated.bullets.first, groupHeadingBullet('Blok'));
      expect(isGroupHeading(updated.bullets.first), isTrue);
    },
  );
}
