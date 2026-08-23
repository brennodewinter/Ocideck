import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/bullets_editor.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('rich text mode uses the markdown editor', (tester) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Titel', customMarkdown: 'Bestaande tekst');

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );

    await tester.tap(find.text('Teksteditor'));
    await tester.pumpAndSettle();
    expect(updated.listStyle, ListStyle.richText);
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(find.text('Voortgangsgrafiek tonen'), findsNothing);
    expect(find.text('Bullet toevoegen'), findsNothing);
  });

  testWidgets('switching list styles preserves bullets and rich text', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['Eerste punt'], customMarkdown: 'Vrije tekst');

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );

    await tester.tap(find.text('Teksteditor'));
    await tester.pumpAndSettle();
    expect(updated.bullets, ['Eerste punt']);
    expect(updated.customMarkdown, 'Vrije tekst');

    await tester.tap(find.text('Opsomming'));
    await tester.pumpAndSettle();
    expect(updated.bullets, ['Eerste punt']);
    expect(updated.customMarkdown, 'Vrije tekst');
  });

  testWidgets('checklist items can be marked as checked', (tester) async {
    var updated = Slide.create(SlideType.bullets).copyWith(bullets: ['Taak']);

    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: BulletsEditor(
            slide: updated,
            onUpdate: (slide) => updated = slide,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Checklist'));
    await tester.pump();
    expect(updated.listStyle, ListStyle.checklist);
    expect(updated.bullets, ['[ ] Taak']);

    await tester.tap(find.byKey(const ValueKey('checklist-item-0')));
    await tester.pump();
    expect(updated.bullets, ['[x] Taak']);
  });

  testWidgets('removing the final bullet leaves an empty bullet', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['Enige bullet']);

    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: BulletsEditor(
            slide: updated,
            onUpdate: (slide) => updated = slide,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('remove-bullet-0')));
    await tester.pump();

    expect(updated.bullets, ['']);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('removing the final checklist item also resets its state', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['\t[x] Afgerond'], listStyle: ListStyle.checklist);

    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: BulletsEditor(
            slide: updated,
            onUpdate: (slide) => updated = slide,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('remove-bullet-0')));
    await tester.pump();

    expect(updated.bullets, ['[ ] ']);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('checklist-item-0')))
          .value,
      isFalse,
    );
  });

  testWidgets('checked items render checked and struck through', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      bullets: ['[x] Klaar', '[ ] Open'],
      listStyle: ListStyle.checklist,
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    );

    expect(find.text('☑ '), findsOneWidget);
    expect(find.text('☐ '), findsOneWidget);
    final checked = tester.widget<InlineMarkdownText>(
      find.byWidgetPredicate(
        (widget) => widget is InlineMarkdownText && widget.text == 'Klaar',
      ),
    );
    expect(checked.style.decoration, TextDecoration.lineThrough);
  });

  testWidgets('checked item strike-through follows the style profile', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['[x] Klaar'], listStyle: ListStyle.checklist);
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: const ThemeProfile(checklistStrikeThrough: false),
            ),
          ),
        ),
      ),
    );

    final checked = tester.widget<InlineMarkdownText>(
      find.byWidgetPredicate(
        (widget) => widget is InlineMarkdownText && widget.text == 'Klaar',
      ),
    );
    expect(checked.style.decoration, isNull);
  });

  testWidgets('checklist progress chart can be enabled', (tester) async {
    var updated = Slide.create(SlideType.bullets).copyWith(
      bullets: ['[x] Klaar', '[ ] Open'],
      listStyle: ListStyle.checklist,
    );

    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: BulletsEditor(
            slide: updated,
            onUpdate: (slide) => updated = slide,
          ),
        ),
      ),
    );

    expect(find.text('Voortgangsgrafiek tonen'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(updated.showChecklistProgress, isTrue);
  });

  testWidgets('checklist progress chart shows checked percentages', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      bullets: ['[x] Klaar', '[ ] Open'],
      listStyle: ListStyle.checklist,
      showChecklistProgress: true,
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: const ThemeProfile(
                checklistCheckedColor: '#00AA00',
                checklistUncheckedColor: '#CC0000',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Afgevinkt 50%'), findsOneWidget);
    expect(find.text('Niet afgevinkt 50%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('checklist-progress-pie')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('checklist-progress-pie')))
          .width,
      greaterThan(200),
    );
    final pie = tester.widget<PieChart>(
      find.byKey(const ValueKey('checklist-progress-pie')),
    );
    expect(pie.data.sections[0].color, const Color(0xFF00AA00));
    expect(pie.data.sections[1].color, const Color(0xFFCC0000));
  });

  testWidgets('presented checklist items can be toggled', (tester) async {
    Slide? updated;
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['[ ] Open'], listStyle: ListStyle.checklist);
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              presentationMode: true,
              onChecklistItemToggle: (column, itemIndex) {
                updated = slide.copyWith(bullets: ['[x] Open']);
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('checklist-preview-toggle-0-0')),
    );
    expect(updated?.bullets, ['[x] Open']);
  });

  testWidgets('a redacted checklist slide cannot be toggled', (tester) async {
    // De presenter draait op het geprojecteerde deck en schrijft een vinkje als
    // HELE slide terug. Op een geredigeerde slide zou dat de bron met zwarte
    // blokken overschrijven, dus het aanvinken is daar uitgeschakeld.
    var fired = false;
    final slide = Slide.create(SlideType.bullets).copyWith(
      bullets: ['[ ] Open'],
      listStyle: ListStyle.checklist,
      contentRedacted: true,
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              presentationMode: true,
              onChecklistItemToggle: (_, _) => fired = true,
            ),
          ),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('checklist-preview-toggle-0-0'));
    if (toggle.evaluate().isNotEmpty) await tester.tap(toggle);
    expect(fired, isFalse);
  });

  testWidgets('rich text bullets slide renders title and body', (tester) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: 'Kop',
      subtitle: 'Subkop',
      listStyle: ListStyle.richText,
      customMarkdown: 'Inhoud met **vet**',
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    );

    expect(find.text('Kop'), findsOneWidget);
    expect(find.text('Subkop'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InlineMarkdownText && widget.text.contains('Inhoud met'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('rich text bullets use the full slide content width', (
    tester,
  ) async {
    const slideWidth = 800.0;
    final slide = Slide.create(SlideType.bullets).copyWith(
      listStyle: ListStyle.richText,
      customMarkdown:
          '${'Lange tekst '.padRight(120, 'a')} die over de volle breedte moet lopen.',
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: slideWidth,
            height: 450,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    );
    await tester.pump();

    final bodyFinder = find.byWidgetPredicate(
      (widget) =>
          widget is InlineMarkdownText && widget.text.contains('Lange tekst'),
    );
    final renderBox = tester.renderObject<RenderBox>(bodyFinder);
    final expectedContentWidth = slideWidth * (1 - 0.07 * 2);
    expect(renderBox.size.width, greaterThan(expectedContentWidth * 0.95));
  });

  testWidgets('rich text bullets do not overflow in a small thumbnail', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: 'Korte titel',
      listStyle: ListStyle.richText,
      customMarkdown: '''
# Kop
Paragraaf met **vet** en wat extra tekst zodat de layout echt iets te doen heeft.
- Eerste punt
- Tweede punt met meer woorden
''',
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 112,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich text bullets+image do not overflow in a small thumbnail', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      title: 'Korte titel',
      listStyle: ListStyle.richText,
      imagePath: 'images/test.png',
      customMarkdown: '''
Paragraaf met **vet** en wat extra tekst zodat de layout echt iets te doen heeft.
- Eerste punt
- Tweede punt met meer woorden
''',
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 112,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hovering progress highlights matching checklist items', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      bullets: ['[x] Klaar', '[ ] Open'],
      listStyle: ListStyle.checklist,
      showChecklistProgress: true,
    );
    await tester.pumpScoped(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              presentationMode: true,
              onChecklistItemToggle: (_, _) {},
            ),
          ),
        ),
      ),
    );

    final checkedRow = find.byKey(const ValueKey('checklist-preview-item-0-0'));
    var container = tester.widget<AnimatedContainer>(checkedRow);
    expect((container.decoration as BoxDecoration).color, Colors.transparent);

    final checkedSegment = tester.widget<MouseRegion>(
      find.byKey(const ValueKey('checklist-progress-checked')),
    );
    checkedSegment.onEnter!(const PointerEnterEvent());
    await tester.pumpAndSettle();

    container = tester.widget<AnimatedContainer>(checkedRow);
    expect(
      (container.decoration as BoxDecoration).color,
      isNot(Colors.transparent),
    );
  });

  testWidgets('"Tussenkop toevoegen" appends a group-heading item', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );

    await tester.tap(find.text('Tussenkop toevoegen'));
    await tester.pumpAndSettle();

    expect(updated.bullets.length, 2);
    expect(isGroupHeading(updated.bullets.last), isTrue);
    // Typing into the new (focused) heading row fills its label.
    await tester.enterText(find.byType(TextField).last, 'Middag');
    await tester.pump();
    expect(updated.bullets.last, groupHeadingBullet('Middag'));
  });

  testWidgets('the divider button toggles a bullet to a heading and back', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['Blok A', 'Punt']);

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );

    // Toggle the first row into a heading.
    await tester.tap(find.byKey(const ValueKey('toggle-heading-0')));
    await tester.pumpAndSettle();
    expect(updated.bullets.first, groupHeadingBullet('Blok A'));
    expect(updated.bullets[1], 'Punt');

    // Toggle it back to an ordinary bullet — the label is preserved.
    await tester.tap(find.byKey(const ValueKey('toggle-heading-0')));
    await tester.pumpAndSettle();
    expect(updated.bullets.first, 'Blok A');
    expect(isGroupHeading(updated.bullets.first), isFalse);
  });

  testWidgets('removing a group-heading row drops it and keeps the bullets', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: [groupHeadingBullet('Kop'), 'Een', 'Twee']);

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('remove-bullet-0')));
    await tester.pump();

    expect(updated.bullets, ['Een', 'Twee']);
    expect(updated.bullets.any(isGroupHeading), isFalse);
  });

  testWidgets('adding a bullet after a heading yields a level-0 bullet', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: [groupHeadingBullet('Kop')]);

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );
    await tester.pump();

    // The bottom "Bullet toevoegen" adds after the last row (the heading); the
    // new row is an ordinary, non-indented bullet, not another heading.
    await tester.tap(find.text('Bullet toevoegen'));
    await tester.pump();

    expect(updated.bullets.length, 2);
    expect(isGroupHeading(updated.bullets[0]), isTrue);
    expect(isGroupHeading(updated.bullets[1]), isFalse);
    expect(updated.bullets[1].startsWith('\t'), isFalse);
  });

  testWidgets('a slide with a heading loads into the editor as a heading row', (
    tester,
  ) async {
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: [groupHeadingBullet('Ochtend'), 'Inloop']);

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
      ),
    );
    await tester.pump();

    // The heading's label shows in its field, not the raw marker.
    expect(find.widgetWithText(TextField, 'Ochtend'), findsOneWidget);
    // An unchanged round-trip through the editor keeps the heading intact.
    expect(updated.bullets.first, groupHeadingBullet('Ochtend'));
  });

  testWidgets(
    'een niveau dieper dan de knop kan, blijft staan als je iets anders typt',
    (tester) async {
      // #1558: _levelOf klemde bij het lezen op _maxLevel en _emit schreef dat
      // geklemde niveau terug. Eén letter in het eerste item liet daarmee het
      // vierde item zakken — een regel die de gebruiker niet had aangeraakt.
      // Zulke diepe niveaus komen echt voor: de parser rekent twee spaties per
      // niveau, dus een geïmporteerde lijst van vier zichtbare niveaus staat
      // intern op 0-2-4-6.
      var updated = Slide.create(SlideType.bullets).copyWith(
        title: 'Titel',
        bullets: const [
          'Eerste niveau',
          '\t\tTweede niveau',
          '\t\t\t\tDerde niveau',
          '\t\t\t\t\t\tVierde niveau',
        ],
      );

      await tester.pumpScoped(
        _testApp(
          BulletsEditor(slide: updated, onUpdate: (slide) => updated = slide),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(2), 'Eerste niveau!');
      await tester.pumpAndSettle();

      expect(updated.bullets.map(bulletLevel).toList(), [
        0,
        2,
        4,
        6,
      ], reason: 'het vierde item stond op 6 en is niet aangeraakt');
    },
  );
}

/// De editors lezen de editorstate (om naar een gemelde bullet te springen), en
/// een Riverpod-consumer zonder scope gooit meteen. Elke pump krijgt er dus een.
extension on WidgetTester {
  Future<void> pumpScoped(Widget child) =>
      pumpWidget(ProviderScope(child: child));
}
