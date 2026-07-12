import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/services/scope_coverage.dart';
import 'package:ocideck/widgets/dialogs/scope_coverage_dialog.dart';

/// Behaviour tests for the scope-coverage dialog: it either reports "no gaps"
/// (an all-clear) or lists each in-scope object that is neither tested nor
/// referenced by a finding, labelled with its object type.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<void> pump(WidgetTester tester, List<ScopeGap> gaps) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ScopeCoverageDialog(gaps: gaps)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty gap list shows the all-clear message', (tester) async {
    await pump(tester, const []);

    expect(find.text('Geen dekkingsgaten'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('each gap is listed with its object and type label', (
    tester,
  ) async {
    await pump(tester, const [
      ScopeGap(object: 'https://app.voorbeeld', type: ScopeObjectType.web),
      ScopeGap(object: '10.0.0.1', type: ScopeObjectType.infra),
    ]);

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('https://app.voorbeeld'), findsOneWidget);
    expect(find.text('10.0.0.1'), findsOneWidget);
    // Subtitles carry the Dutch type labels.
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('Infrastructuur'), findsOneWidget);
    // The all-clear message is not shown when there are gaps.
    expect(find.text('Geen dekkingsgaten'), findsNothing);
  });

  testWidgets('show() opens the dialog and the close action dismisses it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ScopeCoverageDialog.show(context, const []),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ScopeCoverageDialog), findsOneWidget);

    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(ScopeCoverageDialog), findsNothing);
  });
}
