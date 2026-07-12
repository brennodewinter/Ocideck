import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/sec_module_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';

// The editor's TYPE selector reuses the same visual picker as 'Slide toevoegen'
// (AddSlideDialog), so both surfaces share one source and offer identical
// types. The security (informatieveiligheid) types are gated behind the module
// exactly like the add-slide picker — with one refinement: a slide that is
// already a security type can still be re-typed among them with the module off.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required bool reveal,
    SlideType initialType = SlideType.title,
  }) async {
    final container = ProviderContainer(
      overrides: [secModuleRevealProvider.overrideWithValue(reveal)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    if (initialType != SlideType.title) {
      notifier.updateSlide(0, Slide.create(initialType));
    }

    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  // The button carries the picker's title as its tooltip; a stable locator.
  final typeButton = find.byTooltip('Slide type kiezen');

  testWidgets('the TYPE selector opens the visual picker and applies a type', (
    tester,
  ) async {
    final container = await pump(tester, reveal: false);
    expect(typeButton, findsOneWidget);

    await tester.tap(typeButton);
    await tester.pumpAndSettle();
    expect(find.byType(AddSlideDialog), findsOneWidget);

    await tester.tap(find.text('Tabel'));
    await tester.pumpAndSettle();
    expect(
      container.read(deckProvider).deck!.slides.single.type,
      SlideType.table,
    );
  });

  testWidgets('module off: the picker hides the security types', (
    tester,
  ) async {
    await pump(tester, reveal: false);
    await tester.tap(typeButton);
    await tester.pumpAndSettle();

    // Same state as 'Slide toevoegen' with the module off: one category, so no
    // tab bar and no informatieveiligheid type is reachable.
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Bevinding'), findsNothing);
  });

  testWidgets('module on: the picker reveals the security tab', (tester) async {
    await pump(tester, reveal: true);
    await tester.tap(typeButton);
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsWidgets);
    await tester.tap(find.text('Informatieveiligheid'));
    await tester.pumpAndSettle();
    expect(find.text('Bevinding'), findsOneWidget);
  });

  testWidgets(
    'a security slide can be re-typed among security types with the module off',
    (tester) async {
      await pump(tester, reveal: false, initialType: SlideType.finding);
      await tester.tap(typeButton);
      await tester.pumpAndSettle();

      // Current slide is already a security type, so the category is revealed
      // (tab bar appears) even though the module is off — no dead-end.
      expect(find.byType(ChoiceChip), findsWidgets);
      await tester.tap(find.text('Informatieveiligheid'));
      await tester.pumpAndSettle();
      expect(find.text('Checklist'), findsOneWidget);
    },
  );
}
