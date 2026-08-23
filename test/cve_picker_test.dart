import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cve_hit.dart';
import 'package:ocideck/services/cve_search_service.dart';
import 'package:ocideck/widgets/dialogs/cve_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A source that returns one fixed hit — the picker is tested without network.
class _FakeSource implements CveSource {
  @override
  Future<List<CveHit>> search(String query) async => const [
    CveHit(
      id: 'CVE-2021-44228',
      description: 'Log4Shell',
      cvssScore: 10.0,
      cvssSeverity: 'CRITICAL',
    ),
  ];
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('disabled by default: points to the settings toggle', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({}); // allowCveLookup false
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => CvePicker.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Instellingen'), findsOneWidget);
    // No search field while disabled.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('enabled: searches and returns the chosen CVE id', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'allowCveLookup': true,
      'app_consent_accepted': true,
    });
    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await CvePicker.show(
                    context,
                    service: CveSearchService([_FakeSource()]),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // let the settings/consent providers load
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Enabled → a search field is shown.
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2021-44228');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('CVE-2021-44228'), findsOneWidget);
    await tester.tap(find.textContaining('CVE-2021-44228'));
    await tester.pumpAndSettle();
    expect(picked, 'CVE-2021-44228');
  });
}
