import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/preview_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget-coverage tests for the live preview panel and its two companion
/// widgets (the full-deck overlay and the collapsed rail). These drive the
/// header zoom controls, the collapse toggle, the navigation footer and
/// keyboard navigation — all the interactive bits the plain smoke test in
/// preview_panel_test.dart leaves untouched.
///
/// Like that suite they use bounded `pump()`s, never `pumpAndSettle()`: the
/// preview can host a perpetually-animating element (a blinking caret) which
/// would make `pumpAndSettle` spin for its full timeout.
ProviderContainer _deckWith(List<Slide> slides) {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  final deck = container.read(deckProvider.notifier);
  deck.newDeck('Preview test');
  for (final s in slides) {
    // Insert real slides after the starter title slide.
    deck.insertSlides([s]);
  }
  container.read(editorProvider.notifier).select(0);
  return container;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: PreviewPanel()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpOverview(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(1100, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final deck = container.read(deckProvider).deck!;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: FullDeckPreview(
          deck: deck,
          themeProfile: deck.themeProfile,
          editable: true,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('zoom in, reset and zoom out through the header controls', (
    tester,
  ) async {
    final container = _deckWith([Slide.create(SlideType.bullets)]);
    addTearDown(container.dispose);
    await _pumpPanel(tester, container);

    // Starts at 100%; zoom-out is disabled at the minimum.
    expect(find.text('100%'), findsOneWidget);

    // Zoom in twice: 100 → 150 → 200%.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    expect(find.text('200%'), findsOneWidget);

    // Zoom out once: back to 150%.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.remove));
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);

    // Tapping the percentage resets to 100%.
    await tester.tap(find.text('150%'));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the collapse button flips the app-wide collapsed flag', (
    tester,
  ) async {
    final container = _deckWith([Slide.create(SlideType.bullets)]);
    addTearDown(container.dispose);
    await _pumpPanel(tester, container);

    expect(container.read(previewCollapsedProvider), isFalse);
    await tester.tap(find.byTooltip('Preview inklappen'));
    await tester.pump();
    expect(container.read(previewCollapsedProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the navigation footer steps the selection through the deck', (
    tester,
  ) async {
    final container = _deckWith([
      Slide.create(SlideType.bullets),
      Slide.create(SlideType.quote),
      Slide.create(SlideType.table),
    ]);
    addTearDown(container.dispose);
    await _pumpPanel(tester, container);

    expect(container.read(editorProvider).selectedIndex, 0);

    // Next twice, then previous once.
    await tester.tap(find.byTooltip('Volgende slide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(editorProvider).selectedIndex, 1);

    await tester.tap(find.byTooltip('Volgende slide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(editorProvider).selectedIndex, 2);

    await tester.tap(find.byTooltip('Vorige slide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(editorProvider).selectedIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrow keys navigate the preview once it has focus', (
    tester,
  ) async {
    final container = _deckWith([
      Slide.create(SlideType.bullets),
      Slide.create(SlideType.quote),
    ]);
    addTearDown(container.dispose);
    await _pumpPanel(tester, container);

    // The header title sits on the panel's GestureDetector, so tapping it
    // requests focus without hitting a button.
    await tester.tap(find.text('Preview'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(editorProvider).selectedIndex, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(editorProvider).selectedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the theme chip shows the theme and pagination state', (
    tester,
  ) async {
    final container = _deckWith([Slide.create(SlideType.bullets)]);
    addTearDown(container.dispose);
    await _pumpPanel(tester, container);

    // Default decks paginate, so the "paginering aan" marker shows.
    expect(find.textContaining('Thema:'), findsOneWidget);
    expect(find.text('paginering aan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rich-text slide previews without error', (tester) async {
    // Rich-text bullets exercise the richTextPageCount branch in build/_move.
    final rich = Slide.create(SlideType.bullets).copyWith(
      listStyle: ListStyle.richText,
      customMarkdown: List.generate(
        40,
        (i) => 'Regel $i met wat langere tekst om te vullen.',
      ).join('\n\n'),
    );
    final container = _deckWith([rich]);
    addTearDown(container.dispose);
    // The rich slide sits after the starter title slide; select it so build
    // and _move take the rich-text pagination path.
    container.read(editorProvider.notifier).select(1);
    await _pumpPanel(tester, container);

    expect(find.byType(PreviewPanel), findsOneWidget);
    // Step a page forward via the provider; the panel clamps to the real page
    // count so this is safe whether or not the content actually overflowed.
    container.read(richTextPreviewPageProvider.notifier).state = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('FullDeckPreview lists every slide with a header label', (
    tester,
  ) async {
    final container = _deckWith([
      Slide.create(SlideType.bullets),
      Slide.create(SlideType.quote),
    ]);
    addTearDown(container.dispose);
    final deck = container.read(deckProvider).deck!;

    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: FullDeckPreview(deck: deck, themeProfile: deck.themeProfile),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FullDeckPreview), findsOneWidget);
    expect(find.textContaining('Slide 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FullDeckPreview lists every rendered finding page', (
    tester,
  ) async {
    final body = List.filled(8, 'lorem ipsum dolor sit amet').join(' ');
    final finding = Slide.create(SlideType.finding).copyWith(
      customMarkdown: FindingSpec(
        heading: 'F-03 · SQL-injectie',
        scopeObject: 'https://app.voorbeeld/login',
        cvssVector:
            'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
        description: body,
        confirmation: body,
        impact: body,
        recommendation: body,
      ).toMarkdown(),
    );
    final container = _deckWith([finding]);
    addTearDown(container.dispose);
    final deck = container.read(deckProvider).deck!;
    final numberedProfile = deck.themeProfile.copyWith(
      footerShowPageNumbers: true,
    );

    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: FullDeckPreview(deck: deck, themeProfile: numberedProfile),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Starter title + two rendered pages for the authored finding. Both the
    // list labels and the in-slide footers count the expanded render list, just
    // like presenter/export, rather than the two authored slides. Since #1198
    // the compact continuation heading reclaims room, so this finding fits in
    // two pages instead of three.
    for (var page = 1; page <= 3; page++) {
      expect(find.text('Slide $page'), findsOneWidget);
    }
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.textContaining('Slide 4'), findsNothing);
    expect(find.textContaining('(1/2)'), findsOneWidget);
    expect(find.textContaining('(2/2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slide overview reorders with the keyboard and can undo', (
    tester,
  ) async {
    final container = _deckWith([
      Slide.create(SlideType.bullets).copyWith(title: 'Alpha'),
      Slide.create(SlideType.quote).copyWith(title: 'Beta'),
      Slide.create(SlideType.table).copyWith(title: 'Gamma'),
    ]);
    addTearDown(container.dispose);
    final before = container
        .read(deckProvider)
        .deck!
        .slides
        .map((slide) => slide.id)
        .toList();
    await _pumpOverview(tester, container);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final moved = container
        .read(deckProvider)
        .deck!
        .slides
        .map((slide) => slide.id)
        .toList();
    expect(moved[1], before[0]);
    expect(container.read(editorProvider).selectedIndex, 1);

    await tester.tap(find.byKey(const Key('overview-undo')));
    await tester.pump();
    expect(
      container.read(deckProvider).deck!.slides.map((slide) => slide.id),
      before,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pointer drag moves a multi-selection as one block', (
    tester,
  ) async {
    final container = _deckWith([
      Slide.create(SlideType.bullets).copyWith(title: 'Alpha'),
      Slide.create(SlideType.quote).copyWith(title: 'Beta'),
      Slide.create(SlideType.table).copyWith(title: 'Gamma'),
    ]);
    addTearDown(container.dispose);
    final before = container
        .read(deckProvider)
        .deck!
        .slides
        .map((slide) => slide.id)
        .toList();
    await _pumpOverview(tester, container);

    await tester.tap(find.text('2. Alpha'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('3. Beta'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(container.read(editorProvider).selection, {1, 2});

    final source = tester.getCenter(find.byIcon(Icons.drag_indicator).at(1));
    final target = tester.getCenter(find.byType(DragTarget<int>).at(3));
    final gesture = await tester.startGesture(source);
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    final after = container
        .read(deckProvider)
        .deck!
        .slides
        .map((slide) => slide.id)
        .toList();
    expect(after, [before[0], before[3], before[1], before[2]]);
    expect(container.read(editorProvider).selection, {2, 3});
    expect(container.read(editorProvider).selectedIndex, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slide overview shows authored slides once in a responsive grid',
    (tester) async {
      final body = List.filled(8, 'lorem ipsum dolor sit amet').join(' ');
      final finding = Slide.create(SlideType.finding).copyWith(
        customMarkdown: FindingSpec(
          heading: 'F-03 · SQL-injectie',
          scopeObject: 'https://app.voorbeeld/login',
          cvssVector:
              'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
          description: body,
          confirmation: body,
          impact: body,
          recommendation: body,
        ).toMarkdown(),
      );
      final container = _deckWith([finding, Slide.create(SlideType.quote)]);
      addTearDown(container.dispose);
      await _pumpOverview(tester, container);

      expect(
        find.byType(DragTarget<int>),
        findsNWidgets(container.read(deckProvider).deck!.slides.length),
      );
      final first = tester.getTopLeft(find.byType(DragTarget<int>).at(0));
      final second = tester.getTopLeft(find.byType(DragTarget<int>).at(1));
      expect(second.dy, first.dy);

      await tester.binding.setSurfaceSize(const Size(500, 800));
      await tester.pump();
      final narrowFirst = tester.getTopLeft(find.byType(DragTarget<int>).at(0));
      final narrowSecond = tester.getTopLeft(
        find.byType(DragTarget<int>).at(1),
      );
      expect(narrowSecond.dy, greaterThan(narrowFirst.dy));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('slide overview stays usable at 200 percent text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = _deckWith([
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Een bewust uitzonderlijk lange vertaalde slidenaam'),
      Slide.create(SlideType.quote),
    ]);
    addTearDown(container.dispose);
    await _pumpOverview(tester, container, size: const Size(520, 800));

    final title = tester.widget<Text>(find.textContaining('Slide-overzicht'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.byIcon(Icons.drag_indicator), findsWidgets);
    expect(find.byKey(const Key('overview-undo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finalized slide overview is visibly read-only', (tester) async {
    final container = _deckWith([Slide.create(SlideType.bullets)]);
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.loadDeck(
      container.read(deckProvider).deck!.copyWith(finalized: true),
      preserveThemeProfile: true,
    );
    await _pumpOverview(tester, container);

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('overview-undo')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('CollapsedPreviewBar expands the panel again when tapped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Start collapsed so the expand tap is observable as a state change.
    container.read(previewCollapsedProvider.notifier).state = true;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Row(children: [CollapsedPreviewBar()])),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PREVIEW'), findsOneWidget);
    await tester.tap(find.byTooltip('Preview uitklappen'));
    await tester.pump();
    expect(container.read(previewCollapsedProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  group('redactie is zichtbaar vóór verzending', () {
    // Het label in de editor belooft "weglaten uit tonen en exporteren", maar
    // het scherm deed niets: de preview toonde het rauwe deck en de projectie
    // draaide alleen bij presenteren en exporteren. Pas de PDF gaf antwoord.
    ProviderContainer redactedDeck() {
      final container = _deckWith([
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Contact',
          bullets: const ['Mail: jan.jansen@voorbeeld.nl'],
          imagePath: 'images/team.png',
          privacy: PrivacyDisposition.redact,
        ),
      ]);
      container.read(editorProvider.notifier).select(1);
      return container;
    }

    testWidgets('een gewone dia krijgt geen melding', (tester) async {
      // Een balk die er altijd staat, wordt niet meer gelezen.
      final container = _deckWith([Slide.create(SlideType.bullets)]);
      addTearDown(container.dispose);
      await _pumpPanel(tester, container);
      expect(find.textContaining('Weglaten staat aan'), findsNothing);
    });

    testWidgets('een weggelaten dia meldt het, inclusief de media', (
      tester,
    ) async {
      final container = redactedDeck();
      addTearDown(container.dispose);
      await _pumpPanel(tester, container);
      expect(find.textContaining('Weglaten staat aan'), findsOneWidget);
      // Dat álle media verdwijnt stond nergens, en het is de duurste
      // verrassing: een dia die in de export ineens leeg is.
      expect(
        find.textContaining('afbeeldingen, video en audio'),
        findsOneWidget,
      );
    });

    testWidgets('de schakelaar toont wat de ontvanger krijgt', (tester) async {
      final container = redactedDeck();
      addTearDown(container.dispose);
      await _pumpPanel(tester, container);

      // Standaard de eigen tekst: anders valt er niets meer te bewerken.
      expect(find.text('Wat zij zien'), findsOneWidget);
      expect(container.read(audiencePreviewProvider), isFalse);

      await tester.tap(find.text('Wat zij zien'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(audiencePreviewProvider), isTrue);
      expect(find.text('Mijn tekst'), findsOneWidget);
    });
  });
}
