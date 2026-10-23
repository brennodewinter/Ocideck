// De ASR-serversectie uit #2514: profiel-editor, live poortuitslag, de
// verbindingstest zonder audio en de audiotest achter zijn eigen
// bevestigingsdialoog (§4.3). Het transport is een fake — er verlaat nooit
// iets het netwerk op in een test.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/transcription_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/settings_text_field.dart';
import 'package:ocideck/widgets/dialogs/settings/transcription_server_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'asr_server_engine_test.dart' show FakeTransport;

void main() {
  late FakeTransport transport;
  final sent = <String>{};

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    transport = FakeTransport();
    // De keychain is een platformkanaal — zonder handler blijft de call
    // in de test-zone hangen. Een lege sleutelbos is precies wat de sectie
    // hier nodig heeft.
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    sent.clear();
  });

  /// De testhaak: bouwt de engine op het fake-transport en noteert welke
  /// methode hem bereikt — "zonder audio" betekent GET zonder body.
  AsrServerEngine fakeEngine(
    AsrServerProfile profile,
    Future<String?> Function() keyReader,
  ) {
    return AsrServerEngine(
      profile: profile,
      transport: _NotingTransport(transport, sent),
      audioReader: (path) async => WebAssetStore.bytesFor(path) ?? Uint8List(0),
      apiKeyReader: keyReader,
    );
  }

  Widget app() => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TranscriptionServerSection(engineBuilder: fakeEngine),
        ),
      ),
    ),
  );

  /// Zet de sectie op een actief loopback-profiel: klasse, URL en de
  /// "Profiel actief"-schakelaar.
  Future<void> fillLoopback(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<AsrServerMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Op dit apparaat (loopback)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Serveradres (basis-URL)'),
      'http://127.0.0.1:8080',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiel actief'));
    await tester.pumpAndSettle();
  }

  testWidgets('zonder profiel staat de rusttoestand er: lokaal blijft lokaal', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      find.text('Geen server gekozen — transcriptie blijft lokaal.'),
      findsOneWidget,
    );
    expect(find.byType(SettingsSecretField), findsNothing);
  });

  testWidgets('poortlijn spiegelt het concept — uit, dan toegestaan', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<AsrServerMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Op dit apparaat (loopback)').last);
    await tester.pumpAndSettle();

    // Actief zonder endpoint: de poort benoemt wat er ontbreekt.
    await tester.tap(find.text('Profiel actief'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Endpoint ontbreekt of is ongeldig'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Serveradres (basis-URL)'),
      'http://127.0.0.1:8080',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Poort staat toe: verzoeken mogen vertrekken'),
      findsOneWidget,
    );
  });

  testWidgets('opslaan schrijft het profiel, nooit de sleutel', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillLoopback(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'API-sleutel'),
      'geheime-sleutel',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profiel opslaan'));
    await tester.pumpAndSettle();

    final raw = await SharedPreferences.getInstance().then(
      (p) => p.getString(asrServerProfileKey),
    );
    expect(raw, isNotNull);
    final saved = AsrServerProfile.fromJson(
      Map<String, Object?>.from(jsonDecode(raw!) as Map),
    );
    expect(saved.mode, AsrServerMode.loopback);
    expect(saved.enabled, isTrue);
    expect(saved.baseUrl, 'http://127.0.0.1:8080');
    // De sleutel staat nergens in het profiel — die hoort in de sleutelbos.
    expect(raw.contains('geheime'), isFalse);
  });

  testWidgets('de verbindingstest stuurt één GET en geen byte audio', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillLoopback(tester);

    await tester.tap(find.text('Verbinding testen (zonder audio)'));
    await tester.pumpAndSettle();

    expect(sent, {'GET'});
    expect(transport.method, 'GET');
    expect(transport.body, isNull);
    expect(
      find.text('Server bereikbaar en antwoordde als HTTP-server'),
      findsOneWidget,
    );
  });

  testWidgets('de audiotest vraagt eerst toestemming die de host benoemt', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillLoopback(tester);

    await tester.tap(find.text('Test met echte audio'));
    await tester.pumpAndSettle();

    // De dialoog benoemt de bestemming en wat er verstuurd wordt.
    expect(find.textContaining('127.0.0.1', findRichText: true), findsWidgets);
    expect(sent, isEmpty, reason: 'zonder bevestiging vertrekt er niets');

    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
  });

  testWidgets('na bevestiging vertrekt de stille WAV via de echte route', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await fillLoopback(tester);

    await tester.tap(find.text('Test met echte audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Versturen'));
    await tester.pumpAndSettle();

    expect(sent, {'POST'});
    expect(transport.url.toString(), contains('/inference'));
    // De multipart-body draagt de testaudio — de WAV-header is zichtbaar.
    expect(
      String.fromCharCodes(transport.body!.sublist(0, 200)),
      contains('audio.wav'),
    );
    expect(find.textContaining('leeg transcript'), findsOneWidget);
  });

  testWidgets('verwijderen maakt het profiel én de route weer leeg', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      asrServerProfileKey: jsonEncode(
        const AsrServerProfile(
          enabled: true,
          mode: AsrServerMode.loopback,
          baseUrl: 'http://127.0.0.1:8080',
        ).toJson(),
      ),
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Profiel verwijderen'));
    await tester.tap(find.text('Profiel verwijderen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Geen server gekozen — transcriptie blijft lokaal.'),
      findsOneWidget,
    );
    final raw = await SharedPreferences.getInstance().then(
      (p) => p.getString(asrServerProfileKey),
    );
    final saved = AsrServerProfile.fromJson(
      Map<String, Object?>.from(jsonDecode(raw!) as Map),
    );
    expect(saved.hasEndpoint, isFalse);
  });
}

/// Noteert de methode van elk verzoek en delegeert verder aan de
//  scriptbare [FakeTransport] uit de enginetests.
class _NotingTransport implements AsrTransport {
  _NotingTransport(this.inner, this.seen);

  final FakeTransport inner;
  final Set<String> seen;

  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = Duration.zero,
  }) {
    seen.add(method);
    return inner.send(
      method: method,
      url: url,
      strategy: strategy,
      body: body,
      headers: headers,
      timeout: timeout,
    );
  }
}
