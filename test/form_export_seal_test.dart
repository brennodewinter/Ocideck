// De inzending verzegeld opslaan vanaf de invulpagina (FORM_INTAKE.md §5.1, §5.6): het
// bundelbestand, de vingerafdruk uit de uitnodiging, en wat de invuller te lezen krijgt als de
// bundel niet geloofd wordt.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/forms/form_export_support.dart';
import 'package:ocideck/widgets/forms/form_fill_view.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/pump_until.dart';

const String frontMatter = '---\ntitle: Kookboek\n---\n';

const String leeg = '''<!-- form id=kook version=2 -->
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

const String fid = 'abcdefghijklmnopqrstuvwxyz';

late FormSigningKey owner;
late String ownerIdentity;
late String ownerAge;

String day(DateTime d) => formDay(d.toUtc());

Future<String> bundle({
  String template = frontMatter + leeg,
  int seq = 3,
  String? expires,
  String? closes,
  FormSigningKey? signer,
  DateTime? at,
}) async {
  final result = await createFormBundle(
    fid: fid,
    template: template,
    organisers: [
      FormBundleOrganiserInput(
        name: 'Indo IT Kookboek-team',
        age: ownerAge,
        signPublicKey: owner.publicKey,
      ),
    ],
    owner: signer ?? owner,
    bundleSeq: seq,
    expires: expires ?? '2099-01-01',
    now: at ?? DateTime.now(),
    policy: FormBundlePolicy(closes: closes),
  );
  return (result as FormBundleCreated).text;
}

class SealSpy {
  SealSpy({this.bundleText, this.saveAs = 'kook-abcdef.zip.age'});

  String? bundleText;
  String? saveAs;
  bool saveThrows = false;
  Completer<void>? pickGate;

  int picks = 0;
  int formPicks = 0;
  FormBundlePins pins = const FormBundlePins();
  int pinWrites = 0;
  ({String bundle, String fingerprint})? memory;
  final List<String> forgotten = [];
  final List<({String name, Uint8List bytes})> saved = [];
  String? published;

  FormExportSupport get support => FormExportSupport(
    frontMatter: frontMatter,
    clientVersion: '0.6.13',
    readImage: (path) async => null,
    pickPublished: () async {
      formPicks++;
      return null;
    },
    save: (name, bytes) async {
      if (saveThrows) throw const FormatException('schijf vol');
      saved.add((name: name, bytes: bytes));
      return saveAs;
    },
    recall: (_) => published,
    remember: (_, text) => published = text,
    seal: FormSealSupport(
      pickBundle: () async {
        picks++;
        await pickGate?.future;
        return bundleText;
      },
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
  );
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
  String text = leeg,
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
      home: Scaffold(body: _Host(text, support: support)),
    ),
  );
  await tester.pump();
}

Finder text(String s) => find.text(s);
Finder containing(String s) => find.textContaining(s);

/// De invuller vult in en kiest verzegeld opslaan.
Future<void> fillAndSeal(
  WidgetTester tester, {
  String? fingerprint,
  bool fill = true,
}) async {
  if (fill) {
    await tester.enterText(find.byType(TextField).first, 'Sari');
    await tester.pump();
  }
  final sealed = text('Verzegeld opslaan…');
  await tester.ensureVisible(sealed);
  await tester.pumpAndSettle();
  await tester.tap(sealed);
  await tester.pumpAndSettle();
  if (fingerprint != null) {
    await tester.enterText(find.byType(TextField).last, fingerprint);
    await tester.tap(text('Doorgaan'));
    await tester.pumpAndSettle();
  }
}

/// Wacht tot [until] er staat: sleutels en versleuteling zijn echt werk.
Future<void> settle(WidgetTester tester, Finder until) => pumpUntil(
  tester,
  () => until.evaluate().isNotEmpty,
  reason: 'wachtte op ${until.describeMatch(Plurality.one)}',
);

/// Wacht tot [done] waar is.
Future<void> settleWhen(WidgetTester tester, bool Function() done) =>
    pumpUntil(tester, done, reason: 'het werk is niet klaargekomen');

void main() {
  setUpAll(() async {
    owner = await generateFormSigningKey();
    ownerIdentity = generateAgeIdentity();
    ownerAge = (await ageRecipientOf(ownerIdentity))!;
  });

  String fp() => formatFingerprint(owner.fingerprint);

  testWidgets('zonder verzegel-ondersteuning is er alleen de gewone zip', (
    tester,
  ) async {
    final plain = FormExportSupport(
      frontMatter: frontMatter,
      readImage: (_) async => null,
      pickPublished: () async => null,
      save: (_, _) async => null,
      recall: (_) => null,
      remember: (_, _) {},
    );
    await pump(tester, plain);
    expect(text('Inzending opslaan als zip…'), findsOneWidget);
    expect(text('Verzegeld opslaan…'), findsNothing);
    expect(containing('.zip.age'), findsNothing);
  });

  testWidgets('met ondersteuning staan beide knoppen er, met uitleg', (
    tester,
  ) async {
    await pump(tester, SealSpy().support);
    expect(text('Inzending opslaan als zip…'), findsOneWidget);
    expect(text('Verzegeld opslaan…'), findsOneWidget);
    expect(containing('alleen de organisator kan openen'), findsOneWidget);
  });

  testWidgets('een verzegeld bestand dat de organisator opent', (tester) async {
    final spy = SealSpy(bundleText: await bundle());
    await pump(tester, spy.support);
    await fillAndSeal(tester, fingerprint: fp());
    await settle(tester, containing('Verzegeld opgeslagen als'));
    expect(spy.picks, 1);
    final saved = spy.saved.single;
    expect(saved.name, matches(RegExp(r'^kook-[a-z2-7]{6}\.zip\.age$')));
    final opened = await tester.runAsync(
      () => openSealedPackage(
        saved.bytes,
        identities: [ownerIdentity],
        expectedFormId: 'kook',
        expectedFormVersion: 2,
      ),
    );
    expect(
      ((opened!) as FormUnsealed).package.submission,
      frontMatter + gevuld,
    );
    expect(
      text(
        'Verzegeld opgeslagen als kook-abcdef.zip.age, alleen te openen door: Indo IT Kookboek-team.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('de bestandsnaam heeft de naam van de zip met .zip.age', (
    tester,
  ) async {
    final spy = SealSpy(bundleText: await bundle(), saveAs: 'anders.zip.age');
    await pump(tester, spy.support);
    await fillAndSeal(tester, fingerprint: fp());
    await settle(tester, containing('Verzegeld opgeslagen als anders.zip.age'));
    expect(
      spy.saved.single.name,
      matches(RegExp(r'^kook-[a-z2-7]{6}\.zip\.age$')),
    );
  });

  testWidgets('wat werkte wordt onthouden: een tweede inzending vraagt niets', (
    tester,
  ) async {
    final spy = SealSpy(bundleText: await bundle());
    await pump(tester, spy.support);
    await fillAndSeal(tester, fingerprint: fp());
    await settle(tester, containing('Verzegeld opgeslagen als'));
    expect(spy.memory, isNotNull);
    expect(spy.pins.seqFor(fid, owner.fingerprint), 3);
    expect(spy.pinWrites, 1);
    await fillAndSeal(tester, fill: false);
    await settleWhen(tester, () => spy.saved.length == 2);
    expect(spy.picks, 1, reason: 'het bundelbestand is niet opnieuw gevraagd');
    expect(containing('Vingerafdruk van de organisator'), findsNothing);
    expect(spy.saved, hasLength(2));
  });

  group('annuleren', () {
    testWidgets('geen bundelbestand kiezen: er gebeurt niets', (tester) async {
      final spy = SealSpy();
      await pump(tester, spy.support);
      await fillAndSeal(tester);
      expect(spy.picks, 1);
      expect(spy.saved, isEmpty);
      expect(containing('Vingerafdruk van de organisator'), findsNothing);
    });

    testWidgets('de vingerafdruk niet geven: er gebeurt niets', (tester) async {
      final spy = SealSpy(bundleText: await bundle());
      await pump(tester, spy.support);
      await fillAndSeal(tester);
      expect(text('Vingerafdruk van de organisator'), findsOneWidget);
      await tester.tap(text('Annuleren'));
      await tester.pumpAndSettle();
      expect(spy.saved, isEmpty);
      expect(spy.pinWrites, 0);
      expect(spy.memory, isNull);
    });

    testWidgets(
      'het opslagvenster annuleren: de pins staan, het geheugen niet',
      (tester) async {
        final spy = SealSpy(bundleText: await bundle(), saveAs: null);
        await pump(tester, spy.support);
        await fillAndSeal(tester, fingerprint: fp());
        await settleWhen(tester, () => spy.saved.isNotEmpty);
        // Het werk is klaar als de knoppen weer los zijn.
        await settleWhen(
          tester,
          () =>
              tester
                  .widget<ButtonStyleButton>(
                    find.ancestor(
                      of: text('Verzegeld opslaan…'),
                      matching: find.bySubtype<ButtonStyleButton>(),
                    ),
                  )
                  .onPressed !=
              null,
        );
        expect(spy.saved, hasLength(1));
        expect(
          spy.pinWrites,
          1,
          reason: 'de bundel is geloofd, ook al is er niets opgeslagen',
        );
        expect(spy.memory, isNull);
        expect(containing('Verzegeld opgeslagen als'), findsNothing);
      },
    );
  });

  group('wat de invuller te lezen krijgt', () {
    Future<void> expectRefusal(
      WidgetTester tester,
      SealSpy spy,
      String message, {
      String? fingerprint,
      bool forgotten = true,
    }) async {
      await pump(tester, spy.support);
      await fillAndSeal(tester, fingerprint: fingerprint ?? fp());
      await settle(tester, containing(message));
      expect(spy.saved, isEmpty);
      expect(spy.pinWrites, 0);
      expect(spy.forgotten.isNotEmpty, forgotten);
    }

    testWidgets('een vingerafdruk die geen vingerafdruk is', (tester) async {
      await expectRefusal(
        tester,
        SealSpy(bundleText: await bundle()),
        'Dat is geen vingerafdruk. Hij bestaat uit 52 tekens',
        fingerprint: 'abcd',
      );
    });

    testWidgets('de vingerafdruk van een ander', (tester) async {
      final other = await generateFormSigningKey();
      await expectRefusal(
        tester,
        SealSpy(bundleText: await bundle()),
        'De vingerafdruk past niet bij deze bundel',
        fingerprint: formatFingerprint(other.fingerprint),
      );
    });

    testWidgets('een bestand dat geen bundel is', (tester) async {
      await expectRefusal(
        tester,
        SealSpy(bundleText: 'geen bundel'),
        'Dit bestand is geen bundel die OciDeck kan lezen.',
      );
    });

    testWidgets('een bundel die is veranderd', (tester) async {
      final text = (await bundle()).replaceFirst(
        'Indo IT Kookboek-team',
        'Iemand',
      );
      await expectRefusal(
        tester,
        SealSpy(bundleText: text),
        'De handtekening van de bundel klopt niet',
      );
    });

    testWidgets('een bundel bij een ander formulier', (tester) async {
      final other = (frontMatter + leeg).replaceFirst(
        'Welkom.',
        'Welkom daar.',
      );
      await expectRefusal(
        tester,
        SealSpy(bundleText: await bundle(template: other)),
        'Deze bundel hoort niet bij dit formulier.',
      );
    });

    testWidgets('een bundel die verlopen is', (tester) async {
      final yesterday = day(DateTime.now().subtract(const Duration(days: 1)));
      await expectRefusal(
        tester,
        SealSpy(
          bundleText: await bundle(
            expires: yesterday,
            at: DateTime.utc(2020, 1, 1),
          ),
        ),
        'Deze bundel is verlopen.',
      );
    });

    testWidgets('een bundel die ouder is dan een eerder geziene', (
      tester,
    ) async {
      final spy = SealSpy(bundleText: await bundle(seq: 3));
      spy.pins = FormBundlePins.fromJson({'$fid@${owner.fingerprint}': 9});
      await expectRefusal(
        tester,
        spy,
        'Deze bundel is ouder dan een bundel die je eerder van deze organisator kreeg.',
      );
    });

    testWidgets(
      'gesloten: de laatste dag staat erbij, en er wordt niets vergeten',
      (tester) async {
        final yesterday = day(DateTime.now().subtract(const Duration(days: 1)));
        await expectRefusal(
          tester,
          SealSpy(bundleText: await bundle(closes: yesterday)),
          'Dit formulier is gesloten: de laatste dag was $yesterday.',
          forgotten: false,
        );
      },
    );

    testWidgets('te groot: de grens in megabytes staat erbij', (tester) async {
      final result = await createFormBundle(
        fid: fid,
        template: frontMatter + leeg,
        organisers: [
          FormBundleOrganiserInput(
            name: 'Redactie',
            age: ownerAge,
            signPublicKey: owner.publicKey,
          ),
        ],
        owner: owner,
        bundleSeq: 1,
        expires: '2099-01-01',
        now: DateTime.now(),
        policy: const FormBundlePolicy(maxPackageBytes: 100),
      );
      await expectRefusal(
        tester,
        SealSpy(bundleText: (result as FormBundleCreated).text),
        'De inzending is groter dan de organisator toestaat (0.0 MB).',
        forgotten: false,
      );
    });

    testWidgets('een opslagvenster dat niet opent', (tester) async {
      final spy = SealSpy(bundleText: await bundle())..saveThrows = true;
      await pump(tester, spy.support);
      await fillAndSeal(tester, fingerprint: fp());
      await settle(tester, text('De inzending kon niet worden opgeslagen.'));
      expect(spy.memory, isNull);
    });

    testWidgets('met iets open wijst de knop de fout aan en vraagt niets', (
      tester,
    ) async {
      final spy = SealSpy(bundleText: await bundle());
      await pump(tester, spy.support);
      await fillAndSeal(tester, fill: false);
      expect(spy.picks, 0);
      expect(containing('Dit veld is verplicht'), findsOneWidget);
    });
  });

  testWidgets('met iets open wordt niet eerst om het formulier gevraagd', (
    tester,
  ) async {
    // Een antwoord dat niet mag, in een document dat al is ingevuld: het formulier is niet
    // onthouden, maar er valt niets te verzegelen.
    final teLang = gevuld.replaceFirst('Sari', 'S' * 41);
    final spy = SealSpy(bundleText: await bundle());
    await pump(tester, spy.support, text: teLang);
    await fillAndSeal(tester, fill: false);
    expect(spy.formPicks, 0);
    expect(spy.picks, 0);
    expect(spy.saved, isEmpty);
  });

  testWidgets('tijdens het werk staan beide knoppen vast', (tester) async {
    final gate = Completer<void>();
    final spy = SealSpy(bundleText: await bundle())..pickGate = gate;
    await pump(tester, spy.support);
    await tester.enterText(find.byType(TextField).first, 'Sari');
    await tester.pump();
    await tester.ensureVisible(text('Verzegeld opslaan…'));
    await tester.pumpAndSettle();
    await tester.tap(text('Verzegeld opslaan…'));
    await tester.pump();
    for (final label in ['Verzegeld opslaan…', 'Inzending opslaan als zip…']) {
      final widget = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(widget.onPressed, isNull, reason: label);
    }
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('de knoppen zeggen in het Engels wat ze doen', (tester) async {
    await pump(
      tester,
      SealSpy(bundleText: await bundle()).support,
      language: 'en',
    );
    expect(text('Save sealed…'), findsOneWidget);
    expect(containing('only the organiser can open'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Sari');
    await tester.pump();
    await tester.ensureVisible(text('Save sealed…'));
    await tester.pumpAndSettle();
    await tester.tap(text('Save sealed…'));
    await tester.pumpAndSettle();
    expect(text("The organiser's fingerprint"), findsOneWidget);
    expect(text('Cancel'), findsOneWidget);
    expect(text('Continue'), findsOneWidget);
  });

  testWidgets('het vingerafdrukvenster leert niets van wat je typt', (
    tester,
  ) async {
    final spy = SealSpy(bundleText: await bundle());
    await pump(tester, spy.support);
    await fillAndSeal(tester);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.controller!.text, isEmpty, reason: 'nooit voorgevuld');
  });

  testWidgets('Enter in het vingerafdrukvenster geeft de vingerafdruk door', (
    tester,
  ) async {
    final spy = SealSpy(bundleText: await bundle());
    await pump(tester, spy.support);
    await fillAndSeal(tester);
    await tester.enterText(find.byType(TextField).last, fp());
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await settle(tester, containing('Verzegeld opgeslagen als'));
  });
}
