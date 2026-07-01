import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/chart_editor.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';

Widget _markdownHost({
  required String content,
  required bool Function(String) onApply,
  void Function()? onExit,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1400,
          height: 2800,
          child: MarkdownDeckEditor(
            initialContent: content,
            onApply: onApply,
            parseError: false,
            onExitMarkdown: onExit ?? () {},
          ),
        ),
      ),
    ),
  );
}

Widget _chartHost(Slide slide, ValueChanged<Slide> onUpdate) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1400,
        height: 2800,
        child: ChartEditor(
          slide: slide,
          onUpdate: onUpdate,
          themeAnimationDurationMs: kThemeDefaultAnimationDurationMs,
        ),
      ),
    ),
  );
}

Slide _chartSlide(ChartSpec spec) =>
    Slide.create(SlideType.chart).copyWith(customMarkdown: spec.toBlock());

Future<void> _sendControl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  group('MarkdownDeckEditor', () {
    testWidgets('edited text is forwarded to onApply on Toepassen', (
      tester,
    ) async {
      String? applied;
      await tester.pumpWidget(
        _markdownHost(
          content: '# Titel\n\nhello',
          onApply: (md) {
            applied = md;
            return true;
          },
        ),
      );

      await tester.enterText(
        find.byType(TextField).last,
        '# Titel\n\nhello world',
      );
      await tester.pump();

      await tester.tap(find.text('Toepassen'));
      await tester.pumpAndSettle();

      expect(applied, '# Titel\n\nhello world');
    });

    testWidgets('Controleren reveals the validation summary bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _markdownHost(content: '# Titel\n\ntekst', onApply: (_) => true),
      );

      expect(find.text('Controleren'), findsOneWidget);
      await tester.tap(find.text('Controleren'));
      await tester.pumpAndSettle();

      // A Material summary bar with a check / warning icon now appears.
      final hasOk = find
          .byIcon(Icons.check_circle_outline)
          .evaluate()
          .isNotEmpty;
      final hasWarn = find
          .byIcon(Icons.warning_amber_outlined)
          .evaluate()
          .isNotEmpty;
      expect(hasOk || hasWarn, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl+H opens the find bar in replace mode', (tester) async {
      await tester.pumpWidget(
        _markdownHost(content: 'alpha beta alpha', onApply: (_) => true),
      );

      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      await _sendControl(tester, LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownFindBar), findsOneWidget);
    });
  });

  group('ChartEditor', () {
    testWidgets('switching chart type emits an updated slide', (tester) async {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['A', 'B'],
        series: <ChartSeries>[
          ChartSeries(name: 'Waarde', data: [10, 20]),
        ],
      );
      var updated = _chartSlide(spec);

      await tester.pumpWidget(_chartHost(updated, (slide) => updated = slide));
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<ChartType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lijn').last);
      await tester.pumpAndSettle();

      expect(ChartSpec.parse(updated.customMarkdown).type, ChartType.line);
    });

    testWidgets('editing a value cell emits the new data', (tester) async {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['A', 'B'],
        series: <ChartSeries>[
          ChartSeries(name: 'Waarde', data: [10, 20]),
        ],
      );
      var updated = _chartSlide(spec);

      await tester.pumpWidget(_chartHost(updated, (slide) => updated = slide));
      await tester.pump();

      await tester.enterText(find.byKey(const ValueKey('v-0-0-0')), '99');
      await tester.pump();

      expect(
        ChartSpec.parse(updated.customMarkdown).series.single.data.first,
        99,
      );
    });

    testWidgets('adding a row grows the grid and emits', (tester) async {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['A', 'B'],
        series: <ChartSeries>[
          ChartSeries(name: 'Waarde', data: [10, 20]),
        ],
      );
      var updated = _chartSlide(spec);

      await tester.pumpWidget(_chartHost(updated, (slide) => updated = slide));
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Rij'));
      await tester.pump();

      expect(ChartSpec.parse(updated.customMarkdown).x.length, 3);
    });

    testWidgets('adding a series grows the columns and emits', (tester) async {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['A', 'B'],
        series: <ChartSeries>[
          ChartSeries(name: 'Waarde', data: [10, 20]),
        ],
      );
      var updated = _chartSlide(spec);

      await tester.pumpWidget(_chartHost(updated, (slide) => updated = slide));
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reeks'));
      await tester.pump();

      expect(ChartSpec.parse(updated.customMarkdown).series.length, 2);
    });

    testWidgets('changing the title emits the updated title', (tester) async {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['A'],
        series: <ChartSeries>[
          ChartSeries(name: 'Waarde', data: [10]),
        ],
      );
      var updated = _chartSlide(spec);

      await tester.pumpWidget(_chartHost(updated, (slide) => updated = slide));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Omzet 2026');
      await tester.pump();

      expect(ChartSpec.parse(updated.customMarkdown).title, 'Omzet 2026');
    });

    testWidgets('min bound field emits a minBound for a bar chart', (
      tester,
    ) async {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['A'],
        series: <ChartSeries>[
          ChartSeries(name: 'Waarde', data: [10]),
        ],
      );
      var updated = _chartSlide(spec);

      await tester.pumpWidget(_chartHost(updated, (slide) => updated = slide));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('chart-min-bound')),
        '5',
      );
      await tester.pump();

      expect(ChartSpec.parse(updated.customMarkdown).minBound, 5);
    });
  });
}
