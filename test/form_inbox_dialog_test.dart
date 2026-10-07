// De Inbox van een organisator (FORM_INTAKE.md §7.2), eerste vorm: een werkmap
// kiezen, formulieren toevoegen, pakketten binnenhalen en zien wat er van elk
// geworden is.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/state/form_keys_provider.dart';
import 'package:ocideck/state/forms_provider.dart';
import 'package:ocideck/widgets/forms/form_inbox_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/form_key_vault.dart';
import 'support/pump_until.dart';
import 'support/temp_dir.dart';

const String kook = '''<!-- form id=kook version=1 -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

Uint8List zipOf({
  String naam = 'Sari',
  String id = 'abcdefghijklmnopqrstuvwxya',
}) {
  return buildFormPackage(
    submission: kook.replaceFirst(
      '<!-- answer -->\n<!-- /field id=naam -->',
      '<!-- answer -->\n$naam\n<!-- /field id=naam -->',
    ),
    template: kook,
    spec: (parseForm(kook) as ParsedForm).spec,
    images: const {},
    submissionId: id,
    created: DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
}

class _Workspace extends FormsWorkspaceNotifier {
  _Workspace(this.initial);

  final String? initial;

  @override
  String? build() => initial;
}

class _Picks {
  String? folder;
  String? form;
  List<({String name, Uint8List bytes})> packages = [];
  final List<String> titles = [];

  FormInboxPickers get pickers => FormInboxPickers(
    folder: (title) async {
      titles.add(title);
      return folder;
    },
    form: (title) async {
      titles.add(title);
      return form;
    },
    packages: (title) async {
      titles.add(title);
      return packages;
    },
  );
}

/// Echte bestands-I/O loopt niet af binnen de nep-klok van een widgettest; geef
/// haar echte tijd, beeld voor beeld, tot [until] er is. (`pumpAndSettle` is hier
/// geen optie: de voortgangsbalk blijft bewegen en het wachten zou nooit eindigen.)
Future<void> settleIo(
  WidgetTester tester,
  Finder until, {
  Duration timeout = const Duration(seconds: 10),
}) => pumpUntil(
  tester,
  () => until.evaluate().isNotEmpty,
  timeout: timeout,
  reason: 'wachtte op ${until.describeMatch(Plurality.one)}',
);

Future<void> tapAndWait(
  WidgetTester tester,
  Finder tap,
  Finder until, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await tester.tap(tap);
  await settleIo(tester, until, timeout: timeout);
}

void main() {
  late Directory dir;
  late String root;
  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('ocideck_inbox_');
    root = p.join(dir.path, 'werkmap');
  });
  tearDown(() => deleteTempDir(dir));

  Future<ProviderContainer> open(
    WidgetTester tester,
    _Picks picks, {
    String? workspace,
    List<Override> extraOverrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          formsWorkspaceProvider.overrideWith(() => _Workspace(workspace)),
          ...extraOverrides,
        ],
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showFormInboxDialog(
                  context,
                  pickers: picks.pickers,
                  now: () => DateTime.utc(2026, 10, 6),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Dialog)));
  }

  Finder text(String s) => find.text(s);
  Finder containing(String s) => find.textContaining(s);

  testWidgets('zonder werkmap vraagt het venster er eerst om', (tester) async {
    await open(tester, _Picks());
    expect(text('Inzendingen'), findsOneWidget);
    expect(containing('Nog geen werkmap gekozen'), findsOneWidget);
    expect(text('Werkmap kiezen…'), findsOneWidget);
    expect(text('Formulieren'), findsNothing);
    expect(text('Pakketten binnenhalen…'), findsNothing);
  });

  testWidgets('een werkmap kiezen toont de rest en onthoudt de keuze', (
    tester,
  ) async {
    final picks = _Picks()..folder = root;
    final container = await open(tester, picks);
    await tapAndWait(tester, text('Werkmap kiezen…'), text('Formulieren'));
    expect(picks.titles, ['Kies de werkmap voor inzendingen']);
    expect(container.read(formsWorkspaceProvider), root);
    expect(text(root), findsOneWidget);
    expect(text('Formulieren'), findsOneWidget);
    expect(containing('Nog geen formulier toegevoegd'), findsOneWidget);
    expect(containing('Inzendingen in de werkmap: 0'), findsOneWidget);
    expect(
      containing('Een gewone zip is onderweg niet versleuteld.'),
      findsOneWidget,
    );
    expect(
      containing(
        'Een verzegeld bestand (.zip.age) opent met je redactiesleutel.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('annuleren bij het kiezen verandert niets', (tester) async {
    await open(tester, _Picks());
    await tester.tap(text('Werkmap kiezen…'));
    await tester.pump();
    expect(containing('Nog geen werkmap gekozen'), findsOneWidget);
  });

  group('formulieren', () {
    testWidgets('een formulier toevoegen, en dezelfde nog eens', (
      tester,
    ) async {
      final picks = _Picks()..form = kook;
      await open(tester, picks, workspace: root);
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Formulier toegevoegd: kook · v1.'),
      );
      expect(picks.titles, ['Kies het formulier om toe te voegen']);
      await settleIo(tester, text('kook · v1'));
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Dit formulier stond er al.'),
      );
    });

    testWidgets('een andere tekst voor dezelfde versie wordt uitgelegd', (
      tester,
    ) async {
      final picks = _Picks()..form = kook;
      await open(tester, picks, workspace: root);
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Formulier toegevoegd: kook · v1.'),
        // De volledige Linux-suite mat door runnerbelasting meer dan 10 s voor
        // deze echte bestands-I/O; geïsoleerd is dezelfde voorwaarde direct groen.
        timeout: const Duration(seconds: 30),
      );
      picks.form = kook.replaceAll('Inzending', 'Anders');
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        containing('staat er al met een andere tekst'),
      );
    });

    testWidgets('wat geen formulier is wordt geweigerd', (tester) async {
      final picks = _Picks()..form = 'Gewoon tekst.';
      await open(tester, picks, workspace: root);
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        containing('geen formulier dat gepubliceerd kan worden'),
      );
    });

    testWidgets('annuleren zegt niets', (tester) async {
      final picks = _Picks();
      await open(tester, picks, workspace: root);
      await tester.tap(text('Formulier toevoegen…'));
      await pumpUntil(tester, () => picks.titles.isNotEmpty);
      await tester.pump();
      expect(containing('Formulier toegevoegd'), findsNothing);
      expect(containing('geen formulier dat'), findsNothing);
    });

    testWidgets('een schijf waar niet in te schrijven valt wordt gemeld', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await Directory(root).create(recursive: true);
        await File(p.join(root, 'forms')).writeAsString('geen map');
      });
      final picks = _Picks()..form = kook;
      await open(tester, picks, workspace: root);
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Het formulier kon niet worden opgeslagen.'),
      );
    });
  });

  group('pakketten binnenhalen', () {
    testWidgets('zonder formulier kan het niet', (tester) async {
      await open(tester, _Picks(), workspace: root);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: text('Pakketten binnenhalen…'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('elk bestand krijgt zijn regel, en de teller loopt mee', (
      tester,
    ) async {
      final picks = _Picks()
        ..form = kook
        ..packages = [
          (name: 'goed.zip', bytes: zipOf()),
          (
            name: 'fout.zip',
            bytes: zipOf(naam: '', id: 'abcdefghijklmnopqrstuvwxyb'),
          ),
          (name: 'dubbel.zip', bytes: zipOf()),
          (name: 'kapot.zip', bytes: Uint8List.fromList([1, 2, 3])),
        ];
      await open(tester, picks, workspace: root);
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Formulier toegevoegd: kook · v1.'),
      );
      await settleIo(tester, text('kook · v1'));
      await tapAndWait(
        tester,
        text('Pakketten binnenhalen…'),
        containing('Inzendingen in de werkmap: 2'),
        // Vier ZIP-bestanden doen echte bestands-I/O. Onder de volledige
        // Linux-suite kan dat langer dan de algemene 10 s duren; de concrete
        // UI-naconditie blijft leidend en de wacht blijft begrensd.
        timeout: const Duration(seconds: 30),
      );
      expect(picks.titles.last, 'Kies de pakketten om binnen te halen');
      expect(text('goed.zip: binnengehaald.'), findsOneWidget);
      expect(
        text('fout.zip: binnengehaald, maar er zijn punten om na te lopen.'),
        findsOneWidget,
      );
      expect(text('dubbel.zip: stond er al.'), findsOneWidget);
      expect(
        text('kapot.zip: geen inzendpakket dat OciDeck kan lezen.'),
        findsOneWidget,
      );
      expect(containing('Inzendingen in de werkmap: 2'), findsOneWidget);
      // De lijst eronder leest mee: een regel per inzending, de foute als 'om na te lopen'.
      await settleIo(tester, text('abcdefgh…'));
      expect(text('abcdefgh…'), findsNWidgets(2));
      expect(containing('Om na te lopen'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // Het register is er, met beide rijen.
      final register = (await tester.runAsync(
        () => File(p.join(root, 'overview.md')).readAsString(),
      ))!;
      expect(register, contains('abcdefghijklmnopqrstuvwxya'));
      expect(register, contains('needs-fixing'));
    });

    testWidgets(
      'verzegelde bestanden: geopend met de sleutel, of de reden waarom niet',
      (tester) async {
        final vault = FormKeyVault();
        final service = FormKeyService(
          SecretStore(storage: vault, canStore: true),
        );
        final other = FormKeyService(
          SecretStore(storage: FormKeyVault(), canStore: true),
        );
        final sealed = (await tester.runAsync(() async {
          final mine = ((await service.create()) as FormKeyWritten).info;
          final theirs = ((await other.create()) as FormKeyWritten).info;
          Future<Uint8List> seal(String to, Uint8List zip) async =>
              (await sealFormPackage(zip, recipients: [to]) as FormSealed)
                  .bytes;
          final changed = await seal(
            mine.recipient,
            zipOf(id: 'abcdefghijklmnopqrstuvwxyc'),
          );
          changed[changed.length - 1] ^= 1;
          return (
            mine: await seal(mine.recipient, zipOf()),
            theirs: await seal(
              theirs.recipient,
              zipOf(id: 'abcdefghijklmnopqrstuvwxyb'),
            ),
            changed: changed,
          );
        }))!;
        final picks = _Picks()
          ..form = kook
          ..packages = [
            (name: 'mijn.zip.age', bytes: sealed.mine),
            (name: 'andermans.zip.age', bytes: sealed.theirs),
            (name: 'veranderd.zip.age', bytes: sealed.changed),
            (
              name: 'pantser.age',
              bytes: Uint8List.fromList(
                '-----BEGIN AGE ENCRYPTED FILE-----\nAAAA\n'.codeUnits,
              ),
            ),
          ];
        await open(
          tester,
          picks,
          workspace: root,
          extraOverrides: [formKeyServiceProvider.overrideWithValue(service)],
        );
        await tapAndWait(
          tester,
          text('Formulier toevoegen…'),
          text('Formulier toegevoegd: kook · v1.'),
        );
        await settleIo(tester, text('kook · v1'));
        await tapAndWait(
          tester,
          text('Pakketten binnenhalen…'),
          containing('Inzendingen in de werkmap: 1'),
        );
        expect(
          text('mijn.zip.age: verzegeld pakket geopend en binnengehaald.'),
          findsOneWidget,
        );
        expect(
          text(
            'andermans.zip.age: dit pakket is niet voor jouw redactiesleutel verzegeld.',
          ),
          findsOneWidget,
        );
        expect(
          text(
            'veranderd.zip.age: dit pakket is veranderd of afgebroken en wordt niet geopend.',
          ),
          findsOneWidget,
        );
        expect(
          text('pantser.age: geen verzegeld pakket dat OciDeck kan lezen.'),
          findsOneWidget,
        );
        expect(containing('Inzendingen in de werkmap: 1'), findsOneWidget);
        IconData iconOf(String line) => tester
            .widget<Icon>(
              find.descendant(
                of: find
                    .ancestor(of: text(line), matching: find.byType(Row))
                    .first,
                matching: find.byType(Icon),
              ),
            )
            .icon!;
        expect(
          iconOf('mijn.zip.age: verzegeld pakket geopend en binnengehaald.'),
          Icons.check_circle_outline,
        );
        expect(
          iconOf(
            'andermans.zip.age: dit pakket is niet voor jouw redactiesleutel verzegeld.',
          ),
          Icons.error_outline,
        );
      },
    );

    testWidgets('verzegeld zonder redactiesleutel zegt wat er te doen valt', (
      tester,
    ) async {
      final empty = FormKeyService(
        SecretStore(storage: FormKeyVault(), canStore: true),
      );
      final other = FormKeyService(
        SecretStore(storage: FormKeyVault(), canStore: true),
      );
      final bytes = (await tester.runAsync(() async {
        final theirs = ((await other.create()) as FormKeyWritten).info;
        return (await sealFormPackage(zipOf(), recipients: [theirs.recipient])
                as FormSealed)
            .bytes;
      }))!;
      final picks = _Picks()
        ..form = kook
        ..packages = [(name: 'x.zip.age', bytes: bytes)];
      await open(
        tester,
        picks,
        workspace: root,
        extraOverrides: [formKeyServiceProvider.overrideWithValue(empty)],
      );
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Formulier toegevoegd: kook · v1.'),
      );
      await settleIo(tester, text('kook · v1'));
      await tapAndWait(
        tester,
        text('Pakketten binnenhalen…'),
        containing(
          'x.zip.age: dit pakket is verzegeld en er is nog geen redactiesleutel',
        ),
      );
      expect(containing('Inzendingen in de werkmap: 0'), findsOneWidget);
    });

    testWidgets('een formulier dat niet is toegevoegd wordt benoemd', (
      tester,
    ) async {
      final other = FormInboxPickers(
        folder: (_) async => null,
        form: (_) async => kook.replaceFirst('id=kook', 'id=ander'),
        packages: (_) async => [(name: 'x.zip', bytes: zipOf())],
      );
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            formsWorkspaceProvider.overrideWith(() => _Workspace(root)),
          ],
          child: MaterialApp(
            locale: const Locale('nl'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: FormInboxDialog(pickers: other)),
          ),
        ),
      );
      await tester.pump();
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Formulier toegevoegd: ander · v1.'),
      );
      await settleIo(tester, text('ander · v1'));
      await tapAndWait(
        tester,
        text('Pakketten binnenhalen…'),
        containing('x.zip:'),
      );
      expect(
        text(
          'x.zip: dit formulier is niet toegevoegd, of niet in deze versie. Voeg het formulier eerst toe.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'een register dat niet te lezen is wordt gemeld, de inzending staat er wel',
      (tester) async {
        await tester.runAsync(() async {
          await Directory(root).create(recursive: true);
          await File(
            p.join(root, 'overview.md'),
          ).writeAsString('Mijn aantekeningen.\n');
        });
        final picks = _Picks()
          ..form = kook
          ..packages = [(name: 'goed.zip', bytes: zipOf())];
        await open(tester, picks, workspace: root);
        await tapAndWait(
          tester,
          text('Formulier toevoegen…'),
          text('Formulier toegevoegd: kook · v1.'),
        );
        await settleIo(tester, text('kook · v1'));
        await tapAndWait(
          tester,
          text('Pakketten binnenhalen…'),
          containing('goed.zip:'),
        );
        expect(
          text(
            'goed.zip: binnengehaald, maar het register kon niet worden bijgewerkt. Controleer overview.md.',
          ),
          findsOneWidget,
        );
        await settleIo(tester, containing('Inzendingen in de werkmap: 1'));
      },
    );

    testWidgets('een werkmap waar niet te schrijven valt wordt gemeld', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await Directory(root).create(recursive: true);
        await File(p.join(root, 'submissions')).writeAsString('geen map');
      });
      final picks = _Picks()
        ..form = kook
        ..packages = [(name: 'goed.zip', bytes: zipOf())];
      await open(tester, picks, workspace: root);
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Formulier toegevoegd: kook · v1.'),
      );
      await settleIo(tester, text('kook · v1'));
      await tapAndWait(
        tester,
        text('Pakketten binnenhalen…'),
        containing('goed.zip:'),
      );
      expect(
        text('goed.zip: kon niet worden opgeslagen in de werkmap.'),
        findsOneWidget,
      );
    });

    testWidgets('geen keuze is geen actie', (tester) async {
      final picks = _Picks()..form = kook;
      await open(tester, picks, workspace: root);
      await tapAndWait(
        tester,
        text('Formulier toevoegen…'),
        text('Formulier toegevoegd: kook · v1.'),
      );
      await settleIo(tester, text('kook · v1'));
      await tester.tap(text('Pakketten binnenhalen…'));
      await pumpUntil(
        tester,
        () => picks.titles.last == 'Kies de pakketten om binnen te halen',
      );
      await tester.pump();
      expect(containing('binnengehaald'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  testWidgets('Redactiesleutel… opent het sleutelvenster, ook zonder werkmap', (
    tester,
  ) async {
    final service = FormKeyService(
      SecretStore(storage: FormKeyVault(), canStore: true),
    );
    await open(
      tester,
      _Picks(),
      extraOverrides: [formKeyServiceProvider.overrideWithValue(service)],
    );
    await tester.tap(text('Redactiesleutel…'));
    await tester.pump();
    await tester.pump();
    await pumpUntil(
      tester,
      () => text('Redactiesleutel aanmaken').evaluate().isNotEmpty,
    );
    expect(
      find.textContaining('prijs van een server die niets kan lezen'),
      findsOneWidget,
    );
  });

  testWidgets('Sluiten sluit het venster', (tester) async {
    await open(tester, _Picks());
    await tester.tap(text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  group('team', () {
    OutlinedButton button(WidgetTester tester) => tester.widget<OutlinedButton>(
      find.ancestor(of: text('Team…'), matching: find.byType(OutlinedButton)),
    );

    testWidgets('zonder werkmap is er geen team om te beheren', (tester) async {
      await open(tester, _Picks());
      expect(button(tester).onPressed, isNull);
    });

    testWidgets('met een werkmap opent het het teamvenster', (tester) async {
      await open(tester, _Picks(), workspace: root);
      expect(button(tester).onPressed, isNotNull);
      // Onderaan een venster dat scrolt: met een werkmap is er veel boven.
      await tester.ensureVisible(text('Team…'));
      await tester.pump();
      await tester.tap(text('Team…'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => text('Er is nog niemand naast jou.').evaluate().isNotEmpty,
      );
      expect(
        find.widgetWithText(TextField, 'Plak de kaart van de redacteur'),
        findsOneWidget,
      );
    });
  });

  group('uitnodigingspakket maken', () {
    OutlinedButton button(WidgetTester tester) => tester.widget<OutlinedButton>(
      find.ancestor(
        of: text('Offline uitnodigingspakket maken…'),
        matching: find.byType(OutlinedButton),
      ),
    );

    testWidgets('zonder formulier kan het niet', (tester) async {
      await open(tester, _Picks(), workspace: root);
      expect(button(tester).onPressed, isNull);
    });

    testWidgets('met een formulier opent het het bundelvenster', (
      tester,
    ) async {
      await tester.runAsync(() => FormWorkspace(root).publishForm(kook));
      await open(tester, _Picks(), workspace: root);
      await pumpUntil(tester, () => button(tester).onPressed != null);
      await tester.tap(text('Offline uitnodigingspakket maken…'));
      await tester.pumpAndSettle();
      expect(text('Bundel maken'), findsOneWidget);
      expect(text('kook · v1'), findsWidgets);
    });
  });

  group('boek samenstellen', () {
    testWidgets('zonder formulier kan het niet', (tester) async {
      await open(tester, _Picks(), workspace: root);
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: text('Boek samenstellen…'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('met een formulier opent het het samenstelvenster', (
      tester,
    ) async {
      await tester.runAsync(() => FormWorkspace(root).publishForm(kook));
      await open(tester, _Picks(), workspace: root);
      await pumpUntil(
        tester,
        () =>
            tester
                .widget<OutlinedButton>(
                  find.ancestor(
                    of: text('Boek samenstellen…'),
                    matching: find.byType(OutlinedButton),
                  ),
                )
                .onPressed !=
            null,
      );
      await tester.tap(text('Boek samenstellen…'));
      await tester.pumpAndSettle();
      expect(text('Hoofdstuksjabloon kiezen…'), findsOneWidget);
      expect(text('Samenstellen'), findsOneWidget);
    });
  });

  testWidgets('Register openen sluit het venster en opent het register', (
    tester,
  ) async {
    await open(tester, _Picks(), workspace: root);
    await tester.tap(text('Register openen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'Werkkopie openen maakt de kopie, sluit het venster en laat wat binnenkwam staan',
    (tester) async {
      await tester.runAsync(() async {
        final workspace = FormWorkspace(root);
        await workspace.publishForm(kook);
        await importFormPackage(
          workspace,
          zipOf(),
          now: DateTime.utc(2026, 10, 6),
        );
      });
      await open(tester, _Picks(), workspace: root);
      await settleIo(tester, text('abcdefgh…'));
      // Het venster scrolt: de lijst staat onder de knoppen.
      await Scrollable.ensureVisible(
        tester.element(text('abcdefgh…')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(text('abcdefgh…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester, text('Werkkopie openen'));
      await Scrollable.ensureVisible(
        tester.element(text('Werkkopie openen')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(text('Werkkopie openen'));
      final copy = File(
        p.join(
          root,
          'submissions',
          'abcdefghijklmnopqrstuvwxya',
          'submission.edit.md',
        ),
      );
      await pumpUntil(tester, () => find.byType(Dialog).evaluate().isEmpty);
      final exists = (await tester.runAsync(copy.exists))!;
      expect(exists, isTrue);
    },
  );

  testWidgets(
    'het beginscherm biedt Inzendingen aan zodra de functie zichtbaar is',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [formsRevealProvider.overrideWithValue(true)],
          child: const OciDeckApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inzendingen'), findsOneWidget);
      await tester.tap(find.text('Inzendingen'));
      await tester.pumpAndSettle();
      expect(find.byType(FormInboxDialog), findsOneWidget);
    },
  );

  testWidgets('het beginscherm verbergt Inzendingen als de functie uit staat', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    expect(find.text('Inzendingen'), findsNothing);
  });
}
