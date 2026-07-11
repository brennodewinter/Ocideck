import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/findings_summary_spec.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/management_summary.dart';
import 'package:ocideck/widgets/dialogs/management_summary_dialog.dart';

void main() {
  testWidgets('renders totals, scope coverage and standards used', (
    tester,
  ) async {
    final summary = ManagementSummary(
      severities: FindingsSummarySpec.fromSeverities('', const [
        Cvss4Severity.critical,
        Cvss4Severity.low,
      ]),
      standards: const ['WSTG', 'PTES'],
      scopeObjectCount: 3,
      scopeTestedCount: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ManagementSummaryDialog.show(context, summary),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2'), findsWidgets); // total findings = 2
    expect(find.textContaining('2 / 3'), findsOneWidget); // scope coverage
    expect(find.textContaining('WSTG, PTES'), findsOneWidget); // standards
  });
}
