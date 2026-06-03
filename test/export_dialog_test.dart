import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';

void main() {
  testWidgets('export dialog offers a normal/compressed image choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            slides: const [],
            themeProfile: const ThemeProfile(),
            projectPath: null,
            exportService: ExportService(),
          ),
        ),
      ),
    );

    // The image-quality selector and both options must be visible on open.
    expect(find.text('Afbeeldingskwaliteit (PDF)'), findsOneWidget);
    expect(
      find.widgetWithText(SegmentedButton<bool>, 'Normaal'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(SegmentedButton<bool>, 'Gecomprimeerd'),
      findsOneWidget,
    );
    expect(find.text('Exporteer als PDF'), findsOneWidget);
  });
}
