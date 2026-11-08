import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/privacy_profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'DLP profiles enable scanning, persist policy and retain exceptions',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'privacyChecksEnabled': false,
        'privacyDisabledRules': ['email'],
      });
      AppLocalizations.setActiveLanguageCode('nl');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(settingsProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: PrivacyProfiles()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('privacycontrole staat uit'), findsOneWidget);
      await tester.tap(find.text('Export blokkeren'));
      await tester.pumpAndSettle();
      var settings = container.read(settingsProvider);
      expect(settings.privacyChecksEnabled, isTrue);
      expect(settings.privacyStrictSeverity, isTrue);
      expect(settings.privacyExportGate, PrivacyExportGate.block);
      expect(settings.privacyDisabledRules, contains('email'));
      expect(
        (await SharedPreferences.getInstance()).getString('privacyExportGate'),
        'block',
      );
      await tester.tap(find.text('Waarschuwen vóór export'));
      await tester.pumpAndSettle();
      settings = container.read(settingsProvider);
      expect(settings.privacyExportGate, PrivacyExportGate.warn);
      expect(settings.privacyStrictSeverity, isFalse);
      expect(settings.privacyDisabledRules, contains('email'));
    },
  );
}
