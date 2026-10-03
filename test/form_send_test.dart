// Een inzending naar de server sturen vanaf de invulpagina (FORM_INTAKE.md §6.6, §5.8): de
// bevestiging, het versturen, het aankomstbericht en het bewijs; en alles wat mis kan gaan, met
// de zin die zegt wat de invuller kan doen.

import 'dart:convert';
import 'dart:typed_data';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/intake/intake_client.dart';
import 'package:ocideck/services/form/intake/intake_http.dart';
import 'package:ocideck/widgets/forms/form_export_support.dart';
import 'package:ocideck/widgets/forms/form_fill_view.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/fake_intake_server.dart';
import 'support/intake_test_form.dart';
import 'support/pump_until.dart';

const String frontMatter = '---\ntitle: Kookboek\n---\n';

const String leeg = '''<!-- form id=kook version=1 rules=1 lang=nl -->
Welkom.

<!-- field id=naam type=text required max-chars=40 -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

final String gevuld = leeg.replaceFirst(
  '<!-- answer -->\n<!-- /field id=naam -->',
  '<!-- answer -->\nSari\n<!-- /field id=naam -->',
);

/// Wat de proef gebruikt: de organisator, de server en de uitnodiging, met een bundel die pas in
/// 2099 verloopt (de invulpagina gebruikt de echte klok).
class _World {
  _World._(this.organiser, this.server, this.variant);

  final IntakeTestOrganiser organiser;
  final FakeIntakeServer server;
  final IntakeVariant variant;

  static Future<_World> create({
    String host = 'intake.example.org',
    String? bundleHost,
    IntakeFormState state = IntakeFormState.open,
  }) async {
    final organiser = await IntakeTestOrganiser.create();
    final variant = await organiser.variant(
      frontMatter + leeg,
      host: bundleHost ?? host,
      expires: '2099-12-31',
      closes: '2099-12-31',
      now: DateTime.now(),
    );
    final server = FakeIntakeServer(host: host)
      ..clock = (() => DateTime.utc(2026, 11, 3, 9, 30, 12));
    server.publish(kTestFid, [variant], state: state);
    return _World._(organiser, server, variant);
  }

  InviteLink get invite => organiser.invite();
}

class _Spy {
  _Spy(this.world);

  final _World world;
  final List<({String name, Uint8List bytes})> saved = [];
  bool saveThrows = false;
  Completer<void>? saveGate;
  String? saveAs = 'kook-abcdef.receipt.json';
  FormBundlePins pins = const FormBundlePins();
  int pinWrites = 0;
  final List<String> forgotten = [];
  ({String bundle, String fingerprint})? memory;
  InviteLink? invite;
  String? published = frontMatter + leeg;

  FormExportSupport support({IntakeHttp? http, bool withSend = true}) {
    memory ??= (
      bundle: world.variant.bundleText,
      fingerprint: world.organiser.signing.fingerprint,
    );
    invite ??= world.invite;
    return FormExportSupport(
      frontMatter: frontMatter,
      clientVersion: '0.6.13',
      readImage: (_) async => null,
      pickPublished: () async => null,
      save: (name, bytes) async {
        await saveGate?.future;
        if (saveThrows) throw const FormatException('schijf vol');
        saved.add((name: name, bytes: bytes));
        return saveAs;
      },
      recall: (_) => published,
      remember: (_, text) => published = text,
      seal: FormSealSupport(
        pickBundle: () async => null,
        readPins: () async => pins,
        writePins: (next) async {
          pins = next;
          pinWrites++;
        },
        recall: (_) => memory,
        remember: (_, bundle, fingerprint) =>
            memory = (bundle: bundle, fingerprint: fingerprint),
        forget: (spec) {
          forgotten.add(spec.id);
          memory = null;
        },
      ),
      send: withSend
          ? FormSendSupport(
              recall: (_) => invite,
              client: IntakeClient(http ?? world.server),
            )
          : null,
    );
  }
}

class _Host extends StatefulWidget {
  const _Host(this.initial, {required this.support});

  final String initial;
  final FormExportSupport support;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String body = widget.initial;

  @override
  Widget build(BuildContext context) => FormFillView(
    body: body,
    onChanged: (text, _) => setState(() => body = text),
    export: widget.support,
  );
}

Future<void> pump(
  WidgetTester tester,
  FormExportSupport support, {
  String language = 'nl',
}) async {
  AppLocalizations.setActiveLanguageCode(language);
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: _Host(leeg, support: support)),
    ),
  );
  await tester.pump();
}

Finder text(String s) => find.text(s);

/// De invuller vult in en kiest Versturen… en bevestigt dan in het venster.
Future<void> fillAndSend(WidgetTester tester, {bool confirm = true}) async {
  await tester.enterText(find.byType(TextField).first, 'Sari');
  await tester.pump();
  final button = find.byKey(const Key('send-to-server'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await pumpUntil(
    tester,
    () => find.byKey(const Key('send-confirm')).evaluate().isNotEmpty,
    reason: 'het bevestigingsvenster kwam niet',
  );
  if (confirm) await tester.tap(find.byKey(const Key('send-go')));
}

Future<void> waitFor(WidgetTester tester, Finder finder) => pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  reason: 'wachtte op ${finder.describeMatch(Plurality.one)}',
);

void main() {
  late _World world;
  late _Spy spy;

  setUp(() async {
    world = await _World.create();
    spy = _Spy(world);
  });

  group('de knop', () {
    testWidgets('staat er voor een formulier dat via een uitnodiging kwam', (
      tester,
    ) async {
      await pump(tester, spy.support());
      expect(find.byKey(const Key('send-to-server')), findsOneWidget);
      expect(text('Versturen…'), findsOneWidget);
      expect(text('Inzending opslaan als zip…'), findsOneWidget);
      expect(text('Verzegeld opslaan…'), findsOneWidget);
    });

    testWidgets('staat er niet zonder ondersteuning voor een server', (
      tester,
    ) async {
      await pump(tester, spy.support(withSend: false));
      expect(find.byKey(const Key('send-to-server')), findsNothing);
      expect(text('Verzegeld opslaan…'), findsOneWidget);
    });

    testWidgets(
      'staat er niet als het formulier niet via een uitnodiging kwam',
      (tester) async {
        spy.invite = null;
        final support = FormExportSupport(
          frontMatter: frontMatter,
          readImage: (_) async => null,
          pickPublished: () async => null,
          save: (_, _) async => null,
          recall: (_) => null,
          remember: (_, _) {},
          send: FormSendSupport(
            recall: (_) => null,
            client: IntakeClient(world.server),
          ),
        );
        await pump(tester, support);
        expect(find.byKey(const Key('send-to-server')), findsNothing);
      },
    );
  });

  group('versturen', () {
    testWidgets(
      'vraagt eerst naar wie, en stuurt dan: een inzending die de organisator opent',
      (tester) async {
        await pump(tester, spy.support());
        await fillAndSend(tester, confirm: false);
        expect(
          find.text(
            'Naar de redactie van Indo IT Kookboek-team versturen? Je inzending gaat versleuteld naar intake.example.org; alleen Indo IT Kookboek-team kunnen hem openen.',
          ),
          findsOneWidget,
        );
        // Tot de invuller bevestigt is er niets gevraagd.
        expect(world.server.requests, isEmpty);

        await tester.tap(find.byKey(const Key('send-go')));
        await waitFor(tester, find.byKey(const Key('send-arrived')));

        expect(
          find.text(
            'Aangekomen op 2026-11-03 09:30:12 UTC. Heb je vragen, schrijf dan naar redactie@example.org.',
          ),
          findsOneWidget,
        );
        final held = world.server.submissions.values.single;
        final opened = await tester.runAsync(
          () => openSealedPackage(
            held.bytes,
            identities: [world.organiser.identity],
            expectedFormId: 'kook',
            expectedFormVersion: 1,
          ),
        );
        expect(
          (opened! as FormUnsealed).package.submission,
          frontMatter + gevuld,
        );
      },
    );

    testWidgets(
      'de server krijgt de token, het formulier en alleen de hash van het geheim',
      (tester) async {
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-arrived')));
        final request = world.server.requests.single;
        expect(request.method, 'PUT');
        expect(request.headers['intake-token'], kTestInvite);
        expect(request.headers['intake-form'], kTestFid);
        expect(request.headers['intake-withdrawal'], hasLength(64));
        final held = world.server.submissions.values.single;
        expect(request.target, endsWith(world.server.submissions.keys.single));
        expect(held.withdrawalHash, request.headers['intake-withdrawal']);
      },
    );

    testWidgets(
      'het geheim van het bewijs hoort bij de hash die de server kreeg',
      (tester) async {
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-arrived')));
        await tester.tap(find.byKey(const Key('send-receipt')));
        await waitFor(tester, find.byKey(const Key('send-saved')));
        final saved = spy.saved.single;
        expect(
          saved.name,
          matches(RegExp(r'^kook-[a-z2-7]{6}\.receipt\.json$')),
        );
        final receipt = parseIntakeReceipt(utf8.decode(saved.bytes))!;
        expect(receipt.host, 'intake.example.org');
        expect(receipt.fid, kTestFid);
        expect(receipt.sid, world.server.submissions.keys.single);
        expect(
          withdrawalSecretHash(receipt.withdrawalSecret),
          world.server.submissions.values.single.withdrawalHash,
        );
        expect(
          receipt.note.ciphertextSha256,
          world.server.submissions.values.single.hash,
        );
        expect(
          text('Bewijs opgeslagen als kook-abcdef.receipt.json.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'het bewijs wordt niet bewaard als de invuller het schrijven annuleert',
      (tester) async {
        spy.saveAs = null;
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-arrived')));
        await tester.tap(find.byKey(const Key('send-receipt')));
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('send-saved')), findsNothing);
      },
    );

    testWidgets('een schijf die weigert is één melding', (tester) async {
      spy.saveThrows = true;
      await pump(tester, spy.support());
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-arrived')));
      await tester.tap(find.byKey(const Key('send-receipt')));
      await waitFor(tester, find.byKey(const Key('send-saved')));
      expect(text('Het bewijs kon niet worden opgeslagen.'), findsOneWidget);
    });

    testWidgets(
      'het controlegetal is het begin van de hash die de server kreeg',
      (tester) async {
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-arrived')));
        final hash = world.server.submissions.values.single.hash;
        expect(
          find.text(
            'Het controlegetal van wat de server ontving begint met ${hash.substring(0, 12)}. Noem het als je erover schrijft.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'het venster sluit niet door ernaast te tikken, ook niet tijdens het versturen',
      (tester) async {
        world.server.gate = Completer<void>();
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await tester.pump();
        expect(text('De inzending wordt verstuurd…'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        expect(text('De inzending wordt verstuurd…'), findsOneWidget);
        world.server.gate!.complete();
        await waitFor(tester, find.byKey(const Key('send-arrived')));
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        expect(find.byKey(const Key('send-arrived')), findsOneWidget);
      },
    );

    testWidgets(
      'zolang het bewijs wordt opgeslagen kan het niet nog een keer; daarna weer wel',
      (tester) async {
        spy.saveGate = Completer<void>();
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-arrived')));
        await tester.tap(find.byKey(const Key('send-receipt')));
        await tester.pump();
        TextButton button() =>
            tester.widget<TextButton>(find.byKey(const Key('send-receipt')));
        expect(button().onPressed, isNull);
        spy.saveGate!.complete();
        await waitFor(tester, find.byKey(const Key('send-saved')));
        expect(button().onPressed, isNotNull);
        spy.saveGate = null;
        await tester.tap(find.byKey(const Key('send-receipt')));
        await pumpUntil(
          tester,
          () => spy.saved.length == 2,
          reason: 'het bewijs werd niet nog een keer opgeslagen',
        );
      },
    );

    testWidgets('annuleren in de bevestiging stuurt niets', (tester) async {
      await pump(tester, spy.support());
      await fillAndSend(tester, confirm: false);
      await tester.tap(text('Annuleren'));
      await tester.pumpAndSettle();
      expect(world.server.requests, isEmpty);
      expect(world.server.submissions, isEmpty);
    });

    testWidgets('de vingerafdruk staat onder Details', (tester) async {
      await pump(tester, spy.support());
      await fillAndSend(tester, confirm: false);
      await tester.tap(find.byKey(const Key('send-details')));
      await tester.pumpAndSettle();
      expect(
        find.text(formatFingerprint(world.organiser.signing.fingerprint)),
        findsOneWidget,
      );
    });

    testWidgets(
      'een formulier met een fout wordt niet verstuurd: de pagina wijst het aan',
      (tester) async {
        await pump(tester, spy.support());
        final button = find.byKey(const Key('send-to-server'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('send-confirm')), findsNothing);
        expect(world.server.requests, isEmpty);
      },
    );

    testWidgets(
      'de pins worden bewaard zodra de bundel is geloofd, ook als het versturen niet lukt',
      (tester) async {
        world.server.failWith = IntakeHttpFailure.network;
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-failure')));
        expect(spy.pinWrites, 1);
        expect(
          spy.pins.seqFor(kTestFid, world.organiser.signing.fingerprint),
          3,
        );
      },
    );
  });

  group('als het niet lukt', () {
    String failure(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('send-failure'))).data!;

    testWidgets(
      'geen verbinding: de zin noemt de server; opnieuw proberen verstuurt dezelfde inzending één keer',
      (tester) async {
        world.server.failWith = IntakeHttpFailure.timeout;
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-failure')));
        expect(
          failure(tester),
          'Geen verbinding met intake.example.org. Controleer je internetverbinding en probeer het later opnieuw.',
        );
        final firstSid = world.server.requests.single.target;
        world.server.failWith = null;
        await tester.tap(find.byKey(const Key('send-retry')));
        await waitFor(tester, find.byKey(const Key('send-arrived')));
        // Hetzelfde nummer: de server heeft één inzending, niet twee.
        expect(world.server.requests.last.target, firstSid);
        expect(world.server.submissions, hasLength(1));
      },
    );

    testWidgets('een adres dat OciDeck niet benadert', (tester) async {
      world.server.failWith = IntakeHttpFailure.hostRefused;
      await pump(tester, spy.support());
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      expect(failure(tester), 'OciDeck maakt geen verbinding met dit adres.');
    });

    testWidgets('een ingetrokken uitnodiging', (tester) async {
      world.server.publish(kTestFid, [world.variant], token: null);
      await pump(tester, spy.support());
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      expect(
        failure(tester),
        'De uitnodiging is niet meer geldig: de organisator heeft hem ingetrokken of vervangen. Vraag om een nieuwe uitnodiging.',
      );
    });

    testWidgets('een gesloten formulier', (tester) async {
      world.server.publish(kTestFid, [
        world.variant,
      ], state: IntakeFormState.closed);
      await pump(tester, spy.support());
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      expect(
        failure(tester),
        'Dit formulier is gesloten voor nieuwe inzendingen. Neem contact op met de organisator.',
      );
    });

    testWidgets('een inzending die de server te groot vindt', (tester) async {
      world.server.maxPackageBytes = 10;
      await pump(tester, spy.support());
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      expect(
        failure(tester),
        'De server neemt deze inzending niet aan omdat ze te groot is. Haal een foto weg of maak er een kleiner.',
      );
    });

    testWidgets('een drukke server', (tester) async {
      world.server.rateLimited = 1;
      await pump(tester, spy.support());
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      expect(failure(tester), 'De server is druk. Probeer het later opnieuw.');
    });

    testWidgets('een server die iets anders bevestigt dan er is verstuurd', (
      tester,
    ) async {
      // Het antwoord gaat over een andere hash dan wat is verstuurd.
      await pump(tester, _Spy(world).support(http: _LyingServer(world.server)));
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      expect(
        failure(tester),
        'De server bevestigde iets anders dan wat je verstuurde. Probeer het opnieuw, of sla de verzegelde inzending op en mail die.',
      );
    });

    testWidgets('een andere weigering', (tester) async {
      world.server.overrides.clear();
      final broken = _Teapot(world.server);
      await pump(tester, _Spy(world).support(http: broken));
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      expect(
        failure(tester),
        'De server weigerde de inzending. Probeer het later opnieuw, of sla de verzegelde inzending op en mail die.',
      );
    });

    testWidgets(
      'zolang het verzegelde bestand wordt opgeslagen is de knop uit',
      (tester) async {
        world.server.failWith = IntakeHttpFailure.network;
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-failure')));
        spy.saveGate = Completer<void>();
        await tester.tap(find.byKey(const Key('send-save-sealed')));
        await tester.pump();
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('send-save-sealed')))
              .onPressed,
          isNull,
        );
        spy.saveGate!.complete();
        await waitFor(tester, find.byKey(const Key('send-saved')));
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('send-save-sealed')))
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'de verzegelde inzending bewaren om te mailen: dezelfde bytes die zijn geprobeerd',
      (tester) async {
        world.server.failWith = IntakeHttpFailure.network;
        await pump(tester, spy.support());
        await fillAndSend(tester);
        await waitFor(tester, find.byKey(const Key('send-failure')));
        spy.saveAs = 'kook-abcdef.zip.age';
        await tester.tap(find.byKey(const Key('send-save-sealed')));
        await waitFor(tester, find.byKey(const Key('send-saved')));
        expect(
          text(
            'Verzegeld opgeslagen als kook-abcdef.zip.age, alleen te openen door: Indo IT Kookboek-team.',
          ),
          findsOneWidget,
        );
        final saved = spy.saved.single;
        expect(saved.name, endsWith('.zip.age'));
        final sent = world.server.requests.single.body;
        expect(saved.bytes, sent);
      },
    );

    testWidgets('Sluiten laat de antwoorden in het formulier staan', (
      tester,
    ) async {
      world.server.failWith = IntakeHttpFailure.network;
      await pump(tester, spy.support());
      await fillAndSend(tester);
      await waitFor(tester, find.byKey(const Key('send-failure')));
      await tester.tap(text('Sluiten'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send-failure')), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Sari',
      );
    });
  });

  group('wat de bundel zegt', () {
    testWidgets(
      'een bundel voor het adres van een andere server wordt niet verzonden',
      (tester) async {
        final other = await _World.create(bundleHost: 'elders.example.org');
        final otherSpy = _Spy(other);
        await pump(tester, otherSpy.support());
        await tester.enterText(find.byType(TextField).first, 'Sari');
        await tester.pump();
        final button = find.byKey(const Key('send-to-server'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await waitFor(
          tester,
          find.text(
            'Het formulier hoort niet bij de server uit de uitnodiging. Vraag de organisator om een nieuwe uitnodiging.',
          ),
        );
        expect(other.server.requests, isEmpty);
        expect(otherSpy.forgotten, ['kook']);
        expect(find.byKey(const Key('send-confirm')), findsNothing);
      },
    );

    testWidgets('een verlopen bundel', (tester) async {
      final w = await _World.create();
      final expired = await w.organiser.variant(
        frontMatter + leeg,
        host: 'intake.example.org',
        expires: '2020-01-02',
        closes: '2099-12-31',
        now: DateTime.utc(2020, 1, 1),
      );
      final s = _Spy(w)
        ..memory = (
          bundle: expired.bundleText,
          fingerprint: w.organiser.signing.fingerprint,
        );
      await pump(tester, s.support());
      await tester.enterText(find.byType(TextField).first, 'Sari');
      await tester.pump();
      final button = find.byKey(const Key('send-to-server'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await waitFor(
        tester,
        find.text(
          'Deze bundel is verlopen. Vraag de organisator om een nieuwe.',
        ),
      );
      expect(w.server.requests, isEmpty);
    });

    testWidgets('een bundel die de sluitingsdag al voorbij is', (tester) async {
      final w = await _World.create();
      final closed = await w.organiser.variant(
        frontMatter + leeg,
        host: 'intake.example.org',
        expires: '2099-12-31',
        closes: '2020-01-01',
        now: DateTime.utc(2019, 12, 1),
      );
      final s = _Spy(w)
        ..memory = (
          bundle: closed.bundleText,
          fingerprint: w.organiser.signing.fingerprint,
        );
      await pump(tester, s.support());
      await tester.enterText(find.byType(TextField).first, 'Sari');
      await tester.pump();
      final button = find.byKey(const Key('send-to-server'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await waitFor(
        tester,
        find.text(
          'Dit formulier is gesloten: de laatste dag was 2020-01-01. Neem contact op met de organisator.',
        ),
      );
      expect(w.server.requests, isEmpty);
    });
  });

  group('in een andere taal', () {
    testWidgets('de zinnen volgen de taal van het programma', (tester) async {
      await pump(tester, spy.support(), language: 'en');
      expect(text('Send…'), findsOneWidget);
      await fillAndSend(tester, confirm: false);
      expect(
        find.text(
          'Send to the editors of Indo IT Kookboek-team? Your submission goes encrypted to intake.example.org; only Indo IT Kookboek-team can open it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('send-go')));
      await waitFor(tester, find.byKey(const Key('send-arrived')));
      expect(find.text('Your submission has arrived.'), findsOneWidget);
    });
  });
}

/// Een server die op elke upload antwoordt met een bericht over andere bytes.
class _LyingServer implements IntakeHttp {
  _LyingServer(this.inner);

  final FakeIntakeServer inner;

  @override
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  }) async {
    final real = await inner.send(
      method: method,
      url: url,
      headers: headers,
      body: body,
      maxResponseBytes: maxResponseBytes,
      timeout: timeout,
    );
    if (method != 'PUT') return real;
    final note = jsonDecode(utf8.decode(real.body)) as Map<String, Object?>;
    note['ciphertext_sha256'] = 'ab' * 32;
    return IntakeHttpResponse(
      statusCode: real.statusCode,
      body: Uint8List.fromList(utf8.encode(jsonEncode(note))),
    );
  }
}

/// Een server die op een upload met een rare status antwoordt.
class _Teapot implements IntakeHttp {
  _Teapot(this.inner);

  final FakeIntakeServer inner;

  @override
  Future<IntakeHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    List<int>? body,
    required int maxResponseBytes,
    required Duration timeout,
  }) async => method == 'PUT'
      ? FakeIntakeServer.raw(418, 'ik ben een theepot')
      : inner.send(
          method: method,
          url: url,
          headers: headers,
          body: body,
          maxResponseBytes: maxResponseBytes,
          timeout: timeout,
        );
}
