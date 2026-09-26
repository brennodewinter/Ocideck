import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/state/ai_status_provider.dart';
import 'package:ocideck/state/elearning_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nep-transport: nooit netwerk. Dezelfde seam als in
/// welcome_status_test.dart — de versiecheck zelf doet geen fetch zolang
/// `updateChecksEnabled` uit staat, dus de service-naad hoeft hier niet
/// vervangen te worden.
class _FakeTransport implements AiHttpTransport {
  @override
  Future<AiHttpResult> send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 60),
  }) async => const AiHttpResult(200, '{}');
}

Future<void> _pumpWelcome(WidgetTester tester, {String? latestSeen}) async {
  SharedPreferences.setMockInitialValues({
    'app_consent_accepted': true,
    'updateCheckLatestSeen': ?latestSeen,
  });
  FlutterSecureStorage.setMockInitialValues({});
  AppLocalizations.setActiveLanguageCode('nl');
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiHttpTransportProvider.overrideWithValue(_FakeTransport()),
        elearningEnabledProvider.overrideWithValue(false),
      ],
      child: const OciDeckApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

/// Het lampje naast het versienummer — identificeerbaar aan het icoon in zijn
/// eigen formaat (de pijl komt op het scherm niet anders voor).
Finder _badge() => find.byWidgetPredicate(
  (w) => w is Icon && w.icon == Icons.arrow_circle_up_outlined && w.size == 11,
);

Finder _tip(String prefix) => find.byWidgetPredicate(
  (w) => w is Tooltip && (w.message ?? '').startsWith(prefix),
);

void main() {
  group('versiebadge op het openscherm', () {
    testWidgets('nog nooit gecheckt → grijs lampje dat naar Over wijst', (
      tester,
    ) async {
      await _pumpWelcome(tester);

      expect(_badge(), findsOneWidget);
      expect(_tip('Nog niet gecontroleerd'), findsOneWidget);

      // Tik op het grijze lampje: de instellingen openen op het Over-tabblad,
      // waar de automatische controle aan kan.
      await tester.tap(_badge());
      await tester.pumpAndSettle();
      expect(find.text('Nieuwe versies'), findsOneWidget);
    });

    testWidgets('nieuwere release bekend → amber lampje', (tester) async {
      await _pumpWelcome(tester, latestSeen: '99.0.0');

      expect(_badge(), findsOneWidget);
      expect(_tip('OciDeck 99.0.0 is beschikbaar'), findsOneWidget);
    });

    testWidgets('actueel → bewust geen lampje', (tester) async {
      await _pumpWelcome(tester, latestSeen: '0.0.1');

      expect(_badge(), findsNothing);
      expect(_tip('Nog niet gecontroleerd'), findsNothing);
      expect(_tip('OciDeck'), findsNothing);
    });
  });
}
