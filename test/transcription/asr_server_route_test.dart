// De providerkant van de serverroute (#2524): route- en profielkeuze
// in prefs, en de enginefabriek die een geconfigureerd profiel aan een
// AsrServerEngine koppelt — en expliciet níét als het profiel incompleet
// is (geen stille serverroute).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_engine_factory.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/state/transcription_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const loopbackProfile = AsrServerProfile(
    enabled: true,
    mode: AsrServerMode.loopback,
    baseUrl: 'http://127.0.0.1:8080',
  );

  group('transcriptionRouteProvider', () {
    test('standaard lokaal; een keuze persisteert', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(transcriptionRouteProvider), 'local');
      await c.read(transcriptionRouteProvider.notifier).set('server');
      expect(c.read(transcriptionRouteProvider), 'server');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(transcriptionRouteKey), 'server');
    });

    test('een opgeslagen keuze wordt geladen', () async {
      SharedPreferences.setMockInitialValues({transcriptionRouteKey: 'server'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(transcriptionRouteProvider);
      // De async _load landt op de echte event loop van een unit test.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(transcriptionRouteProvider), 'server');
    });
  });

  group('asrServerProfileProvider', () {
    test('set() schrijft een herleesbare JSON-blob', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(asrServerProfileProvider), const AsrServerProfile());
      await c.read(asrServerProfileProvider.notifier).set(loopbackProfile);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(asrServerProfileKey);
      expect(raw, isNotNull);
      expect(
        AsrServerProfile.fromJson(
          Map<String, Object?>.from(jsonDecode(raw!) as Map),
        ),
        loopbackProfile,
      );
    });

    test('een opgeslagen profiel komt terug na rebuild', () async {
      SharedPreferences.setMockInitialValues({
        asrServerProfileKey: jsonEncode(loopbackProfile.toJson()),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(asrServerProfileProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(asrServerProfileProvider), loopbackProfile);
    });

    test(
      'kapotte opgeslagen JSON laat de default intact (fail-closed)',
      () async {
        SharedPreferences.setMockInitialValues({asrServerProfileKey: '{kapot'});
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c.read(asrServerProfileProvider);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(c.read(asrServerProfileProvider), const AsrServerProfile());
      },
    );
  });

  group('transcriptionEngineProvider', () {
    test('server + bruikbaar profiel levert een AsrServerEngine', () async {
      SharedPreferences.setMockInitialValues({
        transcriptionRouteKey: 'server',
        asrServerProfileKey: jsonEncode(loopbackProfile.toJson()),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(transcriptionRouteProvider);
      c.read(asrServerProfileProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(transcriptionEngineProvider), isA<AsrServerEngine>());
    });

    test('server zónder bruikbaar profiel schakelt nooit stilletjes', () async {
      SharedPreferences.setMockInitialValues({transcriptionRouteKey: 'server'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(transcriptionRouteProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final engine = c.read(transcriptionEngineProvider);
      expect(engine, isNot(isA<AsrServerEngine>()));
    });
  });

  test('de fabriek bouwt een engine met platformtransport en -lezer', () {
    final engine = createAsrServerEngine(loopbackProfile);
    expect(engine, isA<AsrServerEngine>());
    expect(engine.kind, EngineKind.batchServer);
    expect(engine.profile, loopbackProfile);
  });
}
