import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/two_bullets_editor.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('edits title and per-column headings', (tester) async {
    var updated = Slide.create(
      SlideType.twoBullets,
    ).copyWith(bullets: const ['a'], bullets2: const ['b']);
    await tester.pumpScoped(
      _host(TwoBulletsEditor(slide: updated, onUpdate: (s) => updated = s)),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Slide titel'), 'T');
    expect(updated.title, 'T');

    final headings = find.widgetWithText(TextField, 'Kop (optioneel)');
    await tester.enterText(headings.first, 'Voordelen');
    expect(updated.columnTitle1, 'Voordelen');
  });

  testWidgets('switches marker to paw and adds a bullet to the left column', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.twoBullets,
    ).copyWith(bullets: const ['a'], bullets2: const ['b']);
    await tester.pumpScoped(
      _host(TwoBulletsEditor(slide: updated, onUpdate: (s) => updated = s)),
    );

    await tester.tap(find.text('Pootje'));
    await tester.pumpAndSettle();
    expect(updated.bulletMarkerOverride, BulletMarker.paw);

    await tester.tap(find.text('Bullet toevoegen').first);
    await tester.pumpAndSettle();
    expect(updated.bullets.length, 2);
    expect(updated.bullets2.length, 1);
  });

  testWidgets('numbered then checklist style with progress + a checked item', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.twoBullets,
    ).copyWith(bullets: const ['a', 'b'], bullets2: const ['c']);
    await tester.pumpScoped(
      _host(TwoBulletsEditor(slide: updated, onUpdate: (s) => updated = s)),
    );

    await tester.tap(find.text('Nummering'));
    await tester.pumpAndSettle();
    expect(updated.listStyle, ListStyle.numbered);

    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();
    expect(updated.listStyle, ListStyle.checklist);
    expect(updated.bullets.first, '[ ] a');

    await tester.tap(find.text('Voortgangsgrafiek tonen'));
    await tester.pumpAndSettle();
    expect(updated.showChecklistProgress, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('checklist-item-Bullets links-0')),
    );
    await tester.pumpAndSettle();
    expect(updated.bullets.first, '[x] a');
  });

  testWidgets('removes a bullet from a column', (tester) async {
    var updated = Slide.create(
      SlideType.twoBullets,
    ).copyWith(bullets: const ['a', 'b'], bullets2: const ['c']);
    await tester.pumpScoped(
      _host(TwoBulletsEditor(slide: updated, onUpdate: (s) => updated = s)),
    );

    await tester.tap(
      find.byKey(const ValueKey('remove-bullet-Bullets links-1')),
    );
    await tester.pumpAndSettle();
    expect(updated.bullets, const ['a']);
    expect(updated.bullets2, const ['c']);
  });
}

/// De editors lezen de editorstate (om naar een gemelde bullet te springen), en
/// een Riverpod-consumer zonder scope gooit meteen. Elke pump krijgt er dus een.
extension on WidgetTester {
  Future<void> pumpScoped(Widget child) =>
      pumpWidget(ProviderScope(child: child));
}
