import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/import_failure.dart';
import 'package:ocideck/services/import/pipeline/import_task.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/widgets/dialogs/presentation_import_progress_dialog.dart';

/// #875 — het enkelvoudige annuleerbare voortgangsvenster. Dit is de
/// widget/integratietest die het issue vraagt: het venster verwerkt invoer
/// (een tik op **Stoppen**) terwijl de import nog loopt, en levert dan een
/// geannuleerde uitkomst.
void main() {
  /// Bouw een scherm met één knop die het venster opent en zijn uitkomst in
  /// [sink] legt zodra het sluit.
  Future<void> pumpOpener(
    WidgetTester tester,
    void Function(PreparedImportResult) sink, {
    required Future<PreparedImportResult> Function(
      void Function(double, String) report,
      ImportCancelToken cancel,
    )
    task,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                sink(
                  await PresentationImportProgressDialog.run(
                    context,
                    fileName: 'plan.pptx',
                    task: task,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  testWidgets('toont voortgang en verwerkt Stoppen tijdens de import', (
    tester,
  ) async {
    PreparedImportResult? captured;
    var reachedCancel = false;
    // De taak blijft hangen tot de gebruiker annuleert — dat is precies het
    // venster waarin de UI moet blíjven reageren.
    await pumpOpener(
      tester,
      (r) => captured = r,
      task: (report, cancel) async {
        report(0.3, 'Slides classificeren…');
        await cancel.whenCancelled;
        reachedCancel = true;
        return const PreparedImportResult.cancelled();
      },
    );

    // Het venster staat, met titel, voortgangsbalk en de melding.
    expect(find.text('plan.pptx'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Slides classificeren…'), findsOneWidget);

    // Invoer wordt verwerkt terwijl de import nog loopt: de tik op Stoppen komt
    // aan, de taak ziet de annulering, en het venster sluit met die uitkomst.
    await tester.tap(find.text('Stoppen'));
    await tester.pumpAndSettle();
    expect(reachedCancel, isTrue);
    expect(captured?.wasCancelled, isTrue);
    expect(find.text('plan.pptx'), findsNothing);
  });

  testWidgets('toont de foutmelding in het venster en sluit pas na Sluiten', (
    tester,
  ) async {
    PreparedImportResult? captured;
    await pumpOpener(
      tester,
      (r) => captured = r,
      task: (report, cancel) async {
        report(0.5, 'Formaat herkennen…');
        return const PreparedImportResult.failed(ImportFailure('nee'));
      },
    );
    await tester.pumpAndSettle();

    // Het venster sluit niet: het toont de fout met technische detail (in een
    // SelectableText zodat de gebruiker kan kopiëren) en een Sluiten-knop.
    expect(find.text('plan.pptx'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Sluiten'), findsOneWidget);

    // Sluiten sluit het venster met de mislukte uitkomst.
    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.wasCancelled, isFalse);
    expect(captured!.failure, isNotNull);
    expect(find.text('plan.pptx'), findsNothing);
  });
}
