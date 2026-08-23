import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
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
}
