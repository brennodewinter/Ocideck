import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/package_password_dialog.dart';

/// Behaviour tests for the encrypted-package password prompt. Uses a throwaway
/// test password (no real credential is involved): the dialog returns the typed
/// value on unlock, null on cancel, disables unlock while empty, surfaces the
/// retry error, and toggles password visibility.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  // Opens the dialog from a button and records the Future's result.
  Future<String?> openAndReturn(
    WidgetTester tester, {
    bool retry = false,
    required Future<void> Function(WidgetTester) interact,
  }) async {
    String? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await PackagePasswordDialog.show(
                  context,
                  retry: retry,
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact(tester);
    await tester.pumpAndSettle();
    expect(done, isTrue, reason: 'the dialog should have closed');
    return result;
  }

  testWidgets('unlock is disabled until a password is typed', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackagePasswordDialog())),
    );
    await tester.pumpAndSettle();

    ElevatedButton unlock() => tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Ontgrendelen'),
    );
    expect(unlock().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'geheim123');
    await tester.pump();
    expect(unlock().onPressed, isNotNull);
  });

  testWidgets('retry surfaces the "wrong password" error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PackagePasswordDialog(retry: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Onjuist wachtwoord. Probeer het opnieuw.'),
      findsOneWidget,
    );
  });

  testWidgets('unlocking returns the typed password', (tester) async {
    final result = await openAndReturn(
      tester,
      interact: (tester) async {
        await tester.enterText(find.byType(TextField), 'geheim123');
        await tester.pump();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Ontgrendelen'));
      },
    );

    expect(result, 'geheim123');
  });

  testWidgets('cancelling returns null', (tester) async {
    final result = await openAndReturn(
      tester,
      interact: (tester) async {
        await tester.tap(find.byType(TextButton));
      },
    );

    expect(result, isNull);
  });

  testWidgets('the visibility toggle unobscures the field', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackagePasswordDialog())),
    );
    await tester.pumpAndSettle();

    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().obscureText, isTrue);

    await tester.tap(find.byTooltip('Wachtwoord tonen'));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });
}
