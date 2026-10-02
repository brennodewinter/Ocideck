// De lijst van de Inbox (FORM_INTAKE.md §7.2, §7.3): een regel per inzending uit het
// register, en per inzending wat er tegen het gepubliceerde formulier mis mee is.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/widgets/forms/form_inbox_list.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_photo_fixtures.dart';
import 'support/pump_until.dart';
import 'support/temp_dir.dart';

const String kook = '''<!-- form id=kook version=1 overview="naam,soort" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=soort type=text -->
**Soort**
<!-- answer -->
<!-- /field id=soort -->

<!-- field id=foto type=image count=0..2 min-width=2000 -->
**Foto**
<!-- answer -->
<!-- /field id=foto -->
''';

const String first = 'abcdefghijklmnopqrstuvwxya';
const String second = 'abcdefghijklmnopqrstuvwxyb';

Uint8List zipOf({
  String naam = 'Sari',
  String soort = '',
  String id = first,
  List<String> fotos = const [],
  Map<String, Uint8List> images = const {},
}) {
  var text = kook.replaceFirst(
    '<!-- answer -->\n<!-- /field id=naam -->',
    '<!-- answer -->\n$naam\n<!-- /field id=naam -->',
  );
  if (soort.isNotEmpty) {
    text = text.replaceFirst(
      '<!-- answer -->\n<!-- /field id=soort',
      '<!-- answer -->\n$soort\n<!-- /field id=soort',
    );
  }
  if (fotos.isNotEmpty) {
    text = text.replaceFirst(
      '<!-- answer -->\n<!-- /field id=foto',
      '<!-- answer -->\n${fotos.map((f) => '![]($f)').join('\n')}\n<!-- /field id=foto',
    );
  }
  return buildFormPackage(
    submission: text,
    template: kook,
    spec: (parseForm(kook) as ParsedForm).spec,
    images: images,
    submissionId: id,
    created: DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
}

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    dir = await Directory.systemTemp.createTemp('ocideck_inboxlist_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
  });
  tearDown(() => deleteTempDir(dir));

  /// Echte bestands-I/O draait niet binnen de nep-klok van een widgettest.
  Future<T> io<T>(WidgetTester tester, Future<T> Function() work) async =>
      (await tester.runAsync(work)) as T;

  Future<void> seed(
    WidgetTester tester,
    List<Uint8List> zips, {
    bool publish = true,
  }) => io(tester, () async {
    if (publish) await workspace.publishForm(kook);
    for (final zip in zips) {
      await importFormPackage(workspace, zip, now: DateTime.utc(2026, 10, 6));
    }
  });

  Future<void> pump(WidgetTester tester, {int version = 0}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FormInboxList(workspace: workspace, version: version),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder text(String s) => find.text(s);

  testWidgets('zonder inzendingen staat er dat', (tester) async {
    await pump(tester);
    await pumpUntil(
      tester,
      () => text('Nog geen inzendingen.').evaluate().isNotEmpty,
    );
  });

  testWidgets(
    'een regel per inzending, de nieuwste bovenaan, met haar status',
    (tester) async {
      await seed(tester, [zipOf(), zipOf(naam: '', id: second)]);
      await pump(tester);
      await pumpUntil(
        tester,
        () => find.byType(ExpansionTile).evaluate().length == 2,
      );
      final tiles = tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .toList();
      expect(
        (tiles[0].title as Text).data,
        'abcdefgh…',
        reason: 'leeg gelaten: alleen het nummer',
      );
      expect((tiles[1].title as Text).data, 'Sari');
      expect(
        (tiles[0].subtitle as Text).data,
        'Om na te lopen · Ontvangen 2026-10-06',
      );
      expect(
        (tiles[1].subtitle as Text).data,
        'received · Ontvangen 2026-10-06',
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    },
  );

  testWidgets('de overzichtskolommen van het formulier vormen de naam', (
    tester,
  ) async {
    await seed(tester, [zipOf(soort: 'Zoet')]);
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect((tile.title as Text).data, 'Sari · Zoet');
  });

  testWidgets('een rij zonder ontvangstdag zegt er niets over', (tester) async {
    await seed(tester, [zipOf()]);
    await io(tester, () async {
      final register =
          (await workspace.readRegister() as FormRegisterParsed).register;
      final text = register.toMarkdown().replaceAll('2026-10-06', '');
      await File(workspace.registerPath).writeAsString(text);
    });
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect((tile.subtitle as Text).data, 'received');
  });

  testWidgets(
    'na een verversing is een opengeklapte beoordeling niet meer van gisteren',
    (tester) async {
      await seed(tester, [zipOf(naam: '')]);
      await pump(tester);
      await pumpUntil(
        tester,
        () => find.byType(ExpansionTile).evaluate().isNotEmpty,
      );
      await open(tester, 'abcdefgh…');
      await pumpUntil(
        tester,
        () => find
            .textContaining('Verplicht, maar leeg gelaten.', findRichText: true)
            .evaluate()
            .isNotEmpty,
      );
      await io(
        tester,
        () =>
            File(
              p.join(workspace.submissionPath(first), 'submission.edit.md'),
            ).writeAsString(
              kook.replaceFirst(
                '<!-- answer -->\n<!-- /field id=naam',
                '<!-- answer -->\nSari\n<!-- /field id=naam',
              ),
            ),
      );
      await pump(tester, version: 1);
      await pumpUntil(
        tester,
        () => text('Geen punten om na te lopen.').evaluate().isNotEmpty,
      );
    },
  );

  testWidgets('openklappen toont wat er mis is, bij naam van het veld', (
    tester,
  ) async {
    await seed(tester, [zipOf(naam: '')]);
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    await open(tester, 'abcdefgh…');
    await pumpUntil(
      tester,
      () => text('Beoordeeld tegen kook · v1.').evaluate().isNotEmpty,
    );
    expect(find.textContaining('Naam: ', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Verplicht, maar leeg gelaten.', findRichText: true),
      findsOneWidget,
    );
    expect(text('Geen punten om na te lopen.'), findsNothing);
  });

  testWidgets('een goede inzending heeft niets om na te lopen', (tester) async {
    await seed(tester, [zipOf()]);
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    await open(tester, 'Sari');
    await pumpUntil(
      tester,
      () => text('Geen punten om na te lopen.').evaluate().isNotEmpty,
    );
  });

  testWidgets('een waarschuwing heeft een eigen pictogram', (tester) async {
    const path = 'images/foto-1.jpg';
    await seed(tester, [
      zipOf(fotos: [path], images: {path: jpegPhoto(width: 640, height: 480)}),
    ]);
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    await open(tester, 'Sari');
    await pumpUntil(
      tester,
      () => find.byIcon(Icons.warning_amber_outlined).evaluate().isNotEmpty,
    );
    expect(find.textContaining('Foto van', findRichText: true), findsOneWidget);
  });

  testWidgets('een foto die geen antwoord noemt wordt geteld', (tester) async {
    await seed(tester, [
      zipOf(images: {'images/los-1.jpg': jpegPhoto(width: 2400, height: 1800)}),
    ]);
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    await open(tester, 'Sari');
    await pumpUntil(
      tester,
      () => text('Foto’s die geen antwoord noemt: 1.').evaluate().isNotEmpty,
    );
  });

  testWidgets(
    'een werkkopie die het herstelt, haalt het punt weg en zegt dat',
    (tester) async {
      await seed(tester, [zipOf(naam: '')]);
      await io(
        tester,
        () =>
            File(
              p.join(workspace.submissionPath(first), 'submission.edit.md'),
            ).writeAsString(
              kook.replaceFirst(
                '<!-- answer -->\n<!-- /field id=naam',
                '<!-- answer -->\nSari\n<!-- /field id=naam',
              ),
            ),
      );
      await pump(tester);
      await pumpUntil(
        tester,
        () => find.byType(ExpansionTile).evaluate().isNotEmpty,
      );
      await open(tester, 'abcdefgh…');
      await pumpUntil(
        tester,
        () => text('Geen punten om na te lopen.').evaluate().isNotEmpty,
      );
      expect(
        text('De beoordeling gaat over de werkkopie (submission.edit.md).'),
        findsOneWidget,
      );
    },
  );

  testWidgets('een ingetrokken inzending zegt wanneer', (tester) async {
    await seed(tester, [zipOf()]);
    await io(tester, () async {
      final register =
          (await workspace.readRegister() as FormRegisterParsed).register;
      await workspace.saveRegister(
        register.withWithdrawal(first, '2026-11-02')!,
      );
    });
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(
      (tile.subtitle as Text).data,
      'received · Ontvangen 2026-10-06 · Ingetrokken 2026-11-02',
    );
  });

  testWidgets('een verwijderde inzending laat alleen het record zien', (
    tester,
  ) async {
    await seed(tester, [zipOf()]);
    await io(tester, () async {
      final register =
          (await workspace.readRegister() as FormRegisterParsed).register;
      await workspace.saveRegister(register.withDeletion(first)!);
      await workspace.deleteSubmissionFiles(first);
    });
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect((tile.title as Text).data, 'abcdefgh…', reason: 'de naam is weg');
    expect((tile.subtitle as Text).data, 'Verwijderd · Ontvangen 2026-10-06');
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await open(tester, 'abcdefgh…');
    await pumpUntil(
      tester,
      () => find
          .textContaining('De inhoud van deze inzending is verwijderd')
          .evaluate()
          .isNotEmpty,
    );
  });

  testWidgets('een inzending die niet te lezen is, wordt gemeld', (
    tester,
  ) async {
    await seed(tester, [zipOf()]);
    await io(
      tester,
      () => File(
        p.join(workspace.submissionPath(first), 'manifest.json'),
      ).writeAsString('geen json'),
    );
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    await open(tester, 'Sari');
    await pumpUntil(
      tester,
      () =>
          find.textContaining('kan niet worden gelezen').evaluate().isNotEmpty,
    );
  });

  testWidgets(
    'zonder register staan de inzendingen er toch, zonder registerregel',
    (tester) async {
      await seed(tester, [zipOf()]);
      await io(tester, () => File(workspace.registerPath).delete());
      await pump(tester);
      await pumpUntil(
        tester,
        () => find.byType(ExpansionTile).evaluate().isNotEmpty,
      );
      final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
      expect((tile.title as Text).data, 'abcdefgh…');
      expect((tile.subtitle as Text).data, 'Zonder regel in het register');
      expect(find.textContaining('kan niet worden gelezen'), findsNothing);
    },
  );

  testWidgets('een register dat stuk is wordt gemeld, de inzendingen blijven', (
    tester,
  ) async {
    await seed(tester, [zipOf()]);
    await io(
      tester,
      () => File(workspace.registerPath).writeAsString('Mijn aantekeningen.\n'),
    );
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().isNotEmpty,
    );
    expect(
      find.textContaining('Het register kan niet worden gelezen'),
      findsOneWidget,
    );
    expect(text('Zonder regel in het register'), findsOneWidget);
  });

  testWidgets('een nieuwe versie leest de lijst opnieuw', (tester) async {
    await seed(tester, [zipOf()]);
    await pump(tester);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().length == 1,
    );
    await seed(tester, [zipOf(id: second, naam: 'Joe')], publish: false);
    await pump(tester, version: 1);
    await pumpUntil(
      tester,
      () => find.byType(ExpansionTile).evaluate().length == 2,
    );
    expect(text('Joe'), findsOneWidget);
  });

  group('FormReviewView', () {
    FormReview reviewWith(List<FormProblem> problems, {bool known = true}) {
      final opened = readFormPackage(zipOf()) as FormPackageOpened;
      return FormReview(
        manifest: opened.manifest,
        problems: problems,
        published: known ? kook : null,
        spec: known ? (parseForm(kook) as ParsedForm).spec : null,
      );
    }

    Future<void> show(
      WidgetTester tester,
      FormReview review, {
      bool edited = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FormReviewView(review: review, edited: edited),
          ),
        ),
      );
    }

    testWidgets('elke ernst heeft zijn eigen pictogram', (tester) async {
      await show(
        tester,
        reviewWith([
          FormProblem(FormIssueCode.requiredEmpty, fieldId: 'naam'),
          FormProblem(
            FormIssueCode.imageTooSmall,
            fieldId: 'foto',
            facts: {'actual': 1, 'min': 2},
          ),
          FormProblem(
            FormIssueCode.imageUnexpectedFaces,
            fieldId: 'foto',
            facts: {'actual': 2, 'expected': 1},
          ),
        ]),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('een veld dat het formulier niet kent heet bij zijn id', (
      tester,
    ) async {
      await show(
        tester,
        reviewWith([
          FormProblem(FormIssueCode.fieldNotInForm, fieldId: 'extra'),
        ]),
      );
      expect(
        find.textContaining('extra: ', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'bestaat niet in het gepubliceerde formulier',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('een punt zonder veld staat zonder naam ervoor', (
      tester,
    ) async {
      await show(
        tester,
        reviewWith([
          FormProblem(
            FormIssueCode.templateTextAltered,
            facts: {'reason': 'hash'},
          ),
        ]),
      );
      expect(find.textContaining(': ', findRichText: true), findsNothing);
      expect(
        find.textContaining(
          'andere tekst van het formulier',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'zonder bekend formulier staat er niet tegen wat beoordeeld is',
      (tester) async {
        await show(
          tester,
          reviewWith([
            FormProblem(FormIssueCode.templateUnknown),
          ], known: false),
        );
        expect(find.textContaining('Beoordeeld tegen'), findsNothing);
        expect(find.textContaining('niet in de werkmap'), findsOneWidget);
      },
    );
  });
}
