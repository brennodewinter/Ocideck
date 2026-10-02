// De controle door de maker vanuit de Inbox (FORM_INTAKE.md §7.4): het hoofdstuk maken, de
// mail voorbereiden en de status zetten.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_maker_check.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/widgets/forms/form_book_dialog.dart';
import 'package:ocideck/widgets/forms/form_inbox_actions.dart';
import 'package:ocideck/widgets/forms/form_maker_check_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_maker_check_fixtures.dart';
import 'support/pump_until.dart';
import 'support/temp_dir.dart';

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  final spec = (parseForm(kookWithMail) as ParsedForm).spec;
  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    dir = await Directory.systemTemp.createTemp('ocideck_checkdlg_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    await workspace.publishForm(kookWithMail);
  });
  tearDown(() => deleteTempDir(dir));

  Future<T> io<T>(WidgetTester tester, Future<T> Function() work) async =>
      (await tester.runAsync(work)) as T;

  FormTemplatePick picks(String body) =>
      (_) async => (name: 'hoofdstuk.md', text: body);

  /// Het resultaat van het venster, zodra het sluit.
  FormMakerCheckResult? result;
  var closed = false;

  Widget app(Widget home) => MaterialApp(
    locale: const Locale('nl'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );

  Future<void> show(
    WidgetTester tester, {
    FormSpec? form,
    FormTemplatePick? pick,
    FormMailOpener? openMail,
    FormAddressLoader? loadAddress,
    int n = 0,
  }) async {
    result = null;
    closed = false;
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showFormMakerCheckDialog(
                context,
                workspace: workspace,
                sid: sidOf(n),
                spec: form ?? spec,
                pickTemplate: pick,
                openMail: openMail,
                loadAddress: loadAddress,
                now: () => DateTime.utc(2026, 11, 3),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder text(String s) => find.text(s);
  Finder field(String label) => find.widgetWithText(TextField, label);
  String valueOf(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;
  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: text(label),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          )
          .onPressed !=
      null;

  const addressLabel = 'E-mailadres van de maker';
  const deadlineLabel = 'Antwoord vóór (jjjj-mm-dd)';

  Future<void> waitForAddress(WidgetTester tester, String expected) =>
      pumpUntil(tester, () => valueOf(tester, addressLabel) == expected);

  /// Wacht tot de voorinvulling van het adres zeker is afgelopen: dezelfde schijfwerk,
  /// later gestart, is pas klaar als het eerder gestarte klaar is.
  Future<void> letPrefillFinish(WidgetTester tester) async {
    await io(tester, () => makerAddressOfSubmission(workspace, sidOf(0)));
    await tester.pump();
  }

  Future<void> chooseTemplate(WidgetTester tester) async {
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
  }

  Future<void> create(WidgetTester tester) async {
    await tester.tap(text('Controledocument maken en openen'));
    await tester.pump();
  }

  Future<void> waitForText(WidgetTester tester, String message) => pumpUntil(
    tester,
    () => find.text(message).evaluate().isNotEmpty,
    reason: message,
  );

  testWidgets(
    'het adres van de maker staat al ingevuld, met veertien dagen om te antwoorden',
    (tester) async {
      await io(tester, () => landKook(workspace, 0));
      await show(tester);
      await waitForAddress(tester, 'sari@example.nl');
      expect(valueOf(tester, deadlineLabel), '2026-11-17');
    },
  );

  testWidgets('zonder adres in de inzending blijft het veld leeg', (
    tester,
  ) async {
    await io(tester, () => landKook(workspace, 0, mail: ''));
    await show(tester);
    await letPrefillFinish(tester);
    expect(valueOf(tester, addressLabel), isEmpty);
  });

  testWidgets('wat de organisator al typte wordt niet overschreven', (
    tester,
  ) async {
    final found = Completer<String?>();
    await show(tester, loadAddress: (_, _) => found.future);
    await tester.enterText(field(addressLabel), 'zelf@example.nl');
    found.complete('sari@example.nl');
    await tester.pump();
    expect(valueOf(tester, addressLabel), 'zelf@example.nl');
  });

  testWidgets('een adres dat er al is vóór er getypt is wordt ingevuld', (
    tester,
  ) async {
    await show(tester, loadAddress: (_, _) async => 'sari@example.nl');
    await tester.pump();
    expect(valueOf(tester, addressLabel), 'sari@example.nl');
  });

  testWidgets('de mail kan pas als adres en dag kloppen', (tester) async {
    await io(tester, () => landKook(workspace, 0, mail: ''));
    await show(tester);
    expect(enabled(tester, 'Mail schrijven'), isFalse);
    expect(text('Dit is geen geldig e-mailadres.'), findsNothing);
    await tester.enterText(field(addressLabel), 'geen adres');
    await tester.pump();
    expect(text('Dit is geen geldig e-mailadres.'), findsOneWidget);
    expect(enabled(tester, 'Mail schrijven'), isFalse);
    await tester.enterText(field(addressLabel), 'sari@example.nl');
    await tester.pump();
    expect(text('Dit is geen geldig e-mailadres.'), findsNothing);
    expect(enabled(tester, 'Mail schrijven'), isTrue);
    await tester.enterText(field(deadlineLabel), '2026-13-40');
    await tester.pump();
    expect(
      find.textContaining('Ongeldige dag. Gebruik jaar-maand-dag'),
      findsOneWidget,
    );
    expect(find.textContaining('bijvoorbeeld 2026-11-03'), findsOneWidget);
    expect(enabled(tester, 'Mail schrijven'), isFalse);
  });

  testWidgets(
    'Mail schrijven opent een mailto met adres, onderwerp en uiterste dag',
    (tester) async {
      await io(tester, () => landKook(workspace, 0));
      final links = <String>[];
      await show(tester, openMail: (link) async => links.add(link));
      await waitForAddress(tester, 'sari@example.nl');
      await tester.tap(text('Mail schrijven'));
      await tester.pump();
      final uri = Uri.parse(links.single);
      expect(uri.scheme, 'mailto');
      expect(Uri.decodeComponent(uri.path), 'sari@example.nl');
      expect(
        uri.queryParameters['subject'],
        'Je bijdrage voor het boek: graag even controleren',
      );
      expect(uri.queryParameters['body'], contains('vóór 2026-11-17.'));
      expect(uri.queryParameters['body'], contains('‘akkoord’'));
      expect(
        text(
          'De mail staat klaar in je mailprogramma. Voeg de pdf toe en verstuur hem.',
        ),
        findsOneWidget,
      );
      expect(closed, isFalse);
    },
  );

  testWidgets('spaties om het adres of de dag horen er niet bij', (
    tester,
  ) async {
    await io(tester, () => landKook(workspace, 0, mail: ''));
    final links = <String>[];
    await show(tester, openMail: (link) async => links.add(link));
    await tester.enterText(field(addressLabel), '  sari@example.nl ');
    await tester.enterText(field(deadlineLabel), ' 2026-12-01 ');
    await tester.pump();
    await tester.tap(text('Mail schrijven'));
    await tester.pump();
    final uri = Uri.parse(links.single);
    expect(Uri.decodeComponent(uri.path), 'sari@example.nl');
    expect(uri.queryParameters['body'], contains('vóór 2026-12-01.'));
  });

  testWidgets('zonder sjabloon wordt er geen document gemaakt', (tester) async {
    await io(tester, () => landKook(workspace, 0));
    await show(tester);
    await create(tester);
    expect(text('Kies eerst een hoofdstuksjabloon.'), findsOneWidget);
    expect(Directory(p.join(workspace.root, 'book')).existsSync(), isFalse);
  });

  testWidgets(
    'het document maken geeft het pad aan de Inbox en sluit het venster',
    (tester) async {
      await io(tester, () => landKook(workspace, 0));
      await io(tester, () => landKook(workspace, 1, naam: 'Joe'));
      await show(tester, pick: picks('# {naam}'));
      await chooseTemplate(tester);
      expect(text('hoofdstuk.md'), findsOneWidget);
      await create(tester);
      await pumpUntil(tester, () => closed);
      final path = (result as FormMakerCheckOpened).path;
      expect(p.basename(path), 'check-abcdefgh.md');
      expect(await io(tester, File(path).readAsString), '# Sari\n');
    },
  );

  testWidgets('geen keuze van een sjabloon verandert niets', (tester) async {
    await io(tester, () => landKook(workspace, 0));
    await show(tester, pick: (_) async => null);
    await chooseTemplate(tester);
    expect(text('Nog geen sjabloon gekozen.'), findsOneWidget);
  });

  testWidgets(
    'een ingetrokken inzending krijgt geen hoofdstuk, en het zegt waarom',
    (tester) async {
      await io(tester, () => landKook(workspace, 0, withdrawn: true));
      await show(tester, pick: picks('# {naam}'));
      await chooseTemplate(tester);
      await create(tester);
      await waitForText(
        tester,
        'Deze inzending is ingetrokken en komt dus in geen enkel hoofdstuk.',
      );
      expect(closed, isFalse);
    },
  );

  testWidgets('een sjabloon met een onbekend veld wordt bij naam geweigerd', (
    tester,
  ) async {
    await io(tester, () => landKook(workspace, 0));
    await show(tester, pick: picks('# {naam} {fout}'));
    await chooseTemplate(tester);
    await create(tester);
    await waitForText(
      tester,
      'Het sjabloon noemt velden die het formulier niet heeft: fout.',
    );
  });

  testWidgets('een inzending die niet te lezen is', (tester) async {
    await io(tester, () => landKook(workspace, 0));
    await io(
      tester,
      () => File(
        p.join(workspace.submissionPath(sidOf(0)), 'manifest.json'),
      ).writeAsString('kapot'),
    );
    await show(tester, pick: picks('# {naam}'));
    await chooseTemplate(tester);
    await create(tester);
    await waitForText(
      tester,
      'Deze inzending is niet te lezen, of het formulier waarvoor ze is ingediend staat niet in de werkmap.',
    );
  });

  testWidgets('een formulier dat niet in de werkmap staat', (tester) async {
    await io(tester, () => landKook(workspace, 0));
    await io(
      tester,
      () => Directory(p.join(workspace.root, 'forms')).delete(recursive: true),
    );
    await show(tester, pick: picks('# {naam}'));
    await chooseTemplate(tester);
    await create(tester);
    await waitForText(
      tester,
      'Deze inzending is niet te lezen, of het formulier waarvoor ze is ingediend staat niet in de werkmap.',
    );
  });

  testWidgets('een inzending die niet in het register staat', (tester) async {
    await io(tester, () => landKook(workspace, 0));
    await io(tester, () => File(workspace.registerPath).delete());
    await show(tester, pick: picks('# {naam}'));
    await chooseTemplate(tester);
    await create(tester);
    await waitForText(
      tester,
      'Deze inzending staat niet in het register. Herstel overview.md en probeer het opnieuw.',
    );
  });

  testWidgets('een register dat stuk is wordt gemeld', (tester) async {
    await io(tester, () => landKook(workspace, 0));
    await show(tester, pick: picks('# {naam}'));
    await chooseTemplate(tester);
    await io(
      tester,
      () => File(workspace.registerPath).writeAsString('Mijn aantekeningen.\n'),
    );
    await create(tester);
    await waitForText(
      tester,
      'Het register kan niet worden gelezen. Herstel overview.md.',
    );
  });

  testWidgets('een map waar niet te schrijven valt wordt gemeld', (
    tester,
  ) async {
    if (Platform.isWindows) return;
    await io(tester, () => landKook(workspace, 0));
    await show(tester, pick: picks('# {naam}'));
    await chooseTemplate(tester);
    await io(tester, () => Process.run('chmod', ['555', workspace.root]));
    addTearDown(() => Process.run('chmod', ['755', workspace.root]));
    await create(tester);
    await waitForText(
      tester,
      'Het controledocument kon niet worden geschreven.',
    );
  });

  testWidgets('Controle verstuurd zet de status en geeft de zin aan de Inbox', (
    tester,
  ) async {
    await io(tester, () => landKook(workspace, 0));
    await show(tester);
    await tester.tap(text('Controle verstuurd'));
    await tester.pump();
    await pumpUntil(tester, () => closed);
    expect(
      (result as FormMakerCheckStatusSet).message,
      'Status gewijzigd naar maker-check-sent.',
    );
    final register = await io(tester, workspace.readRegister);
    final row = (register as FormRegisterParsed).register.rows.single;
    expect(row.status, 'maker-check-sent');
  });

  testWidgets('tijdens het zetten van de status staan beide knoppen vast', (
    tester,
  ) async {
    await io(tester, () => landKook(workspace, 0));
    await show(tester, pick: picks('# {naam}'));
    await tester.tap(text('Controle verstuurd'));
    await tester.pump();
    expect(enabled(tester, 'Controle verstuurd'), isFalse);
    expect(enabled(tester, 'Controledocument maken en openen'), isFalse);
    await pumpUntil(tester, () => closed);
  });

  testWidgets(
    'het venster sluiten tijdens het zetten van de status laat niets achter',
    (tester) async {
      await io(tester, () => landKook(workspace, 0));
      await show(tester);
      await tester.tap(text('Controle verstuurd'));
      await tester.pump();
      await tester.tap(text('Sluiten'));
      await tester.pumpAndSettle();
      await pumpUntil(tester, () {
        final register = File(workspace.registerPath).readAsStringSync();
        return register.contains('maker-check-sent');
      });
      // Een latere schijfhandeling is pas klaar als de vorige is afgehandeld, ook wat
      // daarna in het venster gebeurt.
      await io(tester, workspace.readRegister);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('een formulier zonder die status laat hem niet zetten', (
    tester,
  ) async {
    final eigen = kookWithMail.replaceFirst(
      'states="received|maker-check-sent|maker-approved"',
      'states="received|klaar"',
    );
    await show(tester, form: (parseForm(eigen) as ParsedForm).spec);
    expect(
      text(
        'Dit formulier kent de status maker-check-sent niet; die kan hier dus niet worden gezet.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, 'Controle verstuurd'), isFalse);
  });

  testWidgets('met die status is er geen waarschuwing en de knop werkt', (
    tester,
  ) async {
    await show(tester);
    expect(
      find.textContaining('kent de status maker-check-sent niet'),
      findsNothing,
    );
    expect(enabled(tester, 'Controle verstuurd'), isTrue);
  });

  testWidgets('een register dat stuk is laat de status ongemoeid en zegt het', (
    tester,
  ) async {
    await io(tester, () => landKook(workspace, 0));
    await io(
      tester,
      () => File(workspace.registerPath).writeAsString('Mijn aantekeningen.\n'),
    );
    await show(tester);
    await tester.tap(text('Controle verstuurd'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find
          .textContaining('Het register kan niet worden gelezen')
          .evaluate()
          .isNotEmpty,
    );
    expect(closed, isFalse);
  });

  testWidgets('Sluiten sluit zonder iets mee te geven', (tester) async {
    await show(tester);
    await tester.tap(text('Sluiten'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets(
    'tijdens het maken staat de knop vast, en sluiten laat niets achter',
    (tester) async {
      await io(tester, () => landKook(workspace, 0));
      await show(tester, pick: picks('# {naam}'));
      await chooseTemplate(tester);
      await create(tester);
      expect(enabled(tester, 'Controledocument maken en openen'), isFalse);
      expect(enabled(tester, 'Controle verstuurd'), isFalse);
      await tester.tap(text('Sluiten'));
      await tester.pumpAndSettle();
      final doc = File(p.join(workspace.root, 'book', 'check-abcdefgh.md'));
      await pumpUntil(tester, () => doc.existsSync());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  group('de knop in de Inbox', () {
    Future<void> inbox(
      WidgetTester tester, {
      required List<String> done,
      FormRegisterRow? row,
      FormSpec? form,
      bool canEdit = true,
      ValueChanged<String>? onOpenFile,
      Future<FormMakerCheckResult?> Function(BuildContext)? makerCheck,
    }) => tester.pumpWidget(
      app(
        FormInboxActions(
          workspace: workspace,
          sid: sidOf(0),
          row: row,
          spec: form,
          onDone: done.add,
          onOpenFile: onOpenFile,
          canEdit: canEdit,
          makerCheck: makerCheck,
        ),
      ),
    );

    final received = FormRegisterRow({'sid': sidOf(0), 'status': 'received'});

    testWidgets('staat er voor een inzending die te lezen is', (tester) async {
      await inbox(
        tester,
        row: received,
        form: spec,
        onOpenFile: (_) {},
        done: [],
      );
      expect(text('Controle door de maker…'), findsOneWidget);
    });

    testWidgets(
      'staat er niet zonder opener, zonder formulier of als ze niet te lezen is',
      (tester) async {
        await inbox(tester, row: received, form: spec, done: []);
        expect(text('Controle door de maker…'), findsNothing);
        await inbox(tester, row: received, onOpenFile: (_) {}, done: []);
        expect(text('Controle door de maker…'), findsNothing);
        await inbox(
          tester,
          row: received,
          form: spec,
          onOpenFile: (_) {},
          canEdit: false,
          done: [],
        );
        expect(text('Controle door de maker…'), findsNothing);
      },
    );

    testWidgets('staat er niet voor een ingetrokken of verwijderde inzending', (
      tester,
    ) async {
      final withdrawn = FormRegisterRow({
        'sid': sidOf(0),
        'status': 'received',
        'withdrawn': '2026-11-02',
      });
      await inbox(
        tester,
        row: withdrawn,
        form: spec,
        onOpenFile: (_) {},
        done: [],
      );
      expect(text('Controle door de maker…'), findsNothing);
      final deleted = FormRegisterRow({'sid': sidOf(0), 'status': 'deleted'});
      await inbox(
        tester,
        row: deleted,
        form: spec,
        onOpenFile: (_) {},
        done: [],
      );
      expect(text('Controle door de maker…'), findsNothing);
    });

    testWidgets('opent het venster', (tester) async {
      await io(tester, () => landKook(workspace, 0));
      await inbox(
        tester,
        row: received,
        form: spec,
        onOpenFile: (_) {},
        done: [],
      );
      await tester.tap(text('Controle door de maker…'));
      await tester.pumpAndSettle();
      expect(text('Controledocument maken en openen'), findsOneWidget);
    });

    testWidgets('een gemaakt document wordt geopend', (tester) async {
      final opened = <String>[];
      final done = <String>[];
      await inbox(
        tester,
        row: received,
        form: spec,
        onOpenFile: opened.add,
        done: done,
        makerCheck: (_) async => const FormMakerCheckOpened('/x/check.md'),
      );
      await tester.tap(text('Controle door de maker…'));
      await tester.pump();
      expect(opened, ['/x/check.md']);
      expect(done, isEmpty);
    });

    testWidgets('een gezette status wordt gemeld', (tester) async {
      final opened = <String>[];
      final done = <String>[];
      await inbox(
        tester,
        row: received,
        form: spec,
        onOpenFile: opened.add,
        done: done,
        makerCheck: (_) async => const FormMakerCheckStatusSet('Klaar.'),
      );
      await tester.tap(text('Controle door de maker…'));
      await tester.pump();
      expect(done, ['Klaar.']);
      expect(opened, isEmpty);
    });

    testWidgets('sluiten zonder iets te doen laat alles staan', (tester) async {
      final opened = <String>[];
      final done = <String>[];
      await inbox(
        tester,
        row: received,
        form: spec,
        onOpenFile: opened.add,
        done: done,
        makerCheck: (_) async => null,
      );
      await tester.tap(text('Controle door de maker…'));
      await tester.pump();
      expect(opened, isEmpty);
      expect(done, isEmpty);
    });
  });
}
