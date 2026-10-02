// De lijst van de Inbox (FORM_INTAKE.md §7.2, §7.3): een regel per inzending uit het
// register, en per inzending wat er tegen het gepubliceerde formulier mis mee is.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_submission_actions.dart';
import 'package:ocideck/widgets/forms/form_inbox_actions.dart';
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
  String form = kook,
  String naam = 'Sari',
  String soort = '',
  String id = first,
  List<String> fotos = const [],
  Map<String, Uint8List> images = const {},
}) {
  var text = form.replaceFirst(
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
    template: form,
    spec: (parseForm(form) as ParsedForm).spec,
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
    String form = kook,
  }) => io(tester, () async {
    if (publish) await workspace.publishForm(form);
    for (final zip in zips) {
      await importFormPackage(workspace, zip, now: DateTime.utc(2026, 10, 6));
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    int version = 0,
    ValueChanged<String>? onOpenFile,
    Future<FormDeleteOutcome> Function(
      FormWorkspace,
      String, {
      List<String> keep,
    })?
    delete,
  }) async {
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
            child: FormInboxList(
              workspace: workspace,
              version: version,
              now: () => DateTime.utc(2026, 11, 2),
              delete: delete ?? deleteSubmission,
              onOpenFile: onOpenFile,
            ),
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

  group('wat je met een inzending doet', () {
    Future<void> openFirst(WidgetTester tester, [String title = 'Sari']) async {
      await pumpUntil(
        tester,
        () => find.byType(ExpansionTile).evaluate().isNotEmpty,
      );
      await open(tester, title);
      await pumpUntil(
        tester,
        () => find.byType(FormInboxActions).evaluate().isNotEmpty,
      );
    }

    String subtitle(WidgetTester tester) =>
        (tester.widget<ExpansionTile>(find.byType(ExpansionTile)).subtitle
                as Text)
            .data!;

    testWidgets('de status wisselt naar een status van het formulier', (
      tester,
    ) async {
      await seed(tester, [zipOf()]);
      await pump(tester);
      await openFirst(tester);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('edited').last);
      await pumpUntil(
        tester,
        () => text('Status gewijzigd naar edited.').evaluate().isNotEmpty,
      );
      await pumpUntil(tester, () => subtitle(tester).startsWith('edited'));
    });

    testWidgets(
      'intrekken vraagt de dag, met vandaag als voorstel, en onthoudt hem',
      (tester) async {
        await seed(tester, [zipOf()]);
        await pump(tester);
        await openFirst(tester);
        await tester.tap(text('Intrekken…'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, '2026-11-02'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Intrekken'));
        await pumpUntil(
          tester,
          () => text('Intrekking opgeslagen.').evaluate().isNotEmpty,
        );
        await pumpUntil(
          tester,
          () => subtitle(tester).contains('Ingetrokken 2026-11-02'),
        );
        await pumpUntil(
          tester,
          () => text('Intrekking ongedaan maken').evaluate().isNotEmpty,
        );
        await tester.tap(text('Intrekking ongedaan maken'));
        await pumpUntil(
          tester,
          () => text('Intrekking ongedaan gemaakt.').evaluate().isNotEmpty,
        );
        await pumpUntil(
          tester,
          () => !subtitle(tester).contains('Ingetrokken'),
        );
      },
    );

    testWidgets('een dag die geen dag is houdt het venster open, met uitleg', (
      tester,
    ) async {
      await seed(tester, [zipOf()]);
      await pump(tester);
      await openFirst(tester);
      await tester.tap(text('Intrekken…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'gisteren');
      await tester.tap(find.widgetWithText(FilledButton, 'Intrekken'));
      await tester.pump();
      expect(
        text('Ongeldige dag. Gebruik jaar-maand-dag, bijvoorbeeld 2026-11-02.'),
        findsOneWidget,
      );
      expect(find.text('Inzending intrekken'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2026-11-03');
      await tester.pump();
      expect(find.textContaining('Ongeldige dag'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Intrekken'));
      await pumpUntil(
        tester,
        () => subtitle(tester).contains('Ingetrokken 2026-11-03'),
      );
    });

    testWidgets('annuleren bij intrekken verandert niets', (tester) async {
      await seed(tester, [zipOf()]);
      await pump(tester);
      await openFirst(tester);
      await tester.tap(text('Intrekken…'));
      await tester.pumpAndSettle();
      await tester.tap(text('Annuleren'));
      await tester.pumpAndSettle();
      expect(find.text('Inzending intrekken'), findsNothing);
      expect(find.textContaining('Intrekking'), findsNothing);
    });

    testWidgets(
      'verwijderen zegt eerst wat het doet, en wist pas na bevestigen',
      (tester) async {
        await seed(tester, [zipOf()]);
        final calls = <(String, List<String>)>[];
        await pump(
          tester,
          delete: (ws, sid, {keep = const []}) {
            calls.add((sid, keep));
            return deleteSubmission(ws, sid, keep: keep);
          },
        );
        await openFirst(tester);
        await tester.tap(text('Verwijderen…'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('worden uit de werkmap gewist'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Dit kan niet ongedaan worden gemaakt.'),
          findsOneWidget,
        );
        expect(find.textContaining('Ook blijft staan'), findsNothing);
        // Annuleren: er is niets gebeurd, ook niet aan de kant van de schijf.
        await tester.tap(text('Annuleren'));
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(find.textContaining('Inzending verwijderd'), findsNothing);
        // Bevestigen.
        await tester.tap(text('Verwijderen…'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
        await pumpUntil(
          tester,
          () => text(
            'Inzending verwijderd; het record blijft staan.',
          ).evaluate().isNotEmpty,
        );
        expect(calls, hasLength(1));
        expect(calls.single.$1, first);
        expect(calls.single.$2, isEmpty);
        expect(
          await io(
            tester,
            () async => File(
              p.join(workspace.submissionPath(first), 'submission.md'),
            ).exists(),
          ),
          isFalse,
        );
        await pumpUntil(
          tester,
          () => subtitle(tester).startsWith('Verwijderd'),
        );
      },
    );

    testWidgets('als verwijderen niet lukt staat dat er, in gewone woorden', (
      tester,
    ) async {
      await seed(tester, [zipOf()]);
      for (final (outcome, message) in [
        (
          FormDeleteOutcome.notFound,
          'De inzending is niet gevonden in de werkmap.',
        ),
        (FormDeleteOutcome.failed, 'De inzending kon niet worden verwijderd.'),
        (
          FormDeleteOutcome.deletedRegisterNotUpdated,
          'Inzending verwijderd, maar het register kon niet worden bijgewerkt. Pas overview.md met de hand aan.',
        ),
      ]) {
        await pump(
          tester,
          delete: (ws, sid, {keep = const []}) async => outcome,
        );
        await openFirst(tester);
        await tester.tap(text('Verwijderen…'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
        await pumpUntil(tester, () => text(message).evaluate().isNotEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
      'de werkkopie wordt gemaakt en geopend, en wat binnenkwam blijft',
      (tester) async {
        await seed(tester, [zipOf(naam: '')]);
        final opened = <String>[];
        await pump(tester, onOpenFile: opened.add);
        await openFirst(tester, 'abcdefgh…');
        await tester.tap(text('Werkkopie openen'));
        await pumpUntil(tester, () => opened.isNotEmpty);
        final copy = p.join(
          workspace.submissionPath(first),
          'submission.edit.md',
        );
        expect(opened, [copy]);
        final bytes = await io(
          tester,
          () async => [
            await File(copy).readAsBytes(),
            await File(
              p.join(workspace.submissionPath(first), 'submission.md'),
            ).readAsBytes(),
          ],
        );
        expect(bytes[0], bytes[1]);
      },
    );

    testWidgets('de knop zegt wat hij doet', (tester) async {
      await seed(tester, [zipOf()]);
      await pump(tester, onOpenFile: (_) {});
      await openFirst(tester);
      expect(
        find.byTooltip(
          'Opent een kopie van de inzending om in te verbeteren. Wat binnenkwam blijft ongewijzigd.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'zonder opener, bij een verwijderde of onleesbare inzending is er geen knop',
      (tester) async {
        await seed(tester, [zipOf(), zipOf(id: second, naam: 'Joe')]);
        await io(tester, () => deleteSubmission(workspace, second));
        await io(
          tester,
          () => File(
            p.join(workspace.submissionPath(first), 'manifest.json'),
          ).writeAsString('geen json'),
        );
        // Zonder opener.
        await pump(tester);
        await pumpUntil(
          tester,
          () => find.byType(ExpansionTile).evaluate().length == 2,
        );
        await open(tester, 'Sari');
        await pumpUntil(
          tester,
          () => find.byType(FormInboxActions).evaluate().isNotEmpty,
        );
        expect(text('Werkkopie openen'), findsNothing);
        // Met opener: onleesbaar en verwijderd hebben nog steeds geen knop.
        await pump(tester, onOpenFile: (_) {});
        await pumpUntil(
          tester,
          () => find.byType(FormInboxActions).evaluate().isNotEmpty,
        );
        expect(text('Werkkopie openen'), findsNothing);
        await open(tester, 'abcdefgh…');
        await pumpUntil(
          tester,
          () => find.byType(FormInboxActions).evaluate().length == 2,
        );
        expect(text('Werkkopie openen'), findsNothing);
      },
    );

    testWidgets(
      'een rij die verwijderd heet maakt geen werkkopie, ook al staan de bestanden er nog',
      (tester) async {
        await seed(tester, [zipOf()]);
        await io(tester, () async {
          final register =
              (await workspace.readRegister() as FormRegisterParsed).register;
          await workspace.saveRegister(register.withDeletion(first)!);
        });
        await pump(tester, onOpenFile: (_) {});
        await pumpUntil(
          tester,
          () => find.byType(ExpansionTile).evaluate().isNotEmpty,
        );
        await open(tester, 'abcdefgh…');
        await pumpUntil(
          tester,
          () => find.byType(FormInboxActions).evaluate().isNotEmpty,
        );
        expect(text('Werkkopie openen'), findsNothing);
      },
    );

    testWidgets(
      'zonder opener (de lijst kan geen bestand openen) is er geen knop',
      (tester) async {
        await seed(tester, [zipOf()]);
        await pump(tester);
        await openFirst(tester);
        expect(text('Werkkopie openen'), findsNothing);
        expect(text('Intrekken…'), findsOneWidget);
      },
    );

    testWidgets('ook zonder bekend formulier is er een werkkopie te maken', (
      tester,
    ) async {
      await seed(tester, [zipOf()]);
      await io(
        tester,
        () =>
            Directory(p.join(workspace.root, 'forms')).delete(recursive: true),
      );
      await pump(tester, onOpenFile: (_) {});
      await openFirst(tester);
      expect(text('Werkkopie openen'), findsOneWidget);
    });

    testWidgets('als de kopie niet te maken is staat dat er', (tester) async {
      if (Platform.isWindows) return;
      await seed(tester, [zipOf()]);
      await pump(tester, onOpenFile: (_) {});
      await openFirst(tester);
      final folder = workspace.submissionPath(first);
      await io(tester, () => Process.run('chmod', ['555', folder]));
      addTearDown(() => Process.run('chmod', ['755', folder]));
      await tester.tap(text('Werkkopie openen'));
      await pumpUntil(
        tester,
        () => text(
          'De werkkopie kon niet worden aangemaakt.',
        ).evaluate().isNotEmpty,
      );
    });

    testWidgets(
      'verdwenen vlak voor het openen: de inzending is niet gevonden',
      (tester) async {
        await seed(tester, [zipOf()]);
        await pump(tester, onOpenFile: (_) {});
        await openFirst(tester);
        await io(
          tester,
          () => File(
            p.join(workspace.submissionPath(first), 'submission.md'),
          ).delete(),
        );
        await tester.tap(text('Werkkopie openen'));
        await pumpUntil(
          tester,
          () => text(
            'De inzending is niet gevonden in de werkmap.',
          ).evaluate().isNotEmpty,
        );
      },
    );

    testWidgets('dezelfde status kiezen is geen wijziging', (tester) async {
      await seed(tester, [zipOf()]);
      await pump(tester);
      await openFirst(tester);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('received').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Status gewijzigd'), findsNothing);
      final status = await io(tester, () async {
        final read = await workspace.readRegister() as FormRegisterParsed;
        return read.register.row(first)!.status;
      });
      expect(status, 'received');
    });

    testWidgets(
      'een verwijderde inzending kan nog worden ingetrokken, niet meer verwijderd of van status gewisseld',
      (tester) async {
        await seed(tester, [zipOf()]);
        await io(tester, () => deleteSubmission(workspace, first));
        await pump(tester);
        await pumpUntil(
          tester,
          () => find.byType(ExpansionTile).evaluate().isNotEmpty,
        );
        await open(tester, 'abcdefgh…');
        await pumpUntil(
          tester,
          () => find.byType(FormInboxActions).evaluate().isNotEmpty,
        );
        expect(text('Intrekken…'), findsOneWidget);
        expect(text('Verwijderen…'), findsNothing);
        expect(find.byType(DropdownButton<String>), findsNothing);
      },
    );

    testWidgets(
      'wat het formulier vooraf aankondigde blijft, en de bevestiging noemt het',
      (tester) async {
        final keep = kook.replaceFirst(
          'overview="naam,soort"',
          'overview="naam,soort" keep-record="naam"',
        );
        await seed(tester, [zipOf(form: keep)], form: keep);
        await pump(tester);
        await openFirst(tester);
        await tester.tap(text('Verwijderen…'));
        await tester.pumpAndSettle();
        expect(
          text('Ook blijft staan wat het formulier vooraf aankondigde: naam.'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
        await pumpUntil(
          tester,
          () => subtitle(tester).startsWith('Verwijderd'),
        );
        final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
        expect(
          (tile.title as Text).data,
          'Sari',
          reason: 'de naam stond in keep-record',
        );
      },
    );

    testWidgets(
      'zonder bekend formulier is er geen statuskeuze, wel intrekken en verwijderen',
      (tester) async {
        await seed(tester, [zipOf()]);
        await io(
          tester,
          () => Directory(
            p.join(workspace.root, 'forms'),
          ).delete(recursive: true),
        );
        await pump(tester);
        await openFirst(tester);
        expect(find.byType(DropdownButton<String>), findsNothing);
        expect(text('Intrekken…'), findsOneWidget);
        expect(text('Verwijderen…'), findsOneWidget);
      },
    );

    testWidgets(
      'een register dat stuk is: geen statuskeuze en geen intrekken, verwijderen werkt en zegt het',
      (tester) async {
        await seed(tester, [zipOf()]);
        await io(
          tester,
          () => File(
            workspace.registerPath,
          ).writeAsString('Mijn aantekeningen.\n'),
        );
        await pump(tester);
        await openFirst(tester, 'abcdefgh…');
        expect(find.byType(DropdownButton<String>), findsNothing);
        expect(text('Intrekken…'), findsNothing);
        await tester.tap(text('Verwijderen…'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
        await pumpUntil(
          tester,
          () => find
              .textContaining('het register kon niet worden bijgewerkt')
              .evaluate()
              .isNotEmpty,
        );
      },
    );

    testWidgets('een wijziging die niet kan wordt gemeld in gewone woorden', (
      tester,
    ) async {
      await seed(tester, [zipOf()]);
      await pump(tester);
      await openFirst(tester);
      // Het register verdwijnt onder de lijst vandaan.
      await io(tester, () => File(workspace.registerPath).delete());
      await tester.tap(text('Intrekken…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Intrekken'));
      await pumpUntil(
        tester,
        () => find
            .textContaining('Deze wijziging kon niet worden doorgevoerd')
            .evaluate()
            .isNotEmpty,
      );
    });
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
