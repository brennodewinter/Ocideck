// Een offline uitnodigingspakket maken vanuit de Inbox (FORM_INTAKE.md §5.1, §7.6): de keuzes, de vingerafdruk
// die erna komt en elke zin die zegt waarom er niets is ondertekend.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_bundle_make.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/widgets/forms/form_bundle_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_key_vault.dart';
import 'support/pump_until.dart';
import 'support/temp_dir.dart';

String formText({
  String lang = 'nl',
  String controller = 'Indo IT Kookboek-team',
  String closes = '2026-12-01',
}) =>
    '''<!-- form id=kook version=1 lang=$lang controller="$controller" contact="kook@example.org" retain-unused="6 maanden" closes="$closes" overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  late FormKeyVault vault;
  late FormKeyService keys;
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    dir = Directory.systemTemp.createTempSync('ocideck_bundledlg_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    vault = FormKeyVault();
    keys = FormKeyService(SecretStore(storage: vault, canStore: true));
  });
  tearDown(() => deleteTempDir(dir));

  /// Een sleutel met teruggetypte herstelsleutel, en de formulieren erbij.
  Future<List<PublishedForm>> prepare(
    WidgetTester tester, {
    List<String>? texts,
    bool withKey = true,
    bool verified = true,
  }) async => (await tester.runAsync(() async {
    if (withKey) {
      await keys.create();
      if (verified) await keys.verifyRecovery((await keys.recoveryKey())!);
    }
    for (final text in texts ?? [formText()]) {
      await workspace.publishForm(text);
    }
    return (await workspace.publishedForms()).forms;
  }))!;

  Future<void> show(
    WidgetTester tester,
    List<PublishedForm> forms, {
    String language = 'nl',
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
              onPressed: () => showFormBundleDialog(
                context,
                workspace: workspace,
                forms: forms,
                keys: keys,
                now: () => DateTime.utc(2026, 10, 6),
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
  Finder containing(String s) => find.textContaining(s);

  Future<void> waitFor(WidgetTester tester, Finder finder) => pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    reason: 'wachtte op ${finder.describeMatch(Plurality.one)}',
  );

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(
        find.ancestor(of: find.text(label), matching: find.byType(TextField)),
      )
      .controller!
      .text;

  Future<void> make(WidgetTester tester) async {
    await tester.tap(text('Bundel maken'));
    await tester.pump();
  }

  testWidgets('beginwaarden komen uit het formulier zelf', (tester) async {
    await show(tester, await prepare(tester));
    expect(text('Offline uitnodigingspakket maken…'), findsOneWidget);
    expect(text('kook · v1 · nl'), findsOneWidget);
    expect(fieldText(tester, 'Naam voor de invuller'), 'Indo IT Kookboek-team');
    expect(fieldText(tester, 'Geldig tot (jjjj-mm-dd)'), '2026-12-01');
  });

  testWidgets('zonder sluitingsdag is de beginwaarde een jaar verder', (
    tester,
  ) async {
    final forms = await prepare(
      tester,
      texts: [formText().replaceFirst(' closes="2026-12-01"', '')],
    );
    await show(tester, forms);
    expect(fieldText(tester, 'Geldig tot (jjjj-mm-dd)'), '2027-10-06');
  });

  testWidgets('een bundel maken zegt waar hij staat en geeft de vingerafdruk', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final forms = await prepare(tester);
    final info = (await tester.runAsync(keys.read) as FormKeyPresent).info;
    await show(tester, forms);
    expect(text('Vingerafdruk'), findsNothing);
    await make(tester);
    final path = workspace.bundlePathOf(forms.single);
    await waitFor(tester, text('Bundel gemaakt (volgnummer 1): $path'));
    expect(File(path).existsSync(), isTrue);
    final fingerprint = formatFingerprint(info.fingerprint);
    expect(text(fingerprint), findsOneWidget);
    expect(
      containing('langs een andere weg dan het bundelbestand'),
      findsOneWidget,
    );
    await tester.ensureVisible(text('Vingerafdruk kopiëren'));
    await tester.pump();
    await tester.tap(text('Vingerafdruk kopiëren'));
    await tester.pump();
    expect(copied, [fingerprint]);
  });

  testWidgets('nog een keer: het volgnummer loopt door', (tester) async {
    final forms = await prepare(tester);
    await show(tester, forms);
    await make(tester);
    await waitFor(tester, containing('Bundel gemaakt (volgnummer 1)'));
    await make(tester);
    await waitFor(tester, containing('Bundel gemaakt (volgnummer 2)'));
  });

  testWidgets('een ander formulier zet de beginwaarden terug', (tester) async {
    final forms = await prepare(
      tester,
      texts: [
        formText(),
        formText(lang: 'en', controller: 'Cookbook team', closes: '2027-02-01'),
      ],
    );
    await show(tester, forms);
    await make(tester);
    await waitFor(tester, containing('Bundel gemaakt'));
    await tester.tap(find.byType(DropdownButton<PublishedForm>));
    await tester.pumpAndSettle();
    await tester.tap(text('kook · v1 · en').last);
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'Naam voor de invuller'), 'Cookbook team');
    expect(fieldText(tester, 'Geldig tot (jjjj-mm-dd)'), '2027-02-01');
    expect(
      text('Vingerafdruk'),
      findsNothing,
      reason: 'de vorige bundel is niet deze',
    );
    expect(containing('Bundel gemaakt'), findsNothing);
  });

  group('zegt waarom er niets is ondertekend', () {
    testWidgets('er is geen formulier', (tester) async {
      await show(tester, const []);
      expect(
        text('Er is geen formulier in de werkmap om een bundel voor te maken.'),
        findsOneWidget,
      );
      expect(text('Bundel maken'), findsNothing);
      expect(text('Sluiten'), findsOneWidget);
    });

    testWidgets('er is geen redactiesleutel', (tester) async {
      await show(tester, await prepare(tester, withKey: false));
      await make(tester);
      await waitFor(
        tester,
        text(
          'Er is nog geen redactiesleutel. Maak er een aan onder Redactiesleutel… voordat je een uitnodigingspakket maakt.',
        ),
      );
      expect(
        File(
          workspace.bundlePathOf(
            (await tester.runAsync(
              () async => (await workspace.publishedForms()).forms.single,
            ))!,
          ),
        ).existsSync(),
        isFalse,
      );
    });

    testWidgets('de sleutelhanger geeft geen antwoord', (tester) async {
      final forms = await prepare(tester);
      vault.failRead = true;
      await show(tester, forms);
      await make(tester);
      await waitFor(
        tester,
        text('De sleutelhanger is niet te lezen. Er is niets ondertekend.'),
      );
    });

    testWidgets('de herstelsleutel is niet teruggetypt', (tester) async {
      await show(tester, await prepare(tester, verified: false));
      await make(tester);
      await waitFor(
        tester,
        containing('Controleer eerst je herstelsleutel onder Redactiesleutel…'),
      );
    });

    testWidgets('een naam ontbreekt', (tester) async {
      await show(tester, await prepare(tester));
      await tester.enterText(
        find.widgetWithText(TextField, 'Naam voor de invuller'),
        '   ',
      );
      await make(tester);
      await waitFor(tester, text('Vul een naam in van hooguit 80 tekens.'));
    });

    testWidgets('de geldigheid is geen datum, of eindigt te vroeg', (
      tester,
    ) async {
      await show(tester, await prepare(tester));
      final field = find.widgetWithText(TextField, 'Geldig tot (jjjj-mm-dd)');
      await tester.enterText(field, 'morgen');
      await make(tester);
      await waitFor(
        tester,
        text('Geldig tot moet een bestaande datum zijn, als jjjj-mm-dd.'),
      );
      await tester.enterText(field, '2026-11-30');
      await make(tester);
      await waitFor(
        tester,
        text(
          'Geldig tot mag niet vóór de sluitingsdag van het formulier liggen.',
        ),
      );
    });

    testWidgets('een bundel in de werkmap die niet te lezen is', (
      tester,
    ) async {
      final forms = await prepare(tester);
      final path = workspace.bundlePathOf(forms.single);
      File(path).writeAsStringSync('geen bundel');
      await show(tester, forms);
      await make(tester);
      await waitFor(tester, containing('Controleer: $path'));
      expect(File(path).readAsStringSync(), 'geen bundel');
    });

    testWidgets('een plek waar niet te schrijven valt', (tester) async {
      final forms = await prepare(tester);
      Directory(workspace.bundlePathOf(forms.single)).createSync();
      await show(tester, forms);
      await make(tester);
      await waitFor(
        tester,
        text('De bundel kon niet worden opgeslagen in de werkmap.'),
      );
    });

    testWidgets('een bewaartermijn die de bundel niet draagt', (tester) async {
      final forms = await prepare(
        tester,
        texts: [formText().replaceFirst('"6 maanden"', '"${'x' * 201}"')],
      );
      await show(tester, forms);
      await make(tester);
      await waitFor(tester, containing('De bundel kon niet worden gemaakt ('));
    });
  });

  testWidgets('tijdens het werk staat de knop vast en komt er één bundel', (
    tester,
  ) async {
    final forms = await prepare(tester);
    vault.readGate = Completer<void>();
    await show(tester, forms);
    await make(tester);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: text('Bundel maken'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    final dropdown = tester.widget<DropdownButton<PublishedForm>>(
      find.byType(DropdownButton<PublishedForm>),
    );
    expect(dropdown.onChanged, isNull);
    vault.readGate!.complete();
    await waitFor(tester, containing('Bundel gemaakt (volgnummer 1)'));
    final again = tester.widget<FilledButton>(
      find.ancestor(
        of: text('Bundel maken'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(again.onPressed, isNotNull, reason: 'na het werk weer los');
  });

  testWidgets('twee keer tikken voordat het venster bijwerkt maakt één bundel', (
    tester,
  ) async {
    final forms = await prepare(tester);
    // Hoeveel keer één bundel de sleutelhanger leest, vooraf gemeten op dezelfde manier.
    final before = vault.reads;
    await tester.runAsync(
      () => makeFormBundle(
        workspace,
        forms.single,
        keys: keys,
        organiserName: 'Redactie',
        expires: '2026-12-15',
        now: DateTime.utc(2026, 10, 6),
      ),
    );
    final perBundle = vault.reads - before;
    expect(perBundle, greaterThan(0));
    File(workspace.bundlePathOf(forms.single)).deleteSync();
    await show(tester, forms);
    final start = vault.reads;
    await tester.tap(text('Bundel maken'));
    await tester.tap(text('Bundel maken'));
    await waitFor(tester, containing('Bundel gemaakt (volgnummer 1)'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(vault.reads - start, perBundle, reason: 'de tweede tik deed niets');
  });

  testWidgets('de titel is een kop en een melding wordt voorgelezen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester, await prepare(tester, withKey: false));
    final header = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.header == true,
    );
    expect(header, findsOneWidget);
    expect(
      find.descendant(
        of: header,
        matching: text('Offline uitnodigingspakket maken…'),
      ),
      findsOneWidget,
    );
    await make(tester);
    const message =
        'Er is nog geen redactiesleutel. Maak er een aan onder Redactiesleutel… voordat je een uitnodigingspakket maakt.';
    await waitFor(tester, text(message));
    expect(
      tester.getSemantics(text(message)).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(
      tester.getSemantics(text('Bundel maken')).flagsCollection.isLiveRegion,
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets(
    'een formulier dat de kern niet leest, noemt zichzelf als reden',
    (tester) async {
      final real = (await prepare(tester)).single;
      final broken = PublishedForm(
        id: real.id,
        version: real.version,
        lang: real.lang,
        text: 'geen formulier',
        path: real.path,
      );
      await show(tester, [broken]);
      await make(tester);
      await waitFor(
        tester,
        containing('De bundel kon niet worden gemaakt (formulier).'),
      );
    },
  );

  testWidgets('het laatste formulier van de lijst is het voorgestelde', (
    tester,
  ) async {
    final forms = await prepare(
      tester,
      texts: [
        formText(),
        formText(lang: 'en', controller: 'Cookbook team'),
      ],
    );
    expect(forms.map((f) => f.lang), ['en', 'nl'], reason: 'gesorteerd op pad');
    await show(tester, forms);
    expect(text('kook · v1 · nl'), findsOneWidget);
    expect(fieldText(tester, 'Naam voor de invuller'), 'Indo IT Kookboek-team');
  });

  testWidgets('de knoppen zeggen in het Engels wat ze doen', (tester) async {
    await show(tester, await prepare(tester), language: 'en');
    expect(text('Create offline invitation package…'), findsOneWidget);
    expect(text('Create bundle'), findsOneWidget);
    expect(text('Name for the respondent'), findsOneWidget);
    expect(text('Close'), findsOneWidget);
    await tester.tap(text('Create bundle'));
    await tester.pump();
    await waitFor(tester, containing('Bundle created (sequence number 1)'));
    expect(text('Fingerprint'), findsOneWidget);
    expect(text('Copy fingerprint'), findsOneWidget);
  });

  group('het team', () {
    Future<FormEditorCard> editor(WidgetTester tester, String name) async =>
        (await tester.runAsync(() async {
          final other = FormKeyService(
            SecretStore(storage: FormKeyVault(), canStore: true),
          );
          await other.create();
          return editorCardOf(
            (await other.read() as FormKeyPresent).info,
            name,
          );
        }))!;

    testWidgets(
      'zonder team staat er geen regel over wie er nog meer in staat',
      (tester) async {
        await show(tester, await prepare(tester));
        expect(containing('Naast jou in de bundel'), findsNothing);
      },
    );

    testWidgets('met een team staan de namen erbij, en in de bundel', (
      tester,
    ) async {
      final forms = await prepare(tester);
      final a = await editor(tester, 'Eerste');
      final b = await editor(tester, 'Tweede');
      await tester.runAsync(() => workspace.saveTeam(FormTeam([a, b])));
      await show(tester, forms);
      await waitFor(tester, text('Naast jou in de bundel: Eerste, Tweede.'));
      await make(tester);
      await waitFor(tester, containing('Bundel gemaakt (volgnummer 1)'));
      final stored = (await tester.runAsync(
        () => workspace.bundlesOf('kook'),
      ))!;
      expect(
        [
          for (final o
              in (jsonDecode(stored.bundles.single.text) as Map)['organisers']
                  as List)
            (o as Map)['name'],
        ],
        ['Indo IT Kookboek-team', 'Eerste', 'Tweede'],
      );
    });

    testWidgets(
      'een tweede redacteur is een herstelweg: de herstelsleutel hoeft niet terug',
      (tester) async {
        final forms = await prepare(tester, verified: false);
        await show(tester, forms);
        await make(tester);
        await waitFor(
          tester,
          containing('of voeg een tweede redacteur toe onder Team…'),
        );
        final a = await editor(tester, 'Tweede');
        await tester.runAsync(() => workspace.saveTeam(FormTeam([a])));
        await tester.pump();
        await make(tester);
        await waitFor(tester, containing('Bundel gemaakt (volgnummer 1)'));
      },
    );

    testWidgets('een team dat niet te lezen is: niets ondertekend', (
      tester,
    ) async {
      final forms = await prepare(tester);
      File(workspace.teamPath).writeAsStringSync('geen team');
      await show(tester, forms);
      await make(tester);
      await waitFor(
        tester,
        text(
          'Het bestand team.json in de werkmap is niet te lezen. Er wordt niets ondertekend.',
        ),
      );
      expect(containing('Naast jou in de bundel'), findsNothing);
      expect(File(workspace.bundlePathOf(forms.single)).existsSync(), isFalse);
    });
  });

  testWidgets('Sluiten sluit het venster', (tester) async {
    await show(tester, await prepare(tester));
    await tester.tap(text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
