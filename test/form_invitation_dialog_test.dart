// Een uitnodiging openen (FORM_INTAKE.md §6.4, §6.6): de link plakken, het formulier ophalen en
// zien van wie het komt. Elke zin die zegt waarom het niet ging, en de twee momenten waarop de
// invuller kan oordelen.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/intake/intake_client.dart';
import 'package:ocideck/services/form/intake/intake_http.dart';
import 'package:ocideck/widgets/forms/form_invitation_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/fake_intake_server.dart';
import 'support/intake_test_form.dart';
import 'support/pump_until.dart';

final DateTime _now = DateTime.utc(2026, 11, 3);

void main() {
  FormInvitationChoice? choice;
  var closedWithout = false;
  FormBundlePins pinsRead = const FormBundlePins();
  int pinReads = 0;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    choice = null;
    closedWithout = false;
    pinReads = 0;
    pinsRead = const FormBundlePins();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  void clipboard(String? text) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return text == null ? null : <String, Object?>{'text': text};
          }
          return null;
        });
  }

  Future<void> show(
    WidgetTester tester,
    IntakeHttp http, {
    String? initialLink,
    String language = 'nl',
    DateTime? now,
  }) async {
    AppLocalizations.setActiveLanguageCode(language);
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                choice = await showFormInvitationDialog(
                  context,
                  client: IntakeClient(http),
                  readPins: () async {
                    pinReads++;
                    return pinsRead;
                  },
                  now: () => now ?? _now,
                  initialLink: initialLink,
                );
                closedWithout = choice == null;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<({FakeIntakeServer server, IntakeTestOrganiser organiser})> serve(
    WidgetTester tester,
    List<String> languages, {
    IntakeFormState state = IntakeFormState.open,
  }) async =>
      (await tester.runAsync(() => serverWith(languages, state: state)))!;

  Future<void> fetch(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('invitation-fetch')));
    await pumpUntil(
      tester,
      () =>
          find.byKey(const Key('invitation-open')).evaluate().isNotEmpty ||
          find.byKey(const Key('invitation-failure')).evaluate().isNotEmpty,
      reason: 'het formulier werd niet opgehaald',
    );
  }

  group('de link', () {
    testWidgets('zonder tekst staat er geen oordeel', (tester) async {
      await show(tester, FakeIntakeServer());
      expect(find.byKey(const Key('invitation-issue')), findsNothing);
      expect(find.byKey(const Key('invitation-host')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('invitation-fetch')))
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'een volledige link toont het adres en maakt het ophalen mogelijk',
      (tester) async {
        final f = await serve(tester, ['nl']);
        await show(tester, f.server);
        await tester.enterText(
          find.byKey(const Key('invitation-link')),
          f.organiser.invite().text,
        );
        await tester.pump();
        expect(
          find.text('Het formulier wordt opgehaald bij intake.example.org.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('invitation-fetch')))
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('een link zonder vingerafdruk gaat niet verder', (
      tester,
    ) async {
      final f = await serve(tester, ['nl']);
      await show(tester, f.server);
      final text = f.organiser.invite().text.replaceAll(
        RegExp('&fp=[a-z2-7]+'),
        '',
      );
      await tester.enterText(find.byKey(const Key('invitation-link')), text);
      await tester.pump();
      expect(
        find.text(
          'Deze link is niet compleet. Vraag de organisator om de volledige uitnodigingslink.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('invitation-fetch')))
            .onPressed,
        isNull,
      );
    });

    for (final c in <(String, String, String)>[
      (
        'een link zonder https',
        'http://forms.example.org/f/mfrggzdfmztwq2lknnwg23tpoa#api=x.example&fp=$_fp&t=nvqwy3dpoixxg5dfonzgc3tjnq',
        'De link moet met https beginnen.',
      ),
      (
        'iets wat geen link is',
        'hallo',
        'Dit is geen uitnodigingslink die OciDeck kent. Vraag de organisator om de volledige link.',
      ),
      (
        'een link met een slechte vingerafdruk',
        'https://forms.example.org/f/mfrggzdfmztwq2lknnwg23tpoa#api=x.example&fp=abc&t=nvqwy3dpoixxg5dfonzgc3tjnq',
        'Dit is geen uitnodigingslink die OciDeck kent. Vraag de organisator om de volledige link.',
      ),
    ]) {
      testWidgets(c.$1, (tester) async {
        await show(tester, FakeIntakeServer());
        await tester.enterText(find.byKey(const Key('invitation-link')), c.$2);
        await tester.pump();
        expect(find.text(c.$3), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('invitation-fetch')))
              .onPressed,
          isNull,
        );
      });
    }

    testWidgets(
      'de link van het klembord staat er al, en blijft te veranderen',
      (tester) async {
        final f = await serve(tester, ['nl']);
        clipboard(f.organiser.invite().text);
        await show(tester, f.server);
        await tester.pump();
        final field = tester.widget<TextField>(
          find.byKey(const Key('invitation-link')),
        );
        expect(field.controller!.text, f.organiser.invite().text);
        expect(find.byKey(const Key('invitation-host')), findsOneWidget);
      },
    );

    testWidgets(
      'een onvolledige uitnodiging van het klembord wordt ook overgenomen: de zin zegt wat ontbreekt',
      (tester) async {
        final f = await serve(tester, ['nl']);
        clipboard(
          f.organiser.invite().text.replaceAll(RegExp('&t=[a-z2-7]+'), ''),
        );
        await show(tester, f.server);
        await tester.pump();
        expect(find.byKey(const Key('invitation-issue')), findsOneWidget);
      },
    );

    for (final clip in <String?>[
      null,
      'dit is een boodschappenlijst',
      'https://example.org/gewone-pagina',
      'http://forms.example.org/f/mfrggzdfmztwq2lknnwg23tpoa#api=x.example',
    ]) {
      testWidgets(
        'wat geen uitnodiging lijkt op het klembord blijft daar ($clip)',
        (tester) async {
          clipboard(clip);
          await show(tester, FakeIntakeServer());
          await tester.pump();
          final field = tester.widget<TextField>(
            find.byKey(const Key('invitation-link')),
          );
          expect(field.controller!.text, isEmpty);
        },
      );
    }

    testWidgets('een meegegeven link slaat het klembord over', (tester) async {
      final f = await serve(tester, ['nl']);
      clipboard(
        'https://elders.example/f/mfrggzdfmztwq2lknnwg23tpoa#api=x.example&fp=${f.organiser.signing.fingerprint}&t=$kTestInvite',
      );
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('invitation-link')),
      );
      expect(field.controller!.text, f.organiser.invite().text);
    });

    testWidgets(
      'het klembord komt laat: wat de invuller al intikte blijft staan',
      (tester) async {
        final f = await serve(tester, ['nl']);
        final late = Completer<Map<String, Object?>?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.getData') return late.future;
              return null;
            });
        await show(tester, f.server);
        await tester.enterText(
          find.byKey(const Key('invitation-link')),
          'zelf',
        );
        late.complete({'text': f.organiser.invite().text});
        await tester.pump();
        await tester.pump();
        final field = tester.widget<TextField>(
          find.byKey(const Key('invitation-link')),
        );
        expect(field.controller!.text, 'zelf');
      },
    );

    testWidgets(
      'het klembord komt als het venster al dicht is: er gebeurt niets',
      (tester) async {
        final f = await serve(tester, ['nl']);
        final late = Completer<Map<String, Object?>?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.getData') return late.future;
              return null;
            });
        await show(tester, f.server);
        await tester.tap(find.text('Annuleren'));
        await tester.pumpAndSettle();
        late.complete({'text': f.organiser.invite().text});
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('het venster sluit niet door ernaast te tikken', (
      tester,
    ) async {
      await show(tester, FakeIntakeServer());
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(FormInvitationDialog), findsOneWidget);
    });

    testWidgets('het veld krijgt meteen de aandacht', (tester) async {
      await show(tester, FakeIntakeServer());
      final field = tester.widget<TextField>(
        find.byKey(const Key('invitation-link')),
      );
      expect(field.autofocus, isTrue);
    });

    testWidgets('het veld is niet slim: geen autocorrectie, geen suggesties', (
      tester,
    ) async {
      await show(tester, FakeIntakeServer());
      final field = tester.widget<TextField>(
        find.byKey(const Key('invitation-link')),
      );
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('Annuleren sluit zonder iets te kiezen', (tester) async {
      await show(tester, FakeIntakeServer());
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(closedWithout, isTrue);
      expect(find.byType(FormInvitationDialog), findsNothing);
    });
  });

  group('het formulier ophalen', () {
    testWidgets(
      'toont van wie het is, en geeft het sjabloon terug dat de invuller koos',
      (tester) async {
        final f = await serve(tester, ['nl']);
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await fetch(tester);
        expect(
          find.text('Formulier van Indo IT Kookboek-team'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('invitation-closed')), findsNothing);
        expect(
          find.byKey(const Key('invitation-variant-0')),
          findsNothing,
          reason: 'één taal: niets te kiezen',
        );
        await tester.tap(find.byKey(const Key('invitation-open')));
        await tester.pumpAndSettle();
        expect(choice!.variant.spec.lang, 'nl');
        expect(choice!.variant.template, templateIn('nl'));
        expect(choice!.opened.invite.fid, kTestFid);
        expect(pinReads, 1);
        expect(
          choice!.opened.pins.seqFor(kTestFid, f.organiser.signing.fingerprint),
          3,
        );
      },
    );

    testWidgets('de vingerafdruk staat onder Details, in groepjes van vier', (
      tester,
    ) async {
      final f = await serve(tester, ['nl']);
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      await tester.tap(find.byKey(const Key('invitation-details')));
      await tester.pumpAndSettle();
      expect(find.text('Server: intake.example.org'), findsOneWidget);
      expect(
        find.text(formatFingerprint(f.organiser.signing.fingerprint)),
        findsOneWidget,
      );
    });

    testWidgets('het sjabloon in de taal van het programma staat voorgekozen', (
      tester,
    ) async {
      final f = await serve(tester, ['nl', 'en']);
      await show(
        tester,
        f.server,
        initialLink: f.organiser.invite().text,
        language: 'en',
      );
      await fetch(tester);
      await tester.tap(find.byKey(const Key('invitation-open')));
      await tester.pumpAndSettle();
      expect(choice!.variant.spec.lang, 'en');
    });

    testWidgets(
      'en anders het eerste; de invuller kan een andere taal kiezen',
      (tester) async {
        final f = await serve(tester, ['en', 'de']);
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await fetch(tester);
        expect(find.text('English'), findsOneWidget);
        expect(find.text('Deutsch'), findsOneWidget);
        await tester.tap(find.byKey(const Key('invitation-variant-1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('invitation-open')));
        await tester.pumpAndSettle();
        expect(choice!.variant.spec.lang, 'de');
      },
    );

    testWidgets(
      'zonder een taal die past staat het eerste sjabloon voorgekozen',
      (tester) async {
        final f = await serve(tester, ['en', 'de']);
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await fetch(tester);
        await tester.tap(find.byKey(const Key('invitation-open')));
        await tester.pumpAndSettle();
        expect(choice!.variant.spec.lang, 'en');
      },
    );

    testWidgets(
      'een taal als nl-NL telt als nl, een onbekende code blijft zoals hij is',
      (tester) async {
        final f = await serve(tester, []);
        f.server.publish(kTestFid, [
          (await tester.runAsync(
            () => f.organiser.variant(templateIn('nl-NL')),
          ))!,
          (await tester.runAsync(
            () => f.organiser.variant(templateIn('xx'), seq: 4),
          ))!,
          (await tester.runAsync(
            () => f.organiser.variant(
              '<!-- form id=kook version=1 rules=1 -->\n# Inzending\n\n<!-- field id=naam type=text required -->\n**Naam**\n<!-- answer -->\n<!-- /field id=naam -->\n',
              seq: 5,
            ),
          ))!,
        ]);
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await fetch(tester);
        expect(find.text('Nederlands'), findsOneWidget);
        expect(find.text('xx'), findsOneWidget);
        expect(find.text('Onbekende taal'), findsOneWidget);
        // nl-NL is de taal van het programma: voorgekozen.
        await tester.tap(find.byKey(const Key('invitation-open')));
        await tester.pumpAndSettle();
        expect(choice!.variant.spec.lang, 'nl-NL');
      },
    );

    testWidgets(
      'een formulier dat de server gesloten noemt kan niet worden geopend',
      (tester) async {
        final f = await serve(tester, ['nl'], state: IntakeFormState.closed);
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await fetch(tester);
        expect(
          find.text(
            'Dit formulier is gesloten voor nieuwe inzendingen. Neem contact op met de organisator.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('invitation-open')))
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('de laatste dag van de bundel is de laatste dag', (
      tester,
    ) async {
      final f = await serve(tester, ['nl']);
      // De bundel sluit op 2027-01-31.
      await show(
        tester,
        f.server,
        initialLink: f.organiser.invite().text,
        now: DateTime.utc(2027, 1, 31),
      );
      await fetch(tester);
      expect(find.byKey(const Key('invitation-closed')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('invitation-open')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('een dag later is het formulier gesloten, met de datum erbij', (
      tester,
    ) async {
      final f = await serve(tester, ['nl']);
      await show(
        tester,
        f.server,
        initialLink: f.organiser.invite().text,
        now: DateTime.utc(2027, 2, 1),
      );
      await fetch(tester);
      // De bundel zelf verloopt pas op 2027-03-01, dus hij wordt nog geloofd.
      expect(
        find.text(
          'Dit formulier is gesloten: de laatste dag was 2027-01-31. Neem contact op met de organisator.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('invitation-open')))
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'onderweg staat er een voortgangsregel, en Annuleren sluit; een late uitkomst doet niets',
      (tester) async {
        final f = await serve(tester, ['nl']);
        f.server.gate = Completer<void>();
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await tester.tap(find.byKey(const Key('invitation-fetch')));
        await tester.pump();
        expect(find.text('Het formulier wordt opgehaald…'), findsOneWidget);
        await tester.tap(find.text('Annuleren'));
        await tester.pumpAndSettle();
        expect(closedWithout, isTrue);
        f.server.gate!.complete();
        await pumpUntil(
          tester,
          () => f.server.completed >= 2,
          reason: 'de server kreeg het vervolg niet te zien',
        );
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() async {});
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        expect(choice, isNull);
      },
    );
  });

  group('als het niet lukt', () {
    Future<String> failureText(WidgetTester tester) async =>
        tester.widget<Text>(find.byKey(const Key('invitation-failure'))).data!;

    testWidgets(
      'geen verbinding noemt de server en vraagt het later opnieuw te proberen',
      (tester) async {
        final f = await serve(tester, ['nl']);
        f.server.failWith = IntakeHttpFailure.network;
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await fetch(tester);
        expect(
          await failureText(tester),
          'Geen verbinding met intake.example.org. Controleer je internetverbinding en probeer het later opnieuw.',
        );
      },
    );

    testWidgets('een adres dat OciDeck niet benadert', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.failWith = IntakeHttpFailure.hostRefused;
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'OciDeck maakt geen verbinding met dit adres.',
      );
    });

    testWidgets('een antwoord dat te groot is', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.failWith = IntakeHttpFailure.responseTooLarge;
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'De server stuurde meer dan OciDeck accepteert.',
      );
    });

    testWidgets('een adres dat geen inzendserver is', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
        200,
        '<html></html>',
      );
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'intake.example.org is geen inzendserver die OciDeck begrijpt.',
      );
    });

    testWidgets('een server die te oud of te nieuw is', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.protocol = 2;
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'Deze server is van een nieuwere versie. Werk OciDeck bij.',
      );
      await tester.tap(find.text('Opnieuw proberen'));
      await tester.pump();
      f.server.protocol = 0;
      await fetch(tester);
      expect(
        await failureText(tester),
        'Deze server is te oud voor deze versie van OciDeck.',
      );
    });

    testWidgets('een formulier dat niet meer bestaat', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.forms.clear();
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'Dit formulier bestaat niet (meer) op de server. Vraag de organisator om een nieuwe uitnodiging.',
      );
    });

    testWidgets('een drukke server', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
        429,
        IntakeError(IntakeErrorCode.rateLimited, 'Rustig.').toJsonText(),
      );
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'De server is druk. Probeer het later opnieuw.',
      );
    });

    testWidgets('een andere weigering van de server', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.overrides['/v1/info'] = FakeIntakeServer.raw(
        502,
        '<html></html>',
      );
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(await failureText(tester), 'De server weigerde het verzoek.');
    });

    testWidgets('een formulier dat niet te lezen is', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.overrides['/v1/forms/$kTestFid'] = FakeIntakeServer.raw(
        200,
        '{"state":"open","variants":[]}',
      );
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'De server stuurde een formulier dat OciDeck niet kan lezen.',
      );
    });

    testWidgets(
      'een andere vingerafdruk dan de uitnodiging noemt: dezelfde zin als bij een bundelbestand',
      (tester) async {
        final f = await serve(tester, ['nl']);
        final other = (await tester.runAsync(IntakeTestOrganiser.create))!;
        await show(
          tester,
          f.server,
          initialLink: f.organiser
              .invite(fingerprint: other.signing.fingerprint)
              .text,
        );
        await fetch(tester);
        expect(
          await failureText(tester),
          'De vingerafdruk past niet bij deze bundel: het formulier komt niet van wie de uitnodiging zegt. Controleer de vingerafdruk en het bundelbestand.',
        );
      },
    );

    testWidgets('een bundel voor het adres van een andere server', (
      tester,
    ) async {
      final f = await serve(tester, []);
      f.server.publish(kTestFid, [
        (await tester.runAsync(
          () =>
              f.organiser.variant(templateIn('nl'), host: 'elders.example.org'),
        ))!,
      ]);
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        await failureText(tester),
        'Het formulier hoort niet bij de server uit de uitnodiging. Vraag de organisator om een nieuwe uitnodiging.',
      );
    });

    testWidgets(
      'Opnieuw proberen brengt de link terug, en een tweede poging kan slagen',
      (tester) async {
        final f = await serve(tester, ['nl']);
        f.server.failWith = IntakeHttpFailure.timeout;
        await show(tester, f.server, initialLink: f.organiser.invite().text);
        await fetch(tester);
        await tester.tap(find.text('Opnieuw proberen'));
        await tester.pump();
        final field = tester.widget<TextField>(
          find.byKey(const Key('invitation-link')),
        );
        expect(field.controller!.text, f.organiser.invite().text);
        f.server.failWith = null;
        await fetch(tester);
        expect(
          find.text('Formulier van Indo IT Kookboek-team'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Sluiten sluit zonder iets te kiezen', (tester) async {
      final f = await serve(tester, ['nl']);
      f.server.failWith = IntakeHttpFailure.network;
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
      expect(closedWithout, isTrue);
    });
  });

  group('de pins', () {
    testWidgets('wat de invuller al zag wordt aan de bundel gehouden', (
      tester,
    ) async {
      final f = await serve(tester, []);
      f.server.publish(kTestFid, [
        (await tester.runAsync(
          () => f.organiser.variant(templateIn('nl'), seq: 2),
        ))!,
      ]);
      final fp = f.organiser.signing.fingerprint;
      pinsRead =
          await tester.runAsync(() async {
                final higher = await f.organiser.variant(
                  templateIn('nl'),
                  seq: 9,
                );
                final v = await verifyFormBundle(
                  higher.bundleText,
                  templateText: templateIn('nl'),
                  fingerprint: fp,
                  now: _now,
                );
                return const FormBundlePins().accepting(
                  (v as FormBundleVerified).bundle,
                  fp,
                );
              })
              as FormBundlePins;
      await show(tester, f.server, initialLink: f.organiser.invite().text);
      await fetch(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('invitation-failure'))).data,
        'Deze bundel is ouder dan een bundel die je eerder van deze organisator kreeg. Vraag de organisator om de nieuwste.',
      );
    });
  });

  group('in een andere taal', () {
    testWidgets('de zinnen volgen de taal van het programma', (tester) async {
      final f = await serve(tester, ['en']);
      await show(
        tester,
        f.server,
        initialLink: f.organiser.invite().text,
        language: 'en',
      );
      expect(find.text('Open invitation'), findsWidgets);
      expect(find.text('Fetch form'), findsOneWidget);
      await fetch(tester);
      expect(find.text('Form from Indo IT Kookboek-team'), findsOneWidget);
      expect(find.text('Fill in the form'), findsOneWidget);
    });
  });
}

const String _fp = 'mw3am46w5weex4a4fqrc3avnub2a6knmgnk5nkjfzaprp5d2e64a';
