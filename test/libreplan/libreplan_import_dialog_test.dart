import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/libreplan_import_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget tests for the LibrePlan import dialog. The dialog is a
/// `ConsumerStatefulWidget` that reads `settingsProvider` and
/// `deckProvider`; the import path itself is covered by the unit tests in
/// `libreplan_import_test.dart`. Here we verify the dialog renders, that the
/// checkboxes toggle, and that the import button is disabled when no
/// slide type is selected.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders title and all slide-type checkboxes', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LibreplanImportDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(LibreplanImportDialog), findsOneWidget);
    expect(find.text('LibrePlan importeren'), findsOneWidget);
    // All eight checkboxes should be visible and checked by default.
    expect(find.text('Gantt-planning'), findsOneWidget);
    expect(find.text('WBS (hiërarchie)'), findsOneWidget);
    expect(find.text('Projectstatus (cockpit)'), findsOneWidget);
    expect(find.text('Milestones (tijdlijn)'), findsOneWidget);
    expect(find.text('Kritieke pad (flow)'), findsOneWidget);
    expect(find.text('Resources (tabel)'), findsOneWidget);
    expect(find.text('Timesheet (tabel)'), findsOneWidget);
    expect(find.text('Resourcebelasting (grafiek)'), findsOneWidget);
  });

  testWidgets('import button is enabled when at least one type is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LibreplanImportDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Import button should be enabled (all checkboxes on by default).
    final importButton = find.ancestor(
      of: find.text('Importeren'),
      matching: find.byType(ElevatedButton),
    );
    final importBtnWidget = tester.widget<ElevatedButton>(importButton);
    expect(importBtnWidget.onPressed, isNotNull);
  });

  testWidgets('unchecking all disables the import button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LibreplanImportDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Uncheck all checkboxes by tapping each CheckboxListTile.
    for (final label in const [
      'Gantt-planning',
      'WBS (hiërarchie)',
      'Projectstatus (cockpit)',
      'Milestones (tijdlijn)',
      'Kritieke pad (flow)',
      'Resources (tabel)',
      'Timesheet (tabel)',
      'Resourcebelasting (grafiek)',
    ]) {
      await tester.tap(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(CheckboxListTile),
        ),
      );
      await tester.pump();
    }

    final importButton = find.ancestor(
      of: find.text('Importeren'),
      matching: find.byType(ElevatedButton),
    );
    final importBtnWidget = tester.widget<ElevatedButton>(importButton);
    expect(importBtnWidget.onPressed, isNull);
  });

  testWidgets('cancel closes the dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LibreplanImportDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(find.byType(LibreplanImportDialog), findsNothing);
  });
}
