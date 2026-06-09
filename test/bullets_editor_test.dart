import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/bullets_editor.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  testWidgets('checklist items can be marked as checked', (tester) async {
    var updated = Slide.create(SlideType.bullets).copyWith(bullets: ['Taak']);

    await tester.pumpWidget(
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

    await tester.pumpWidget(
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

    await tester.pumpWidget(
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
    await tester.pumpWidget(
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
    await tester.pumpWidget(
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

    await tester.pumpWidget(
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
    await tester.pumpWidget(
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
    await tester.pumpWidget(
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

  testWidgets('hovering progress highlights matching checklist items', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      bullets: ['[x] Klaar', '[ ] Open'],
      listStyle: ListStyle.checklist,
      showChecklistProgress: true,
    );
    await tester.pumpWidget(
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
}
