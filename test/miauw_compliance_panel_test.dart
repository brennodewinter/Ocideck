import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/miauw_compliance.dart';
import 'package:ocideck/services/miauw_eis_catalog.dart';
import 'package:ocideck/state/miauw_compliance_provider.dart';
import 'package:ocideck/widgets/dialogs/miauw_compliance_panel.dart';

EisResult _res(String id, EisStatus status, {String? reason}) => EisResult(
  entry: MiauwEisCatalog.instance.byId(id)!,
  status: status,
  waiverReason: reason,
);

void main() {
  testWidgets('renders EIS rows and warns when a foundational EIS is waived', (
    tester,
  ) async {
    final result = MiauwComplianceResult([
      _res('1.1', EisStatus.uitgesloten, reason: 'Geen digitale aanlevering'),
      _res('1.6', EisStatus.voldaan),
      _res('4.2', EisStatus.open),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [miauwComplianceProvider.overrideWithValue(result)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MiauwCompliancePanel.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Rows for the seeded requirements are shown, grouped by part.
    expect(find.textContaining('1.6 ·'), findsOneWidget);
    expect(find.textContaining('4.2 ·'), findsOneWidget);
    // A waived foundational EIS (1.1) surfaces the warning + carries its reason.
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    expect(find.text('Geen digitale aanlevering'), findsOneWidget);
  });
}
