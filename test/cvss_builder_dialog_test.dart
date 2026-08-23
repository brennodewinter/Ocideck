import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/widgets/dialogs/cvss_builder_dialog.dart';

/// The reusable CVSS builder dialog seeds from a vector, shows a live score, and
/// returns a Base-only vector on "Toepassen".
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('returns the seeded base vector on Toepassen', (tester) async {
    const seed =
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await CvssBuilderDialog.show(
                  context,
                  initialVector: seed,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The base score is shown (9.3 · Critical for the seeded vector).
    expect(find.textContaining('9.3'), findsWidgets);

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(Cvss4.parseVector(result!).score, 9.3);
  });

  testWidgets('shows a context score when the scope object is rated', (
    tester,
  ) async {
    const seed =
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => CvssBuilderDialog.show(
                context,
                initialVector: seed,
                cia: const CiaRating(
                  confidentiality: CiaLevel.low,
                  integrity: CiaLevel.low,
                  availability: CiaLevel.low,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Base 9.3 and the CIA-weighted context 8.9 are both shown.
    expect(find.textContaining('9.3'), findsWidgets);
    expect(find.textContaining('8.9'), findsWidgets);
  });
}
