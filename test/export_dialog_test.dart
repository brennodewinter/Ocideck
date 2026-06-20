import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/quality_export_policy.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';

const _qualityWarning = SlideQualityResult([
  SlideQualityIssue(
    slideIndex: 0,
    kind: SlideQualityIssueKind.imageContrastUnverified,
    category: SlideQualityCategory.contrast,
    severity: MarkdownValidationSeverity.warning,
  ),
]);

const _qualityError = SlideQualityResult([
  SlideQualityIssue(
    slideIndex: 0,
    kind: SlideQualityIssueKind.textDensityCritical,
    category: SlideQualityCategory.textDensity,
    severity: MarkdownValidationSeverity.error,
  ),
]);

void main() {
  test('quality warnings require acknowledgement before export proceeds', () {
    final decision = const QualityExportPolicy().evaluate(_qualityWarning);
    expect(decision.allowed, isFalse);
    expect(decision.canAcknowledge, isTrue);
    expect(decision.warningCount, 1);
  });

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

  testWidgets('shows quality banner when issues are present', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            deckPath: '/tmp/deck.md',
            slides: const [],
            themeProfile: const ThemeProfile(),
            projectPath: null,
            exportService: ExportService(),
            qualityResult: _qualityWarning,
          ),
        ),
      ),
    );

    expect(find.textContaining('Slidekwaliteit'), findsOneWidget);
    expect(find.text('Bekijk meldingen…'), findsOneWidget);
  });

  testWidgets('blocks export UI when serious quality errors are enforced', (
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
            qualityResult: _qualityError,
            qualityPolicy: const QualityExportPolicy(blockOnErrors: true),
          ),
        ),
      ),
    );

    expect(
      find.text('Export geblokkeerd vanwege ernstige kwaliteitsproblemen.'),
      findsOneWidget,
    );
    expect(find.text('Exporteer als PDF'), findsNothing);
  });
}
