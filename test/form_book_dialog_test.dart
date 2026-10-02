// Het boek samenstellen vanuit de Inbox (FORM_INTAKE.md §7.5): de keuzes, en de zin die
// zegt hoe het ging.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_submission_actions.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/widgets/forms/form_book_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_photo_fixtures.dart';
import 'support/pump_until.dart';
import 'support/temp_dir.dart';

const String kook =
    '''<!-- form id=kook version=1 states="received|maker-approved|laid-out" overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=soort type=choice options="Zoet|Hartig" -->
**Soort**
<!-- answer -->
<!-- /field id=soort -->

<!-- field id=foto type=image count=0..2 -->
**Foto**
<!-- answer -->
<!-- /field id=foto -->

<!-- field id=rij type=table columns="A|B" -->
**Rij**
<!-- answer -->
<!-- /field id=rij -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

String sidOf(int n) => 'abcdefghijklmnopqrstuvwxy${'abcdefg'[n]}';

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    dir = await Directory.systemTemp.createTemp('ocideck_bookdlg_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
  });
  tearDown(() => deleteTempDir(dir));

  Future<T> io<T>(WidgetTester tester, Future<T> Function() work) async =>
      (await tester.runAsync(work)) as T;

  /// Een inzending in de werkmap, met een status.
  Future<void> seed(
    WidgetTester tester,
    List<({int n, String naam, String soort, String status})> subs, {
    String form = kook,
  }) => io(tester, () async {
    await workspace.publishForm(form);
    for (final s in subs) {
      await importFormPackage(
        workspace,
        buildFormPackage(
          submission: form
              .replaceFirst(
                '<!-- answer -->\n<!-- /field id=naam',
                '<!-- answer -->\n${s.naam}\n<!-- /field id=naam',
              )
              .replaceFirst(
                '<!-- answer -->\n<!-- /field id=soort',
                '<!-- answer -->\n${s.soort}\n<!-- /field id=soort',
              )
              .replaceFirst(
                '- [ ]\n<!-- /field id=akkoord',
                '- [x]\n<!-- /field id=akkoord',
              ),
          template: form,
          spec: (parseForm(form) as ParsedForm).spec,
          images: const {},
          submissionId: sidOf(s.n),
          created: DateTime.utc(2026, 10, 4),
          clientRules: kFormRulesVersion,
        ),
        now: DateTime.utc(2026, 10, 6),
      );
      if (s.status != 'received') {
        await setSubmissionStatus(workspace, sidOf(s.n), s.status, [
          'received',
          'maker-approved',
          'laid-out',
        ]);
      }
    }
  });

  Future<List<PublishedForm>> forms(WidgetTester tester) async =>
      (await io(tester, workspace.publishedForms)).forms;

  Future<void> show(
    WidgetTester tester, {
    List<PublishedForm>? list,
    FormTemplatePick? pick,
    ValueChanged<String>? onOpenFile,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFormBookDialog(
                context,
                workspace: workspace,
                forms: list ?? const [],
                onOpenFile: onOpenFile,
                pickTemplate: pick,
                now: () => DateTime.utc(2026, 11, 3),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder text(String s) => find.text(s);
  FormTemplatePick picks(String name, String body) =>
      (_) async => (name: name, text: body);

  Future<void> compile(WidgetTester tester, String expected) async {
    await tester.tap(text('Samenstellen'));
    await pumpUntil(
      tester,
      () => find.textContaining(expected).evaluate().isNotEmpty,
    );
  }

  testWidgets(
    'zonder bruikbaar formulier staat dat er, en is er niets te doen',
    (tester) async {
      await show(tester);
      expect(
        text('Er is geen bruikbaar formulier in de werkmap.'),
        findsOneWidget,
      );
      expect(text('Samenstellen'), findsNothing);
    },
  );

  testWidgets('maker-approved staat standaard aan, de rest niet', (
    tester,
  ) async {
    await seed(tester, []);
    await show(tester, list: await forms(tester));
    final chips = tester
        .widgetList<FilterChip>(find.byType(FilterChip))
        .toList();
    expect(
      [for (final c in chips) ((c.label as Text).data, c.selected)],
      [('received', false), ('maker-approved', true), ('laid-out', false)],
    );
  });

  testWidgets(
    'een formulier zonder maker-approved begint zonder gekozen status',
    (tester) async {
      final eigen = kook.replaceFirst(
        'states="received|maker-approved|laid-out"',
        'states="nieuw|klaar"',
      );
      await seed(tester, [], form: eigen);
      await show(tester, list: await forms(tester));
      final chips = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .toList();
      expect([for (final c in chips) c.selected], [false, false]);
    },
  );

  testWidgets('de talen van één versie zijn één keuze', (tester) async {
    await seed(tester, []);
    await io(
      tester,
      () => workspace.publishForm(
        kook.replaceFirst('id=kook version=1', 'id=kook version=1 lang=nl'),
      ),
    );
    await io(
      tester,
      () => workspace.publishForm(
        kook.replaceFirst('id=kook version=1', 'id=kook version=1 lang=en'),
      ),
    );
    final all = await forms(tester);
    expect(all.length, greaterThan(1));
    await show(tester, list: all);
    await tester.tap(find.byType(DropdownButton<PublishedForm>));
    await tester.pumpAndSettle();
    expect(
      find.text('kook · v1'),
      findsNWidgets(2),
      reason: 'de keuze zelf en één regel in het menu',
    );
  });

  testWidgets(
    'zonder sjabloon, of zonder status, wordt er niets samengesteld',
    (tester) async {
      await seed(tester, [
        (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
      ]);
      await show(tester, list: await forms(tester));
      await tester.tap(text('Samenstellen'));
      await tester.pump();
      expect(text('Kies eerst een hoofdstuksjabloon.'), findsOneWidget);
      expect(Directory(p.join(workspace.root, 'book')).existsSync(), isFalse);
    },
  );

  testWidgets('zonder gekozen status wordt er niets samengesteld', (
    tester,
  ) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('hoofdstuk.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'maker-approved'));
    await tester.pump();
    await tester.tap(text('Samenstellen'));
    await tester.pump();
    expect(text('Kies minstens één status.'), findsOneWidget);
  });

  testWidgets('de hele weg: sjabloon kiezen, samenstellen, het boek openen', (
    tester,
  ) async {
    await seed(tester, [
      (n: 0, naam: 'Zoë', soort: 'Zoet', status: 'maker-approved'),
      (n: 1, naam: 'Adi', soort: 'Hartig', status: 'maker-approved'),
      (n: 2, naam: 'Joe', soort: 'Zoet', status: 'received'),
    ]);
    final opened = <String>[];
    await show(
      tester,
      list: await forms(tester),
      pick: picks('hoofdstuk.md', '# {naam}'),
      onOpenFile: opened.add,
    );
    expect(text('Nog geen sjabloon gekozen.'), findsOneWidget);
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    expect(text('hoofdstuk.md'), findsOneWidget);
    await compile(tester, 'Boek samengesteld. Hoofdstukken: 2. Foto’s: 0.');
    expect(find.textContaining('Ingetrokken en dus weggelaten'), findsNothing);
    expect(find.textContaining('Overgeslagen'), findsNothing);
    expect(find.textContaining('ontbraken'), findsNothing);
    final book = File(p.join(workspace.root, 'book', 'boek.md'));
    expect(await io(tester, book.readAsString), '# Zoë\n\n# Adi\n');
    await tester.tap(text('Boek openen'));
    await tester.pumpAndSettle();
    expect(opened, [book.path]);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('ordenen en groeperen worden meegegeven', (tester) async {
    await seed(tester, [
      (n: 0, naam: 'Zoë', soort: 'Zoet', status: 'maker-approved'),
      (n: 1, naam: 'Adi', soort: 'Hartig', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    // Ordenen op soort
    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('soort').last);
    await tester.pumpAndSettle();
    // Groeperen op soort
    await tester.tap(find.byType(DropdownButton<String?>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('soort').last);
    await tester.pumpAndSettle();
    await compile(tester, 'Boek samengesteld.');
    final book = File(p.join(workspace.root, 'book', 'boek.md'));
    expect(
      await io(tester, book.readAsString),
      '## Hartig\n\n# Adi\n\n## Zoet\n\n# Zoë\n',
    );
  });

  testWidgets('afbeeldingen, toestemming en tabellen zijn geen ordening', (
    tester,
  ) async {
    await seed(tester, []);
    await show(tester, list: await forms(tester));
    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    expect(find.text('naam'), findsWidgets);
    expect(find.text('foto'), findsNothing);
    expect(find.text('akkoord'), findsNothing);
    expect(find.text('rij'), findsNothing);
  });

  testWidgets('een sjabloon met een onbekend veld wordt geweigerd bij naam', (
    tester,
  ) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam} {fout}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await compile(
      tester,
      'Het sjabloon noemt velden die het formulier niet heeft: fout.',
    );
  });

  testWidgets('een naam die al is, en een naam die niet kan', (tester) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await compile(tester, 'Boek samengesteld.');
    await tester.tap(text('Samenstellen'));
    await pumpUntil(
      tester,
      () => text(
        'Er staat al een boek met deze naam. Kies een andere naam.',
      ).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField), 'a b');
    await tester.tap(text('Samenstellen'));
    await pumpUntil(
      tester,
      () => find
          .textContaining('Gebruik voor de naam alleen letters')
          .evaluate()
          .isNotEmpty,
    );
  });

  testWidgets('niets om in het boek te zetten zegt waarom', (tester) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'received'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await compile(tester, 'Er is niets om in het boek te zetten');
    expect(
      find.textContaining('Ingetrokken: 0; overgeslagen: 0.'),
      findsOneWidget,
    );
    expect(text('Boek openen'), findsNothing);
  });

  testWidgets('wat ingetrokken en overgeslagen is staat in de melding', (
    tester,
  ) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
      (n: 1, naam: 'Joe', soort: 'Zoet', status: 'maker-approved'),
      (n: 2, naam: 'Adi', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await io(
      tester,
      () => setSubmissionWithdrawal(workspace, sidOf(1), '2026-11-02'),
    );
    await io(
      tester,
      () => File(
        p.join(workspace.submissionPath(sidOf(2)), 'manifest.json'),
      ).writeAsString('geen json'),
    );
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await compile(tester, 'Boek samengesteld. Hoofdstukken: 1.');
    expect(
      find.textContaining('Ingetrokken en dus weggelaten: 1.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Overgeslagen (andere versie of niet te lezen): 1.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'een register dat stuk is, en een schijf die weigert, worden gemeld',
    (tester) async {
      await seed(tester, [
        (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
      ]);
      await show(
        tester,
        list: await forms(tester),
        pick: picks('h.md', '# {naam}'),
      );
      await tester.tap(text('Hoofdstuksjabloon kiezen…'));
      await tester.pump();
      await io(
        tester,
        () =>
            File(workspace.registerPath).writeAsString('Mijn aantekeningen.\n'),
      );
      await compile(
        tester,
        'Het register kan niet worden gelezen. Herstel overview.md.',
      );
    },
  );

  testWidgets('een boek dat niet te schrijven valt wordt gemeld', (
    tester,
  ) async {
    if (Platform.isWindows) return;
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await io(tester, () => Process.run('chmod', ['555', workspace.root]));
    addTearDown(() => Process.run('chmod', ['755', workspace.root]));
    await compile(tester, 'Het boek kon niet worden geschreven.');
  });

  testWidgets('geen keuze van een sjabloon verandert niets', (tester) async {
    await seed(tester, []);
    await show(tester, list: await forms(tester), pick: (_) async => null);
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    expect(text('Nog geen sjabloon gekozen.'), findsOneWidget);
  });

  testWidgets('een status erbij kiezen neemt die inzendingen mee', (
    tester,
  ) async {
    await seed(tester, [
      (n: 0, naam: 'Zoë', soort: 'Zoet', status: 'maker-approved'),
      (n: 1, naam: 'Joe', soort: 'Zoet', status: 'received'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'received'));
    await tester.pump();
    await compile(tester, 'Boek samengesteld. Hoofdstukken: 2.');
  });

  testWidgets('zonder opener biedt het geen Boek openen aan', (tester) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await compile(tester, 'Boek samengesteld.');
    expect(text('Boek openen'), findsNothing);
  });

  testWidgets('een formulier zonder maker-approved vraagt zelf om een status', (
    tester,
  ) async {
    final eigen = kook.replaceFirst(
      'states="received|maker-approved|laid-out"',
      'states="nieuw|klaar"',
    );
    await seed(tester, [], form: eigen);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await tester.tap(text('Samenstellen'));
    await tester.pump();
    expect(text('Kies minstens één status.'), findsOneWidget);
  });

  testWidgets('spaties om de naam horen er niet bij', (tester) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  mijnboek ');
    await compile(tester, 'Boek samengesteld.');
    expect(
      File(p.join(workspace.root, 'book', 'mijnboek.md')).existsSync(),
      isTrue,
    );
  });

  testWidgets(
    'de nieuwste versie staat voorop, en een andere versie wist de ordening',
    (tester) async {
      await seed(tester, []);
      await io(
        tester,
        () =>
            workspace.publishForm(kook.replaceFirst('version=1', 'version=2')),
      );
      await show(tester, list: await forms(tester));
      DropdownButton<PublishedForm> pick() =>
          tester.widget(find.byType(DropdownButton<PublishedForm>));
      expect(pick().value!.version, 2);
      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('soort').last);
      await tester.pumpAndSettle();
      DropdownButton<String?> order() =>
          tester.widget(find.byType(DropdownButton<String?>).first);
      expect(order().value, 'soort');
      await tester.tap(find.byType(DropdownButton<String?>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('soort').last);
      await tester.pumpAndSettle();
      DropdownButton<String?> group() =>
          tester.widget(find.byType(DropdownButton<String?>).last);
      expect(group().value, 'soort');
      await tester.tap(find.byType(DropdownButton<PublishedForm>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('kook · v1').last);
      await tester.pumpAndSettle();
      expect(pick().value!.version, 1);
      expect(order().value, isNull);
      expect(group().value, isNull);
    },
  );

  testWidgets('een foto die ontbreekt wordt in de melding geteld', (
    tester,
  ) async {
    await io(tester, () async {
      await workspace.publishForm(kook);
      final answer = kook
          .replaceFirst(
            '<!-- answer -->\n<!-- /field id=naam',
            '<!-- answer -->\nSari\n<!-- /field id=naam',
          )
          .replaceFirst(
            '- [ ]\n<!-- /field id=akkoord',
            '- [x]\n<!-- /field id=akkoord',
          )
          .replaceFirst(
            '<!-- answer -->\n<!-- /field id=foto',
            '<!-- answer -->\n![Beschrijving](images/foto-1.jpg "Foto: Sari")\n<!-- /field id=foto',
          );
      await importFormPackage(
        workspace,
        buildFormPackage(
          submission: answer,
          template: kook,
          spec: (parseForm(kook) as ParsedForm).spec,
          images: {'images/foto-1.jpg': jpegPhoto()},
          submissionId: sidOf(0),
          created: DateTime.utc(2026, 10, 4),
          clientRules: kFormRulesVersion,
        ),
        now: DateTime.utc(2026, 10, 6),
      );
      await setSubmissionStatus(workspace, sidOf(0), 'maker-approved', [
        'received',
        'maker-approved',
        'laid-out',
      ]);
      await File(
        p.join(workspace.submissionPath(sidOf(0)), 'images', 'foto-1.jpg'),
      ).delete();
    });
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}\n{foto}'),
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await compile(tester, 'Boek samengesteld. Hoofdstukken: 1. Foto’s: 0.');
    expect(
      find.textContaining('Foto’s die in de werkmap ontbraken: 1.'),
      findsOneWidget,
    );
  });

  testWidgets('tijdens het samenstellen is de vorige melding weg', (
    tester,
  ) async {
    await seed(tester, [
      (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
    ]);
    await show(
      tester,
      list: await forms(tester),
      pick: picks('h.md', '# {naam}'),
      onOpenFile: (_) {},
    );
    await tester.tap(text('Hoofdstuksjabloon kiezen…'));
    await tester.pump();
    await compile(tester, 'Boek samengesteld.');
    expect(text('Boek openen'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'tweede');
    await tester.tap(text('Samenstellen'));
    await tester.pump();
    expect(find.textContaining('Boek samengesteld.'), findsNothing);
    expect(text('Boek openen'), findsNothing);
    await pumpUntil(
      tester,
      () => find.textContaining('Boek samengesteld.').evaluate().isNotEmpty,
    );
  });

  testWidgets(
    'het venster sluiten tijdens het samenstellen laat niets achter',
    (tester) async {
      await seed(tester, [
        (n: 0, naam: 'Sari', soort: 'Zoet', status: 'maker-approved'),
      ]);
      await show(
        tester,
        list: await forms(tester),
        pick: picks('h.md', '# {naam}'),
      );
      await tester.tap(text('Hoofdstuksjabloon kiezen…'));
      await tester.pump();
      await tester.tap(text('Samenstellen'));
      await tester.pump();
      await tester.tap(text('Sluiten'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      final book = File(p.join(workspace.root, 'book', 'boek.md'));
      await pumpUntil(tester, () => book.existsSync());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
