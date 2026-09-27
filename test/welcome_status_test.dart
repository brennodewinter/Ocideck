import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ai_settings.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/ai_client_service.dart';
import 'package:ocideck/services/ai_security_gate.dart';
import 'package:ocideck/state/ai_status_provider.dart';
import 'package:ocideck/state/elearning_provider.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/state/storage_status_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nep-transport: nooit netwerk, alleen een programmeerbare uitkomst voor
/// `GET /models`. Dezelfde seam als de provider-test.
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

/// OciServe-notifier met een vaste beginstate — de statuschip leest alleen
/// `settings.enabled` en `status`, verdere calls doet deze test niet.
class _FixedOciServe extends OciServeNotifier {
  _FixedOciServe(this._state);

  final OciServeState _state;

  @override
  OciServeState build() => _state;
}

/// De lampjes identificeren zich via hun tooltip — `Icons.school_outlined`
/// staat óók op de "Mijn cursussen"-knop, dus het icoon alleen is geen bewijs.
Finder _tip(String prefix) => find.byWidgetPredicate(
  (w) => w is Tooltip && (w.message ?? '').startsWith(prefix),
);

/// Nep-probe voor de opslaglampjes: de uitkomst is een parameter, nooit
/// netwerk. `calls` bewijst of een verbinding überhaupt getest is.
class _StorageProbe {
  _StorageProbe(this.result);

  final bool result;
  final calls = <String>[];

  Future<bool> call(StorageConnection c, dynamic secrets) async {
    calls.add(c.id);
    return result;
  }
}

Map<String, Object> _connectionPrefs(List<StorageConnection> connections) => {
  'storageConnections': StorageConnection.encodeList(connections),
};

Future<void> _pumpWelcome(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool elearningEnabled = false,
  OciServeState? ociServeState,
  _StorageProbe? storageProbe,
}) async {
  // Consent al geaccepteerd, anders staat _ConsentWelcomePane voor het
  // welkomscherm (met ook een "Welkom bij OciDeck"-titel — valkuil).
  SharedPreferences.setMockInitialValues({
    'app_consent_accepted': true,
    ...prefs,
  });
  FlutterSecureStorage.setMockInitialValues({});
  AppLocalizations.setActiveLanguageCode('nl');
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiHttpTransportProvider.overrideWithValue(_FakeTransport()),
        elearningEnabledProvider.overrideWithValue(elearningEnabled),
        if (ociServeState != null)
          ociServeProvider.overrideWith(() => _FixedOciServe(ociServeState)),
        if (storageProbe != null)
          storageProbeProvider.overrideWithValue(
            (c, secrets) => storageProbe.call(c, secrets),
          ),
      ],
      child: const OciDeckApp(),
    ),
  );
  await tester.pumpAndSettle();
  // De endpoint-ping van de statusprovider landt asynchroon.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

Map<String, Object> _aiPrefs(AiSettings settings) => {
  'aiSettings': jsonEncode(settings.toJson()),
};

void main() {
  group('welkomscherm-statuscentrum', () {
    testWidgets('alle uitbreidingen uit → geen lampjes', (tester) async {
      await _pumpWelcome(tester);

      expect(_tip('AI:'), findsNothing);
      expect(_tip('eLearning:'), findsNothing);
    });

    testWidgets('AI aan en bereikbaar → groen lampje', (tester) async {
      await _pumpWelcome(
        tester,
        prefs: _aiPrefs(
          const AiSettings(
            enabled: true,
            mode: AiBackendMode.local,
            baseUrl: 'http://127.0.0.1:11434/v1',
            model: 'testmodel',
          ),
        ),
      );

      expect(_tip('AI: functioneert'), findsOneWidget);
      expect(_tip('eLearning:'), findsNothing);
    });

    testWidgets('AI aan maar niet ingesteld → aandacht-lampje met reden', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        prefs: _aiPrefs(const AiSettings(enabled: true)),
      );

      expect(_tip('AI: niet volledig ingesteld'), findsOneWidget);
    });

    testWidgets('eLearning-module aan + server ingesteld → lampje', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        elearningEnabled: true,
        ociServeState: const OciServeState(
          settings: OciServeSettings(
            enabled: true,
            baseUrl: 'https://learn.example',
          ),
          status: OciServeStatus.signedOut,
        ),
      );

      // Nog nooit aangemeld: server wel ingesteld, account niet, niet
      // ingelogd — en geen bereikbaarheidsclaim, want daarover is niets
      // bekend.
      final tips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .where(
            (t) =>
                (t.message ?? '').contains(
                  'eLearning-account: niet ingesteld',
                ) &&
                (t.message ?? '').contains('eLearning: niet ingelogd'),
          )
          .toList();
      expect(tips, hasLength(1));
      expect(tips.single.message, isNot(contains('bereikbaar')));
      expect(_tip('AI:'), findsNothing);
    });

    testWidgets('eLearning-module uit → lampje weg, ook met server ingesteld', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        elearningEnabled: false,
        ociServeState: const OciServeState(
          settings: OciServeSettings(
            enabled: true,
            baseUrl: 'https://learn.example',
          ),
          status: OciServeStatus.signedOut,
        ),
      );

      expect(_tip('eLearning'), findsNothing);
    });

    testWidgets('eLearning-module aan maar server uit → lampje met ketting', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        elearningEnabled: true,
        ociServeState: const OciServeState(
          settings: OciServeSettings(enabled: false),
          status: OciServeStatus.signedOut,
        ),
      );

      // De module staat aan maar de verbinding is niet ingericht: juist dan
      // toont het lampje waar het hapert — beide "niet ingesteld"-regels.
      final tips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .where(
            (t) =>
                (t.message ?? '').contains(
                  'eLearning-server: niet ingesteld',
                ) &&
                (t.message ?? '').contains(
                  'eLearning-account: niet ingesteld',
                ) &&
                (t.message ?? '').contains('eLearning: niet ingelogd'),
          )
          .toList();
      expect(tips, hasLength(1));
    });

    testWidgets('eLearning bewaarde login → account ingesteld in de tip', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        elearningEnabled: true,
        ociServeState: const OciServeState(
          settings: OciServeSettings(
            enabled: true,
            baseUrl: 'https://learn.example',
          ),
          status: OciServeStatus.signedOut,
          hasStoredLogin: true,
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message ?? '').contains('eLearning-account: ingesteld'),
        ),
        findsOneWidget,
      );
    });

    /// De tip van het eLearning-lampje die álle verwachte regels bevat.
    Finder elearningTip({required String server, required String account}) =>
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message ?? '').contains('eLearning-server: $server') &&
              (w.message ?? '').contains('eLearning: $account'),
        );

    testWidgets('eLearning ingelogd → server- én accountregel in de tip', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        elearningEnabled: true,
        ociServeState: const OciServeState(
          settings: OciServeSettings(
            enabled: true,
            baseUrl: 'https://learn.example',
          ),
          status: OciServeStatus.authenticated,
          account: OciServeAccount(id: 'u1'),
        ),
      );

      expect(
        elearningTip(server: 'bereikbaar', account: 'ingelogd'),
        findsOneWidget,
      );
    });

    testWidgets('eLearning server weg → beide regels vertellen dat', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        elearningEnabled: true,
        ociServeState: const OciServeState(
          settings: OciServeSettings(
            enabled: true,
            baseUrl: 'https://learn.example',
          ),
          status: OciServeStatus.signedOut,
          errorCode: 'network',
        ),
      );

      expect(
        elearningTip(server: 'niet bereikbaar', account: 'niet ingelogd'),
        findsOneWidget,
      );
    });

    testWidgets('tik op eLearning-lampje opent Instellingen op Integraties', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        elearningEnabled: true,
        ociServeState: const OciServeState(
          settings: OciServeSettings(enabled: true),
          status: OciServeStatus.signedOut,
        ),
      );

      await tester.tap(
        elearningTip(server: 'niet ingesteld', account: 'niet ingelogd'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);
      // Het integraties-tabblad is geselecteerd: de eLearning-kaart staat er.
      expect(find.text('Integraties'), findsWidgets);
    });

    testWidgets('lokale opslag → meteen groen, zonder probe', (tester) async {
      final probe = _StorageProbe(true);
      await _pumpWelcome(
        tester,
        prefs: _connectionPrefs([
          const LocalConnection(id: 'l1', name: 'Schijf', path: '/tmp/decks'),
        ]),
        storageProbe: probe,
      );

      expect(_tip('Schijf: bereikbaar'), findsOneWidget);
      expect(probe.calls, isEmpty);
    });

    testWidgets('remote opslag + probe geslaagd → groen lampje op naam', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        prefs: _connectionPrefs([
          const WebdavConnection(
            id: 'w1',
            name: 'Kantoor',
            server: WebdavServer(
              baseUrl: 'https://cloud.example',
              username: 'aisha',
            ),
          ),
        ]),
        storageProbe: _StorageProbe(true),
      );

      expect(_tip('Kantoor: bereikbaar'), findsOneWidget);
    });

    testWidgets('remote opslag + probe mislukt → niet-bereikbaar lampje', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        prefs: _connectionPrefs([
          const WebdavConnection(
            id: 'w1',
            name: 'Kantoor',
            server: WebdavServer(
              baseUrl: 'https://cloud.example',
              username: 'aisha',
            ),
          ),
        ]),
        storageProbe: _StorageProbe(false),
      );

      expect(_tip('Kantoor: niet bereikbaar'), findsOneWidget);
    });

    testWidgets(
      'remote opslag zonder naam → afgeleide omschrijving als label',
      (tester) async {
        await _pumpWelcome(
          tester,
          prefs: _connectionPrefs([
            const WebdavConnection(
              id: 'w1',
              name: '',
              server: WebdavServer(
                baseUrl: 'https://cloud.example',
                username: 'aisha',
              ),
            ),
          ]),
          storageProbe: _StorageProbe(true),
        );

        // fallbackLabel is de host — zelfde weergave als het opslag-tabblad.
        expect(_tip('cloud.example: bereikbaar'), findsOneWidget);
      },
    );

    testWidgets('twee verbindingen → één lampje met beide regels in de tip', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        prefs: _connectionPrefs([
          const LocalConnection(id: 'l1', name: 'Schijf', path: '/tmp/decks'),
          const WebdavConnection(
            id: 'w1',
            name: 'Kantoor',
            server: WebdavServer(
              baseUrl: 'https://cloud.example',
              username: 'aisha',
            ),
          ),
        ]),
        storageProbe: _StorageProbe(true),
      );

      // Eén tooltip, niet twee lampjes — beide regels in dezelfde ballon.
      final tips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .where(
            (t) =>
                (t.message ?? '').contains('Schijf: bereikbaar') &&
                (t.message ?? '').contains('Kantoor: bereikbaar'),
          )
          .toList();
      expect(tips, hasLength(1));
    });

    testWidgets('tik op het opslaglampje opent Instellingen op Opslag', (
      tester,
    ) async {
      await _pumpWelcome(
        tester,
        prefs: _connectionPrefs([
          const LocalConnection(id: 'l1', name: 'Schijf', path: '/tmp/decks'),
        ]),
        storageProbe: _StorageProbe(true),
      );

      await tester.tap(_tip('Schijf: bereikbaar'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);
      // Het opslag-tabblad is geselecteerd: de verbindingslijst staat er.
      expect(find.text('Opslag'), findsWidgets);
    });
  });
}
