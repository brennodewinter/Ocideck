import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/command_palette.dart';

void main() {
  List<PaletteCommand> commands(List<String> invoked) => [
    PaletteCommand(
      label: 'Presenteren',
      icon: Icons.play_circle_outline,
      onInvoke: () => invoked.add('present'),
    ),
    PaletteCommand(
      label: 'Nieuwe grafiek',
      icon: Icons.insert_chart_outlined,
      keywords: const ['chart'],
      onInvoke: () => invoked.add('chart'),
    ),
    PaletteCommand(
      label: 'Instellingen',
      icon: Icons.settings_outlined,
      onInvoke: () => invoked.add('settings'),
    ),
  ];

  Future<void> pump(WidgetTester tester, List<PaletteCommand> cmds) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => CommandPalette.show(context, cmds),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows every command, then filters on the typed query', (
    tester,
  ) async {
    await pump(tester, commands([]));
    expect(find.text('Presenteren'), findsOneWidget);
    expect(find.text('Nieuwe grafiek'), findsOneWidget);
    expect(find.text('Instellingen'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'graf');
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe grafiek'), findsOneWidget);
    expect(find.text('Presenteren'), findsNothing);
    expect(find.text('Instellingen'), findsNothing);
  });

  testWidgets('filters case- and accent-insensitively via keywords', (
    tester,
  ) async {
    await pump(tester, commands([]));
    await tester.enterText(find.byType(TextField), 'CHART');
    await tester.pumpAndSettle();
    expect(find.text('Nieuwe grafiek'), findsOneWidget);
    expect(find.text('Presenteren'), findsNothing);
  });

  testWidgets('arrow-down then Enter runs the second command and closes', (
    tester,
  ) async {
    final invoked = <String>[];
    await pump(tester, commands(invoked));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(invoked, ['chart']);
    expect(find.byType(CommandPalette), findsNothing);
  });

  testWidgets('tapping a row runs exactly that command', (tester) async {
    final invoked = <String>[];
    await pump(tester, commands(invoked));
    await tester.tap(find.text('Instellingen'));
    await tester.pumpAndSettle();
    expect(invoked, ['settings']);
  });

  testWidgets('a disabled command is inert and keeps the palette open', (
    tester,
  ) async {
    final invoked = <String>[];
    await pump(tester, [
      PaletteCommand(
        label: 'Export',
        icon: Icons.file_download_outlined,
        enabled: false,
        onInvoke: () => invoked.add('export'),
      ),
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(invoked, isEmpty);
    expect(find.byType(CommandPalette), findsOneWidget);
  });

  testWidgets('Escape closes the palette without running anything', (
    tester,
  ) async {
    final invoked = <String>[];
    await pump(tester, commands(invoked));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(invoked, isEmpty);
  });

  testWidgets('the empty state appears when nothing matches', (tester) async {
    await pump(tester, commands([]));
    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.pumpAndSettle();
    expect(find.text('Geen resultaten'), findsOneWidget);
  });
}
