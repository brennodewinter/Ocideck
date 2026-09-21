import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/utils/error_snackbar.dart';

/// The copyable error SnackBar: it shows the message, and its Kopiëren action
/// puts that exact text on the clipboard and confirms — so a failure can be
/// forwarded without retyping.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('shows the message and copies it to the clipboard', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showErrorSnackBar(
                ScaffoldMessenger.of(context),
                context.l10n,
                'Export mislukt: de schijf is vol.',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump(); // schedule the SnackBar
    await tester.pump(const Duration(milliseconds: 750)); // finish its entrance
    expect(find.text('Export mislukt: de schijf is vol.'), findsOneWidget);

    await tester.tap(find.text('Kopiëren'));
    await tester.pump();
    expect(copied, ['Export mislukt: de schijf is vol.']);

    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Gekopieerd'), findsOneWidget);
  });

  /// #2149: een snackbar met actie was blijvend (persist volgt `action !=
  /// null`) en had geen sluitknop — hij ging nooit weg. [showActionSnackBar]
  /// is de gedeelde plek die `persist: false` en een duur afdwingt; het thema
  /// levert het sluiticoon.
  testWidgets(
    'actie-snackbar heeft duur, is niet blijvend en sluit via het icoon',
    (tester) async {
      var actionRan = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showActionSnackBar(
                  ScaffoldMessenger.of(context),
                  'Verwijzing verwijderd',
                  'Ongedaan maken',
                  () => actionRan = true,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Verwijzing verwijderd'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.persist, isFalse);
      expect(snackBar.duration, const Duration(seconds: 4));

      // Het sluiticoon uit het thema sluit de melding zonder de actie.
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.byType(SnackBar), findsNothing);
      expect(actionRan, isFalse);
    },
  );

  testWidgets('actie-snackbar verdwijnt vanzelf binnen zijn duur', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showActionSnackBar(
                ScaffoldMessenger.of(context),
                'Verwijzing verwijderd',
                'Ongedaan maken',
                () {},
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byType(SnackBar), findsOneWidget);

    // Voorbij de duur + animatie moet hij weg zijn — ook mét actieknop.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byType(SnackBar), findsNothing);
  });
}
