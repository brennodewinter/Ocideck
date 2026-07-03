import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late String deckPath;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = Directory.systemTemp.createTempSync('export_dialog_smoke');
    deckPath = '${tempDir.path}/demo.md';
    File(deckPath).writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\n---\n\n# Demo\n\n- a\n',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              onPressed: () => ExportDialog.show(
                context,
                deckPath: deckPath,
                slides: const [],
                themeProfile: const ThemeProfile(),
                projectPath: tempDir.path,
                exportService: ExportService(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('ExportDialog.show renders the dialog', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await openDialog(tester);

    expect(find.byType(ExportDialog), findsOneWidget);
    // De kwaliteitskeuze is ingeklapt tot de kop wordt aangetikt.
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    await tester.tap(find.text('Afbeeldingskwaliteit (PDF)'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
  });

  testWidgets('toggling the compressed segment keeps the dialog rendered', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await openDialog(tester);

    await tester.tap(find.text('Afbeeldingskwaliteit (PDF)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gecomprimeerd'));
    await tester.pumpAndSettle();

    expect(find.byType(ExportDialog), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
  });
}
