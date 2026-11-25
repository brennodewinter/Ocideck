import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The editor's TYPE selector reuses the same visual picker as 'Slide toevoegen'
// (AddSlideDialog), so both surfaces share one source and offer identical
// types. The security (informatieveiligheid) types are gated behind the module
// exactly like the add-slide picker — with one refinement: a slide that is
// already a security type can still be re-typed among them with the module off.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required bool reveal,
    SlideType initialType = SlideType.title,
    double width = 1000,
    double height = 2200,
  }) async {
    final container = ProviderContainer(
      overrides: [infoSafetyRevealProvider.overrideWithValue(reveal)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    if (initialType != SlideType.title) {
      notifier.updateSlide(0, Slide.create(initialType));
    }

    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
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

  testWidgets('the editor toolbar fits the minimum editor width', (
    tester,
  ) async {
    await pump(tester, reveal: false, width: 420);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the TYPE selector opens the visual picker and applies a type', (
    tester,
  ) async {
    final container = await pump(
      tester,
      reveal: false,
      initialType: SlideType.table,
      height: 600,
    );
    expect(typeButton, findsOneWidget);

    await tester.tap(typeButton);
    await tester.pumpAndSettle();
    final dialog = find.byType(AddSlideDialog);
    Finder card(SlideType type) =>
        find.descendant(of: dialog, matching: find.byKey(ValueKey(type)));
    bool isSelected(SlideType type) => tester
        .widgetList<Semantics>(
          find.descendant(of: card(type), matching: find.byType(Semantics)),
        )
        .any((node) => node.properties.selected == true);

    expect(card(SlideType.table).hitTestable(), findsOneWidget);
    expect(isSelected(SlideType.table), isTrue);
    expect(isSelected(SlideType.title), isFalse);
    final ink = tester.widget<Ink>(
      find.descendant(of: card(SlideType.table), matching: find.byType(Ink)),
    );
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.color, AppTheme.warningBg);
    expect((decoration.border! as Border).top.color, AppTheme.amber600);

    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'Titelpagina',
    );
    await tester.pumpAndSettle();
    await tester.tap(card(SlideType.title));
    await tester.pumpAndSettle();
    expect(
      container.read(deckProvider).deck!.slides.single.type,
      SlideType.title,
    );

    await tester.tap(typeButton);
    await tester.pumpAndSettle();
    expect(isSelected(SlideType.title), isTrue);
    expect(isSelected(SlideType.table), isFalse);
  });

  testWidgets('de stijlkeuze vervangt latere wissels tot het einde', (
    tester,
  ) async {
    final container = await pump(tester, reveal: false);
    final notifier = container.read(deckProvider.notifier);
    final editor = container.read(editorProvider.notifier);
    final base = container.read(deckProvider).deck!.themeProfile.name;
    final defaultStyle = container
        .read(settingsProvider)
        .selectedThemeProfileName;
    const legacyStyles = [
      'Vigilis',
      'Security',
      'Vigilis',
      'deck',
      'Security',
      'Vigilis',
      'Security',
    ];
    final legacySlides = [
      for (final (i, style) in legacyStyles.indexed)
        '<!-- ocideck_style: $style -->\n\n# Dia ${i + 1}\n\n- Tekst',
    ].join('\n\n---\n\n');
    expect(
      notifier.applyMarkdown('---\nmarp: true\n---\n\n$legacySlides'),
      isTrue,
    );

    final picker = find.byKey(const Key('slide-style-from-here'));
    Future<void> select(int index) async {
      editor.select(index);
      await tester.pumpAndSettle();
    }

    Future<void> choose(String profile) async {
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text(profile).last);
      await tester.pumpAndSettle();
    }

    List<String> styles() {
      final deck = container.read(deckProvider).deck!;
      return List.generate(
        deck.slides.length,
        (i) => deck.slideProfileAt(i).name,
      );
    }

    await select(1);
    // Ook opnieuw kiezen van de actieve stijl vervangt alle latere wissels.
    await choose('Security');
    expect(styles(), ['Vigilis', ...List.filled(6, 'Security')]);

    notifier.undo();
    await tester.pumpAndSettle();
    expect(styles(), [
      'Vigilis',
      'Security',
      'Vigilis',
      base,
      'Security',
      'Vigilis',
      'Security',
    ]);
    await choose('Security');

    await select(2);
    expect(tester.widget<DropdownButton<String>>(picker).value, 'Security');
    expect(
      find.byTooltip(
        'Geërfd vanaf dia 2\nEen nieuwe keuze geldt vanaf deze dia tot het einde.',
      ),
      findsOneWidget,
    );

    await select(1);
    await tester.tap(typeButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AddSlideDialog),
        matching: find.byKey(const ValueKey(SlideType.title)),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(deckProvider).deck!.slides[1].type, SlideType.title);
    expect(container.read(deckProvider).deck!.slides[1].styleName, 'Security');

    await select(5);
    await choose('Vigilis');
    expect(styles(), [
      'Vigilis',
      ...List.filled(4, 'Security'),
      'Vigilis',
      'Vigilis',
    ]);

    await select(3);
    await choose('Deckstijl ($base)');
    expect(styles(), [
      'Vigilis',
      'Security',
      'Security',
      ...List.filled(4, base),
    ]);

    await select(5);
    await choose('Vigilis');
    final expected = [
      'Vigilis',
      'Security',
      'Security',
      base,
      base,
      'Vigilis',
      'Vigilis',
    ];
    expect(styles(), expected);
    expect(
      container.read(settingsProvider).selectedThemeProfileName,
      defaultStyle,
    );

    final markdown = notifier.generateMarkdown();
    expect(RegExp('<!-- ocideck_style:').allMatches(markdown), hasLength(4));
    expect(notifier.applyMarkdown(markdown), isTrue);
    expect(styles(), expected);
  });

  testWidgets('module off: the picker hides the security types', (
    tester,
  ) async {
    await pump(tester, reveal: false);
    await tester.tap(typeButton);
    await tester.pumpAndSettle();

    // Same state as 'Slide toevoegen' with the module off: one category, so no
    // tab bar and no informatieveiligheid type is reachable.
    expect(find.byKey(const Key('addSlideCategoryTabs')), findsNothing);
    expect(find.text('Bevinding'), findsNothing);
    // Aanvalsoppervlak is MIAUW-materiaal en hoort bij de module; het miste
    // alleen zijn categorie en stond daardoor altijd in de kiezer.
    expect(find.text('Aanvalsoppervlak'), findsNothing);
  });

  testWidgets('module on: the picker reveals the security tab', (tester) async {
    await pump(tester, reveal: true);
    await tester.tap(typeButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addSlideCategoryTabs')), findsWidgets);
    await tester.tap(find.text('Informatieveiligheid'));
    await tester.pumpAndSettle();
    expect(find.text('Bevinding'), findsOneWidget);
    expect(find.text('Aanvalsoppervlak'), findsOneWidget);
  });

  testWidgets(
    'a security slide can be re-typed among security types with the module off',
    (tester) async {
      await pump(tester, reveal: false, initialType: SlideType.finding);
      await tester.tap(typeButton);
      await tester.pumpAndSettle();

      // Current slide is already a security type, so the category is revealed
      // (tab bar appears) even though the module is off — no dead-end.
      expect(find.byKey(const Key('addSlideCategoryTabs')), findsWidgets);
      await tester.tap(find.text('Informatieveiligheid'));
      await tester.pumpAndSettle();
      expect(find.text('Uitvoering testen conform standaard'), findsOneWidget);
    },
  );
}
