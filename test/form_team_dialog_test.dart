// Het team van de redactie vanuit de Inbox (FORM_INTAKE.md §7.6): een redacteur toevoegen met zijn
// kaart en de teruggetypte vingerafdruk, verwijderen, en elke zin die zegt waarom het niet ging.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/widgets/forms/form_team_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_key_vault.dart';
import 'support/pump_until.dart';
import 'support/temp_dir.dart';

/// Een werkmap die het bewaren van het team vasthoudt tot de test hem loslaat: zo is te zien wat het
/// venster doet terwijl het werk nog loopt.
class _GatedWorkspace extends FormWorkspace {
  _GatedWorkspace(super.root);

  Completer<void>? gate;

  @override
  Future<bool> saveTeam(FormTeam team) async {
    await gate?.future;
    return super.saveTeam(team);
  }
}

void main() {
  late Directory dir;
  late _GatedWorkspace workspace;
  late FormKeyVault vault;
  late FormKeyService keys;
  late FormKeyInfo ownerInfo;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    dir = Directory.systemTemp.createTempSync('ocideck_teamdlg_');
    workspace = _GatedWorkspace(p.join(dir.path, 'werkmap'));
    vault = FormKeyVault();
    keys = FormKeyService(SecretStore(storage: vault, canStore: true));
  });
  tearDown(() => deleteTempDir(dir));

  /// De eigen sleutel van de eigenaar, aangemaakt.
  Future<void> ownKey(WidgetTester tester) async {
    ownerInfo = (await tester.runAsync(() async {
      await keys.create();
      return (await keys.read() as FormKeyPresent).info;
    }))!;
  }

  Future<FormEditorCard> cardOf(WidgetTester tester, String name) async =>
      (await tester.runAsync(() async {
        final service = FormKeyService(
          SecretStore(storage: FormKeyVault(), canStore: true),
        );
        await service.create();
        return editorCardOf(
          (await service.read() as FormKeyPresent).info,
          name,
        );
      }))!;

  Future<void> show(WidgetTester tester, {String language = 'nl'}) async {
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
              onPressed: () =>
                  showFormTeamDialog(context, workspace: workspace, keys: keys),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  Finder text(String s) => find.text(s);
  Finder containing(String s) => find.textContaining(s);

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
  }) => pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    timeout: timeout,
    reason: 'wachtte op ${finder.describeMatch(Plurality.one)}',
  );

  final cardField = find.widgetWithText(
    TextField,
    'Plak de kaart van de redacteur',
  );
  final fingerprintField = find.widgetWithText(
    TextField,
    'Vingerafdruk van de kaart',
  );

  /// Plak een kaart en kies Kaart controleren.
  Future<void> paste(WidgetTester tester, String cardText) async {
    await tester.enterText(cardField, cardText);
    // Het veld groeit met wat erin staat: pas na een frame staat de knop op zijn plek.
    await tester.pump();
    await tester.ensureVisible(text('Kaart controleren'));
    await tester.pump();
    await tester.tap(text('Kaart controleren'));
    await tester.pump();
  }

  /// Tik de vingerafdruk en kies Toevoegen.
  Future<void> confirm(WidgetTester tester, String fingerprint) async {
    await tester.enterText(fingerprintField, fingerprint);
    await tester.pump();
    await tester.ensureVisible(text('Toevoegen'));
    await tester.pump();
    await tester.tap(text('Toevoegen'));
    await tester.pump();
  }

  ButtonStyleButton buttonOf(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );

  Future<List<String>> teamNames(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final read = await workspace.readTeam() as FormTeamStored;
        return [for (final e in read.team.editors) e.name];
      }))!;

  testWidgets('een leeg team, met uitleg en een kop', (tester) async {
    await ownKey(tester);
    final semantics = tester.ensureSemantics();
    await show(tester);
    await waitFor(tester, text('Er is nog niemand naast jou.'));
    expect(containing('naast jou die in elke bundel staan'), findsOneWidget);
    final header = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.header == true,
    );
    expect(find.descendant(of: header, matching: text('Team')), findsOneWidget);
    expect(File(workspace.teamPath).existsSync(), isFalse);
    semantics.dispose();
  });

  testWidgets('een redacteur toevoegen: de kaart, dan de vingerafdruk', (
    tester,
  ) async {
    await ownKey(tester);
    final card = await cardOf(tester, 'Tweede redacteur');
    await show(tester);
    await waitFor(tester, text('Er is nog niemand naast jou.'));
    await paste(tester, card.toText());
    // Na het lezen staat alleen de naam in beeld: de vingerafdruk van de kaart juist niet, want
    // wie hem van het scherm overtikt controleert niets.
    expect(
      containing(
        'Kaart van Tweede redacteur. Typ de vingerafdruk van deze kaart',
      ),
      findsOneWidget,
    );
    expect(containing(formatFingerprint(card.fingerprint)), findsNothing);
    expect(containing(card.fingerprint), findsNothing);
    expect(tester.widget<TextField>(cardField).enabled, isFalse);
    await confirm(tester, formatFingerprint(card.fingerprint));
    await waitFor(
      tester,
      text(
        'Tweede redacteur is toegevoegd. Maak het uitnodigingspakket opnieuw om Tweede redacteur erin op te nemen.',
      ),
    );
    expect(await teamNames(tester), ['Tweede redacteur']);
    // Nu staat hij in de lijst, met zijn vingerafdruk.
    await waitFor(tester, text(formatFingerprint(card.fingerprint)));
    expect(text('Er is nog niemand naast jou.'), findsNothing);
    expect(cardField, findsOneWidget);
    expect(tester.widget<TextField>(cardField).controller!.text, isEmpty);
    expect(tester.widget<TextField>(cardField).enabled, isTrue);
    expect(text('Kaart controleren'), findsOneWidget);
  });

  testWidgets('Enter in het vingerafdrukveld voegt toe', (tester) async {
    await ownKey(tester);
    final card = await cardOf(tester, 'A');
    await show(tester);
    await waitFor(tester, text('Er is nog niemand naast jou.'));
    await paste(tester, card.toText());
    await tester.enterText(
      fingerprintField,
      formatFingerprint(card.fingerprint),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // Sleutelcontrole en opslag gebruiken echte I/O; de volle Linux-suite mat
    // hier meer dan tien seconden terwijl de uitkomst daarna wel verscheen.
    await waitFor(
      tester,
      containing('A is toegevoegd.'),
      timeout: const Duration(seconds: 30),
    );
  });

  testWidgets('de velden leren niets van wat je typt', (tester) async {
    await ownKey(tester);
    final card = await cardOf(tester, 'A');
    await show(tester);
    await waitFor(tester, text('Er is nog niemand naast jou.'));
    expect(tester.widget<TextField>(cardField).autocorrect, isFalse);
    expect(tester.widget<TextField>(cardField).enableSuggestions, isFalse);
    await paste(tester, card.toText());
    expect(tester.widget<TextField>(fingerprintField).autocorrect, isFalse);
    expect(
      tester.widget<TextField>(fingerprintField).enableSuggestions,
      isFalse,
    );
    expect(
      tester.widget<TextField>(fingerprintField).controller!.text,
      isEmpty,
      reason: 'nooit voorgevuld',
    );
  });

  group('wat de kaart zegt', () {
    testWidgets('een tekst die geen kaart is', (tester) async {
      await ownKey(tester);
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, 'geen kaart');
      expect(text('Dit is geen redacteurskaart.'), findsOneWidget);
      expect(text('Toevoegen'), findsNothing);
    });

    testWidgets('een kaart van een nieuwere versie', (tester) async {
      await ownKey(tester);
      final card = await cardOf(tester, 'A');
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, card.toText().replaceFirst('"v":1', '"v":2'));
      expect(
        text(
          'Deze kaart is van een nieuwere versie van OciDeck. Werk OciDeck bij.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('een kaart met iets wat niet kan', (tester) async {
      await ownKey(tester);
      final card = await cardOf(tester, 'A');
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, card.toText().replaceFirst(card.kid, 'abc'));
      expect(
        text(
          'De kaart bevat iets wat niet kan. Vraag de redacteur om een nieuwe kaart.',
        ),
        findsOneWidget,
      );
    });
  });

  group('wat de vingerafdruk zegt', () {
    testWidgets(
      'niet die van deze kaart: er verandert niets, en het kan opnieuw',
      (tester) async {
        await ownKey(tester);
        final card = await cardOf(tester, 'A');
        final other = await cardOf(tester, 'B');
        await show(tester);
        await waitFor(tester, text('Er is nog niemand naast jou.'));
        await paste(tester, card.toText());
        await confirm(tester, formatFingerprint(other.fingerprint));
        await waitFor(
          tester,
          containing('Deze vingerafdruk past niet bij de kaart'),
        );
        expect(await teamNames(tester), isEmpty);
        expect(
          fingerprintField,
          findsOneWidget,
          reason: 'de stap blijft staan',
        );
        await confirm(tester, formatFingerprint(card.fingerprint));
        await waitFor(tester, containing('A is toegevoegd.'));
      },
    );

    testWidgets('geen vingerafdruk', (tester) async {
      await ownKey(tester);
      final card = await cardOf(tester, 'A');
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, card.toText());
      await confirm(tester, 'abcd');
      await waitFor(
        tester,
        text(
          'Dat is geen vingerafdruk. Hij bestaat uit 52 tekens, meestal in groepjes van vier.',
        ),
      );
    });

    testWidgets('Annuleren haalt de melding van de vingerafdruk weg', (
      tester,
    ) async {
      await ownKey(tester);
      final card = await cardOf(tester, 'A');
      final other = await cardOf(tester, 'B');
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, card.toText());
      await confirm(tester, formatFingerprint(other.fingerprint));
      await waitFor(
        tester,
        containing('Deze vingerafdruk past niet bij de kaart'),
      );
      await tester.tap(text('Annuleren'));
      await tester.pump();
      expect(
        containing('Deze vingerafdruk past niet bij de kaart'),
        findsNothing,
      );
    });

    testWidgets(
      'Annuleren gaat terug naar de kaart en vergeet wat is ingetikt',
      (tester) async {
        await ownKey(tester);
        final card = await cardOf(tester, 'A');
        await show(tester);
        await waitFor(tester, text('Er is nog niemand naast jou.'));
        await paste(tester, card.toText());
        await tester.enterText(fingerprintField, 'iets');
        await tester.tap(text('Annuleren'));
        await tester.pump();
        expect(fingerprintField, findsNothing);
        expect(text('Kaart controleren'), findsOneWidget);
        expect(tester.widget<TextField>(cardField).enabled, isTrue);
        await tester.tap(text('Kaart controleren'));
        await tester.pump();
        expect(
          tester.widget<TextField>(fingerprintField).controller!.text,
          isEmpty,
        );
      },
    );
  });

  group('wie er niet bij kan', () {
    testWidgets('de eigen kaart', (tester) async {
      await ownKey(tester);
      final own = editorCardOf(ownerInfo, 'Ik');
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, own.toText());
      await confirm(tester, formatFingerprint(own.fingerprint));
      await waitFor(tester, text('Dit is je eigen kaart.'));
      expect(await teamNames(tester), isEmpty);
    });

    testWidgets('iemand die er al in staat', (tester) async {
      await ownKey(tester);
      final card = await cardOf(tester, 'A');
      await tester.runAsync(() => workspace.saveTeam(FormTeam([card])));
      await show(tester);
      await waitFor(tester, text('A'));
      await paste(tester, card.toText());
      await confirm(tester, formatFingerprint(card.fingerprint));
      await waitFor(tester, text('Deze redacteur staat er al.'));
    });

    testWidgets('een vol team', (tester) async {
      await ownKey(tester);
      final full = <FormEditorCard>[];
      for (var i = 0; i < kFormMaxEditors; i++) {
        full.add(await cardOf(tester, 'E$i'));
      }
      await tester.runAsync(() => workspace.saveTeam(FormTeam(full)));
      final extra = await cardOf(tester, 'te veel');
      await show(tester);
      await waitFor(tester, text('E0'));
      await paste(tester, extra.toText());
      await confirm(tester, formatFingerprint(extra.fingerprint));
      await waitFor(
        tester,
        text(
          'Het team is vol: een bundel draagt hooguit 64 organisatoren, jou meegeteld.',
        ),
      );
    });

    testWidgets('zonder eigen sleutel', (tester) async {
      final card = await cardOf(tester, 'A');
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, card.toText());
      await confirm(tester, formatFingerprint(card.fingerprint));
      await waitFor(
        tester,
        text('Maak eerst je eigen redactiesleutel aan onder Redactiesleutel….'),
      );
    });

    testWidgets('een sleutelhanger die niet te lezen is', (tester) async {
      await ownKey(tester);
      final card = await cardOf(tester, 'A');
      vault.failRead = true;
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, card.toText());
      await confirm(tester, formatFingerprint(card.fingerprint));
      await waitFor(
        tester,
        text(
          'Je redactiesleutel is niet te gebruiken. Kijk onder Redactiesleutel….',
        ),
      );
    });

    testWidgets('een plek waar het team niet te bewaren valt', (tester) async {
      await ownKey(tester);
      final card = await cardOf(tester, 'A');
      Directory(workspace.teamPath).createSync(recursive: true);
      await show(tester);
      await waitFor(tester, text('Er is nog niemand naast jou.'));
      await paste(tester, card.toText());
      await confirm(tester, formatFingerprint(card.fingerprint));
      await waitFor(tester, text('Het team kon niet worden opgeslagen.'));
    });
  });

  testWidgets('een team dat niet te lezen is: alleen de melding, niets te doen', (
    tester,
  ) async {
    await ownKey(tester);
    Directory(workspace.root).createSync(recursive: true);
    File(workspace.teamPath).writeAsStringSync('geen team');
    await show(tester);
    await waitFor(
      tester,
      text(
        'Het bestand team.json in de werkmap is niet te lezen. Er is niets aangepast; herstel of verwijder het.',
      ),
    );
    expect(cardField, findsNothing);
    expect(text('Kaart controleren'), findsNothing);
    expect(File(workspace.teamPath).readAsStringSync(), 'geen team');
  });

  group('een redacteur verwijderen', () {
    testWidgets('na een bevestiging die zegt wat blijft', (tester) async {
      await ownKey(tester);
      final a = await cardOf(tester, 'A');
      final b = await cardOf(tester, 'B');
      await tester.runAsync(() => workspace.saveTeam(FormTeam([a, b])));
      await show(tester);
      await waitFor(tester, text('A'));
      await tester.tap(text('Verwijderen').first);
      await tester.pump();
      await tester.pump();
      expect(text('Redacteur verwijderen'), findsOneWidget);
      expect(
        containing(
          'Verwijder A uit het team? Uitnodigingspakketten die je al hebt gemaakt blijven zoals ze zijn',
        ),
        findsOneWidget,
      );
      expect(containing('blijft voor die persoon leesbaar'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: text('Verwijderen'),
        ),
      );
      await tester.pump();
      await waitFor(
        tester,
        text(
          'A is verwijderd. Maak het uitnodigingspakket opnieuw om A eruit te halen.',
        ),
      );
      expect(await teamNames(tester), ['B']);
      await pumpUntil(
        tester,
        () => text('A').evaluate().isEmpty,
        reason: 'A staat nog in de lijst',
      );
      expect(text('B'), findsOneWidget);
    });

    testWidgets('Annuleren in de bevestiging laat alles zoals het was', (
      tester,
    ) async {
      await ownKey(tester);
      final a = await cardOf(tester, 'A');
      await tester.runAsync(() => workspace.saveTeam(FormTeam([a])));
      await show(tester);
      await waitFor(tester, text('A'));
      await tester.tap(text('Verwijderen'));
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: text('Annuleren'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        buttonOf(tester, 'Kaart controleren').onPressed,
        isNotNull,
        reason: 'er is niets gaan lopen',
      );
      expect(await teamNames(tester), ['A']);
      expect(containing('is verwijderd'), findsNothing);
    });

    testWidgets('iemand die ondertussen al weg is', (tester) async {
      await ownKey(tester);
      final a = await cardOf(tester, 'A');
      await tester.runAsync(() => workspace.saveTeam(FormTeam([a])));
      await show(tester);
      await waitFor(tester, text('A'));
      File(workspace.teamPath).deleteSync();
      await tester.tap(text('Verwijderen'));
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: text('Verwijderen'),
        ),
      );
      await tester.pump();
      await waitFor(
        tester,
        text('Deze redacteur staat niet meer in het team.'),
      );
      await waitFor(tester, text('Er is nog niemand naast jou.'));
    });
  });

  testWidgets('tijdens het toevoegen staan de knoppen vast', (tester) async {
    await ownKey(tester);
    final card = await cardOf(tester, 'A');
    final gate = Completer<void>();
    workspace.gate = gate;
    await show(tester);
    await waitFor(tester, text('Er is nog niemand naast jou.'));
    await paste(tester, card.toText());
    await confirm(tester, formatFingerprint(card.fingerprint));
    expect(buttonOf(tester, 'Toevoegen').onPressed, isNull);
    expect(buttonOf(tester, 'Annuleren').onPressed, isNull);
    gate.complete();
    await waitFor(tester, containing('A is toegevoegd.'));
    expect(buttonOf(tester, 'Kaart controleren').onPressed, isNotNull);
  });

  testWidgets('tijdens het verwijderen staan de knoppen vast', (tester) async {
    await ownKey(tester);
    final a = await cardOf(tester, 'A');
    final b = await cardOf(tester, 'B');
    await tester.runAsync(() => workspace.saveTeam(FormTeam([a, b])));
    await show(tester);
    await waitFor(tester, text('A'));
    workspace.gate = Completer<void>();
    await tester.tap(text('Verwijderen').first);
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: text('Verwijderen'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(buttonOf(tester, 'Kaart controleren').onPressed, isNull);
    for (final remove
        in find.widgetWithText(TextButton, 'Verwijderen').evaluate()) {
      expect((remove.widget as TextButton).onPressed, isNull);
    }
    workspace.gate!.complete();
    await waitFor(tester, containing('is verwijderd.'));
    expect(buttonOf(tester, 'Kaart controleren').onPressed, isNotNull);
  });

  testWidgets('tijdens het werk staan de knoppen vast en komt er één redacteur', (
    tester,
  ) async {
    await ownKey(tester);
    final card = await cardOf(tester, 'A');
    await show(tester);
    await waitFor(tester, text('Er is nog niemand naast jou.'));
    await paste(tester, card.toText());
    // Meet hoeveel keer één toevoeging de sleutelhanger leest, en doe het dan dubbel.
    final before = vault.reads;
    await tester.enterText(
      fingerprintField,
      formatFingerprint(card.fingerprint),
    );
    await tester.tap(text('Toevoegen'));
    await tester.tap(text('Toevoegen'));
    await waitFor(tester, containing('A is toegevoegd.'));
    final both = vault.reads - before;
    expect(both, 1, reason: 'de tweede tik deed niets');
    expect(await teamNames(tester), ['A']);
  });

  testWidgets('de knoppen zeggen in het Engels wat ze doen', (tester) async {
    await ownKey(tester);
    final card = await cardOf(tester, 'A');
    await show(tester, language: 'en');
    await waitFor(tester, text('There is nobody besides you yet.'));
    expect(text('Team'), findsOneWidget);
    final en = find.widgetWithText(TextField, "Paste the editor's card");
    await tester.enterText(en, card.toText());
    await tester.tap(text('Check card'));
    await tester.pump();
    expect(
      containing('Card of A. Type the fingerprint of this card'),
      findsOneWidget,
    );
    expect(text('Add'), findsOneWidget);
    expect(text('Cancel'), findsOneWidget);
  });

  testWidgets('Sluiten sluit het venster', (tester) async {
    await ownKey(tester);
    await show(tester);
    await waitFor(tester, text('Er is nog niemand naast jou.'));
    await tester.tap(text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
