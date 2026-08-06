import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';
import 'package:ocideck/widgets/editors/slide_type_help.dart';

void main() {
  Future<SlideType?> Function() openDialog(
    WidgetTester tester, {
    bool reveal = false,
    bool revealProcesverbetering = false,
    bool revealManagementsysteem = false,
    Size? surfaceSize,
  }) {
    SlideType? picked;
    return () async {
      // The exhaustive "all types" cases reveal every module at once — four
      // categories, so the tab bar wraps to more rows than the default
      // 800×600 test surface leaves room for. Give those a taller window; the
      // real app's window is comfortably larger than the AlertDialog either way.
      if (surfaceSize != null) {
        await tester.binding.setSurfaceSize(surfaceSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => picked = await AddSlideDialog.show(
                  context,
                  revealInfoSafety: reveal,
                  revealProcesverbetering: revealProcesverbetering,
                  revealManagementsysteem: revealManagementsysteem,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return picked;
    };
  }

  List<SlideType> visibleTypes(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<SlideTypePreviewPainter>()
      .map((p) => p.type)
      .toList();

  testWidgets('every slide type shows a wireframe preview', (tester) async {
    // Reveal every module so every type is offered; the "Alle" tab drops
    // the category filter so all of them are visible at once.
    await openDialog(
      tester,
      reveal: true,
      revealProcesverbetering: true,
      revealManagementsysteem: true,
      surfaceSize: const Size(800, 900),
    )();
    await tester.tap(find.text('Alle'));
    await tester.pumpAndSettle();
    expect(visibleTypes(tester).toSet(), SlideType.values.toSet());
  });

  testWidgets('offers every type in the slideTypeMeta registry', (
    tester,
  ) async {
    // Derived from the single source of truth, so a newly added type shows up
    // automatically instead of having to be added to a second hand-kept list.
    await openDialog(
      tester,
      reveal: true,
      revealProcesverbetering: true,
      revealManagementsysteem: true,
      surfaceSize: const Size(800, 900),
    )();
    await tester.tap(find.text('Alle'));
    await tester.pumpAndSettle();
    expect(visibleTypes(tester).toSet(), slideTypeMeta.keys.toSet());
  });

  testWidgets('hides the security types and tab bar until the module is on', (
    tester,
  ) async {
    // Module off (the default): only SlideCategory.general types are offered,
    // so no tab bar is drawn and no Informatieveiligheid type is reachable.
    await openDialog(tester)();
    expect(find.byKey(const Key('addSlideCategoryTabs')), findsNothing);
    expect(
      visibleTypes(
        tester,
      ).any((t) => t.category == SlideCategory.informationSecurity),
      isFalse,
    );
  });

  testWidgets('reveals the security types under a tab when the module is on', (
    tester,
  ) async {
    await openDialog(tester, reveal: true)();
    // A second category now carries types, so the tab bar appears. The default
    // tab is Algemeen, so no security type is shown yet.
    expect(find.byKey(const Key('addSlideCategoryTabs')), findsWidgets);
    expect(
      visibleTypes(
        tester,
      ).any((t) => t.category == SlideCategory.informationSecurity),
      isFalse,
    );
    // The Informatieveiligheid tab shows exactly the module's types.
    await tester.tap(find.text('Informatieveiligheid'));
    await tester.pumpAndSettle();
    expect(visibleTypes(tester).toSet(), {
      SlideType.assets,
      SlideType.discoveries,
      SlideType.finding,
      SlideType.findingsSummary,
      SlideType.checklist,
      SlideType.scopeMatrix,
      SlideType.signOff,
    });
  });

  testWidgets('the search field filters cards by localised label', (
    tester,
  ) async {
    await openDialog(tester)();
    expect(find.text('Tabel'), findsOneWidget);
    expect(find.text('Titelpagina'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tab');
    await tester.pumpAndSettle();

    expect(find.text('Tabel'), findsOneWidget);
    expect(find.text('Titelpagina'), findsNothing);
    expect(visibleTypes(tester), [SlideType.table]);
  });

  testWidgets('an empty search shows a no-results message', (tester) async {
    await openDialog(tester)();
    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.pumpAndSettle();
    expect(visibleTypes(tester), isEmpty);
    expect(find.text('Geen resultaten'), findsOneWidget);
  });

  testWidgets('the sort toggle switches to alphabetical order', (tester) async {
    await openDialog(tester)();
    // Curated order leads with the title slide.
    expect(visibleTypes(tester).first, SlideType.title);

    await tester.tap(find.byTooltip('Alfabetisch sorteren'));
    await tester.pumpAndSettle();

    // Assert the *ordering*, not which label happens to win it. Naming the
    // winner meant this test broke every time a type was added whose label
    // sorted early — which says nothing about whether sorting works.
    final labels = [
      for (final type in visibleTypes(tester)) slideTypeMeta[type]!.label,
    ];
    final sorted = [...labels]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(labels, sorted);
  });

  testWidgets('type cards are labelled buttons (WCAG name/role)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openDialog(tester)();
    expect(
      tester.getSemantics(find.text('Tabel')),
      isSemantics(isButton: true, isFocusable: true, label: 'Tabel'),
    );
    handle.dispose();
  });

  testWidgets('the dialog is fully keyboard-operable', (tester) async {
    SlideType? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async =>
                  picked = await AddSlideDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The first card (title slide) is focused on open; tab moves to the
    // second card and Enter activates it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, SlideType.section);
  });

  testWidgets('escape closes the dialog without choosing', (tester) async {
    await openDialog(tester)();
    expect(find.byType(AddSlideDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AddSlideDialog), findsNothing);
  });

  testWidgets('de uitleg staat waar de keuze wordt gemaakt', (tester) async {
    // De volledige uitleg per slidetype lag al klaar in 32 talen, maar
    // verscheen pas ná het invoegen, achter een dichtgeklapte "Wat kan ik
    // hier?". Wie moest kiezen, koos op een draadframe en een woord.
    await openDialog(tester)();
    const l10n = AppLocalizations(Locale('nl'));

    // Het eerste kaartje heeft de focus, dus die uitleg staat er meteen.
    expect(find.text(slideTypeHelpText(l10n, SlideType.title)), findsOneWidget);

    // Een ander kaartje aanwijzen wisselt de uitleg.
    final tableHelp = slideTypeHelpText(l10n, SlideType.table);
    expect(find.text(tableHelp), findsNothing);
    final card = find.ancestor(
      of: find.byWidgetPredicate((w) {
        final painter = w is CustomPaint ? w.painter : null;
        return painter is SlideTypePreviewPainter &&
            painter.type == SlideType.table;
      }),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(card.first);
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(card.first));
    await tester.pumpAndSettle();
    expect(find.text(tableHelp), findsOneWidget);
    // En de uitleg van het vorige type is weg: één vak, één antwoord.
    expect(find.text(slideTypeHelpText(l10n, SlideType.title)), findsNothing);
  });

  testWidgets('een schermlezer hoort de uitleg op het kaartje zelf', (
    tester,
  ) async {
    // Het vak onder het rooster wordt door een schermlezer niet vanzelf
    // gepasseerd; de hint op de knop wél.
    await openDialog(tester)();
    const l10n = AppLocalizations(Locale('nl'));
    final semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((s) => s.properties.hint != null)
        .map((s) => s.properties.hint)
        .toSet();
    expect(semantics, contains(slideTypeHelpText(l10n, SlideType.quote)));
  });
}
