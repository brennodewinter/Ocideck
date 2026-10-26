// De live-server-opt-in (#2525): de sessieconsent-rij die alleen
// verschijnt als het profiel een live-endpoint heeft én de
// protocolproef dat endpoint aantoonbaar `vosk-ws-1` hoorde. Geen
// bewijs = geen checkbox; een dode optie is erger dan geen optie.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/dialogs/live_server_opt_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Profile extends AsrServerProfileNotifier {
  _Profile(this.profile);

  final AsrServerProfile profile;

  @override
  AsrServerProfile build() => profile;
}

const enabledLive = AsrServerProfile(
  enabled: true,
  mode: AsrServerMode.loopback,
  baseUrl: 'http://127.0.0.1:8080',
  liveUrl: 'ws://127.0.0.1:2700',
);

Widget app(LiveServerOptIn child, AsrServerProfile profile) {
  return ProviderScope(
    overrides: [asrServerProfileProvider.overrideWith(() => _Profile(profile))],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'een uitgeschakeld of live-loos profiel toont niets en proeft niet',
    (tester) async {
      var probes = 0;
      await tester.pumpWidget(
        app(
          LiveServerOptIn(
            sourcesLabel: 'de microfoon',
            onChanged: (_) {},
            probeRunner: (_) async {
              probes++;
              return const AsrServerProbe(
                status: AsrProbeStatus.reachable,
                detail: 'x',
              );
            },
          ),
          const AsrServerProfile(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(probes, 0);
    },
  );

  testWidgets('een mislukte proef toont de reden, geen stille checkbox', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        LiveServerOptIn(
          sourcesLabel: 'de microfoon',
          onChanged: (_) {},
          probeRunner: (_) async => const AsrServerProbe(
            status: AsrProbeStatus.unreachable,
            detail: 'endpoint spreekt geen vosk-ws-1',
          ),
        ),
        enabledLive,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('niet beschikbaar'), findsOneWidget);
    expect(
      find.textContaining('endpoint spreekt geen vosk-ws-1'),
      findsOneWidget,
    );
  });

  testWidgets(
    'een bewezen proef toont de consent — vinkje levert host aan ouder',
    (tester) async {
      final states = <LiveOptInState>[];
      await tester.pumpWidget(
        app(
          LiveServerOptIn(
            sourcesLabel: 'de microfoon',
            onChanged: states.add,
            probeRunner: (_) async => const AsrServerProbe(
              status: AsrProbeStatus.reachable,
              detail: 'vosk-ws-1',
            ),
          ),
          enabledLive,
        ),
      );
      await tester.pumpAndSettle();

      // De checkbox noemt de host én wat er live heen gaat.
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.textContaining('127.0.0.1'), findsWidgets);
      expect(find.textContaining('de microfoon'), findsOneWidget);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(states.single.chosen, isTrue);
      expect(states.single.host, '127.0.0.1');
    },
  );

  testWidgets('de consent-rij past ook op 200% tekstschaal', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: app(
          LiveServerOptIn(
            sourcesLabel: 'de microfoon',
            onChanged: (_) {},
            probeRunner: (_) async => const AsrServerProbe(
              status: AsrProbeStatus.reachable,
              detail: 'vosk-ws-1',
            ),
          ),
          enabledLive,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('de profiel-JSON van een live-profiel overleeft zijn prefs-ronde', () {
    final back = AsrServerProfile.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(enabledLive.toJson())) as Map,
      ),
    );
    expect(back, enabledLive);
  });
}
