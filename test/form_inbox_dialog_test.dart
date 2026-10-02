// De Inbox van een organisator (FORM_INTAKE.md §7.2), eerste vorm: een werkmap
// kiezen, formulieren toevoegen, pakketten binnenhalen en zien wat er van elk
// geworden is.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/state/forms_provider.dart';
import 'package:ocideck/widgets/forms/form_inbox_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
Future<void> settleIo(WidgetTester tester, Finder until) => pumpUntil(
  tester,
  () => until.evaluate().isNotEmpty,
  reason: 'wachtte op ${until.describeMatch(Plurality.one)}',
);

Future<void> tapAndWait(WidgetTester tester, Finder tap, Finder until) async {
  await tester.tap(tap);
  await settleIo(tester, until);
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
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          formsWorkspaceProvider.overrideWith(() => _Workspace(workspace)),
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
      text('Een gewone zip is onderweg niet versleuteld.'),
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

  testWidgets('Sluiten sluit het venster', (tester) async {
    await open(tester, _Picks());
    await tester.tap(text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
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
