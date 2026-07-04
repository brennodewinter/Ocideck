import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/consent_provider.dart';
import 'package:ocideck/widgets/dialogs/consent_dialog.dart';
import 'package:ocideck/widgets/language_flag.dart';
import 'package:ocideck/widgets/privacy_statement_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled EUPL licence', () {
    test('loads and strips its SPDX/comment header', () async {
      // Reset: een eerder (gerandomiseerd) gedraaide widgettest kan de memo
      // in een fake-async-zone gestart hebben; die future completeert hier
      // nooit meer. Vers laden maakt deze test volgorde-onafhankelijk.
      PrivacyStatementContent.resetLicenseCacheForTest();
      final text = await PrivacyStatementContent.loadFullLicense();
      // The HTML-comment header (with the SPDX line) is removed…
      expect(text.contains('SPDX-License-Identifier'), isFalse);
      // …and the actual licence body is present.
      expect(text.trimLeft(), startsWith('# European Union Public Licence'));
      expect(text, contains('EUPL'));
    });
  });

  group('ConsentDialog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ProviderContainer> pumpDialog(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: ConsentDialog())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    ElevatedButton acceptButton(WidgetTester tester) =>
        tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Akkoord gaan'),
        );

    testWidgets('accept stays disabled until the box is ticked', (
      tester,
    ) async {
      await pumpDialog(tester);

      expect(acceptButton(tester).onPressed, isNull);

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(acceptButton(tester).onPressed, isNotNull);
    });

    testWidgets('accepting records consent', (tester) async {
      final container = await pumpDialog(tester);
      expect(container.read(consentProvider).hasAccepted, isFalse);

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Akkoord gaan'));
      await tester.pumpAndSettle();

      expect(container.read(consentProvider).hasAccepted, isTrue);
    });
  });

  group('language flags', () {
    testWidgets('Frisian uses the bundled flag image', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: languageFlag('fy'))),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/flag_fy.png',
      );
    });

    testWidgets('other languages use a flag emoji, not an image', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: languageFlag('en'))),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('🇬🇧'), findsOneWidget);
    });

    testWidgets('an option row shows the flag beside the name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: languageOptionRow('fy', 'Frysk'))),
      );
      expect(find.text('Frysk'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
