// De redactiesleutel vanuit de Inbox (FORM_INTAKE.md §5.9): zichtbaar aanmaken, de
// herstelsleutel terugtypen, herstellen, exporteren en wissen.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/widgets/forms/form_keys_dialog.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/form_key_vault.dart';
import 'support/pump_until.dart';

void main() {
  late FormKeyVault vault;
  late FormKeyService service;
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    vault = FormKeyVault();
    service = FormKeyService(
      SecretStore(storage: vault, canStore: true),
      now: () => DateTime.utc(2026, 11, 3),
    );
  });

  Future<void> show(
    WidgetTester tester, {
    FormKeyService? use,
    FormKeyFileSaver? saveFile,
    String language = 'nl',
  }) async {
    AppLocalizations.setActiveLanguageCode(language);
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFormKeysDialog(
                  context,
                  service: use ?? service,
                  saveFile: saveFile,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
  }

  Finder text(String s) => find.text(s);

  /// Wacht tot [s] er staat: de dienst werkt met echte (asynchrone) bewerkingen.
  Future<void> waitFor(WidgetTester tester, String s) =>
      pumpUntil(tester, () => text(s).evaluate().isNotEmpty, reason: s);

  Future<void> create(WidgetTester tester) async {
    await show(tester);
    await waitFor(tester, 'Redactiesleutel aanmaken');
    await tester.tap(text('Redactiesleutel aanmaken'));
    await waitFor(
      tester,
      'Redactiesleutel aangemaakt. Schrijf nu de herstelsleutel op.',
    );
  }

  testWidgets('zonder sleutelhanger staat er dat, en is er niets te doen', (
    tester,
  ) async {
    await show(
      tester,
      use: FormKeyService(SecretStore(storage: vault, canStore: false)),
    );
    await waitFor(
      tester,
      'Dit platform heeft geen sleutelhanger. De redactiesleutel kan hier niet worden bewaard; gebruik de desktopapp.',
    );
    expect(text('Redactiesleutel aanmaken'), findsNothing);
  });

  testWidgets('zonder sleutel legt het uit wat hij is en wat verlies kost', (
    tester,
  ) async {
    await show(tester);
    await waitFor(tester, 'Redactiesleutel aanmaken');
    expect(
      find.textContaining('de prijs van een server die niets kan lezen'),
      findsOneWidget,
    );
    expect(text('Herstellen uit herstelsleutel…'), findsOneWidget);
    expect(vault.writes, isEmpty, reason: 'niets wordt stilletjes aangemaakt');
  });

  testWidgets('aanmaken toont de herstelsleutel en vraagt hem terug te typen', (
    tester,
  ) async {
    await create(tester);
    final recovery = (await tester.runAsync(service.recoveryKey))!;
    expect(find.text(recovery), findsOneWidget);
    expect(text('Typ de herstelsleutel hier opnieuw in'), findsOneWidget);
    expect(text('Herstelsleutel controleren'), findsOneWidget);
    expect(text('Later'), findsOneWidget);
    expect(vault.writes, hasLength(1));
  });

  testWidgets('de knoppen zeggen in het Engels wat ze doen', (tester) async {
    // Een Nederlandse bronstring kan al een Engelse vertaling hebben uit een ander venster
    // ("Controleren" was "Check syntax"); alleen een venster in de andere taal ziet dat.
    await show(tester, language: 'en');
    await waitFor(tester, 'Create editorial key');
    expect(text('Restore from recovery key…'), findsOneWidget);
    await tester.tap(text('Create editorial key'));
    await waitFor(tester, 'Check recovery key');
    expect(text('Later'), findsOneWidget);
    expect(text('Check syntax'), findsNothing);
  });

  testWidgets('de herstelsleutel terugtypen controleert hem en zegt dat', (
    tester,
  ) async {
    await create(tester);
    final recovery = (await tester.runAsync(service.recoveryKey))!;
    await tester.enterText(find.byType(TextField), recovery.toLowerCase());
    await tester.tap(text('Herstelsleutel controleren'));
    await waitFor(tester, 'Klopt: de herstelsleutel is gecontroleerd.');
    expect(text('De herstelsleutel is gecontroleerd.'), findsOneWidget);
    final state = await tester.runAsync(service.read) as FormKeyPresent;
    expect(state.info.recoveryVerified, isTrue);
  });

  testWidgets('een verkeerd teruggetypte herstelsleutel zegt wat er mis is', (
    tester,
  ) async {
    await create(tester);
    final recovery = (await tester.runAsync(service.recoveryKey))!;
    final plain = recovery.replaceAll('-', '');
    final typo = plain.replaceRange(30, 31, plain[30] == '2' ? '3' : '2');
    final other = encodeFormRecoveryKey(
      signingSeed: Uint8List(32),
      ageIdentity: generateAgeIdentity(),
    );
    for (final (typed, message) in [
      (typo, 'Er zit een typefout in: de controlesom klopt niet.'),
      ('onzin', 'Dit is geen herstelsleutel van een redactiesleutel.'),
      (
        other,
        'Dit is een geldige herstelsleutel, maar niet die van deze redactiesleutel.',
      ),
    ]) {
      await tester.enterText(find.byType(TextField), typed);
      await tester.tap(text('Herstelsleutel controleren'));
      await waitFor(tester, message);
    }
    final state = await tester.runAsync(service.read) as FormKeyPresent;
    expect(state.info.recoveryVerified, isFalse);
  });

  testWidgets(
    'Later laat de sleutel staan en zegt dat de herstelsleutel nog niet gecontroleerd is',
    (tester) async {
      await create(tester);
      await tester.tap(text('Later'));
      await tester.pump();
      expect(
        find.textContaining('De herstelsleutel is nog niet gecontroleerd'),
        findsOneWidget,
      );
      expect(text('Herstelsleutel tonen…'), findsOneWidget);
    },
  );

  testWidgets(
    'de sleutel toont zijn vingerafdruk in groepjes en zijn ontvanger',
    (tester) async {
      final present = await tester.runAsync(() async {
        await service.create();
        return await service.read() as FormKeyPresent;
      });
      await show(tester);
      await waitFor(tester, 'Herstelsleutel tonen…');
      expect(
        find.text(formatFingerprint(present!.info.fingerprint)),
        findsOneWidget,
      );
      expect(find.text(present.info.recipient), findsOneWidget);
      expect(find.text('Aangemaakt op 2026-11-03.'), findsOneWidget);
      expect(find.text('Vingerafdruk'), findsOneWidget);
      expect(find.text('Ontvanger (age)'), findsOneWidget);
    },
  );

  testWidgets('de herstelsleutel tonen kan later nog, en Later gaat terug', (
    tester,
  ) async {
    await tester.runAsync(service.create);
    await show(tester);
    await waitFor(tester, 'Herstelsleutel tonen…');
    await tester.tap(text('Herstelsleutel tonen…'));
    await tester.pump();
    await tester.pump();
    final recovery = (await tester.runAsync(service.recoveryKey))!;
    expect(find.text(recovery), findsOneWidget);
    await tester.tap(text('Later'));
    await tester.pump();
    expect(find.text(recovery), findsNothing);
  });

  group('de redacteurskaart', () {
    Future<FormKeyPresent> present(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          await service.create();
          return await service.read() as FormKeyPresent;
        }))!;

    Future<void> openCard(WidgetTester tester) async {
      await show(tester);
      await waitFor(tester, 'Redacteurskaart maken…');
      await tester.tap(text('Redacteurskaart maken…'));
      await tester.pump();
    }

    testWidgets('zonder sleutel is er geen kaart te maken', (tester) async {
      await show(tester);
      await waitFor(tester, 'Redactiesleutel aanmaken');
      expect(text('Redacteurskaart maken…'), findsNothing);
    });

    testWidgets('een kaart met de naam, de tekst en de vingerafdruk', (
      tester,
    ) async {
      final key = await present(tester);
      await openCard(tester);
      expect(text('Kaart maken'), findsOneWidget);
      expect(text('Vingerafdruk van de kaart'), findsNothing);
      await tester.enterText(find.byType(TextField), '  Sari  ');
      await tester.tap(text('Kaart maken'));
      await tester.pump();
      final shown = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data!)
          .toList();
      final card =
          (parseFormEditorCard(shown.firstWhere((t) => t.startsWith('{')))
                  as FormEditorCardParsed)
              .card;
      expect(card.name, 'Sari');
      expect(card.age, key.info.recipient);
      expect(card.sign, key.info.signPublicKey);
      expect(shown, contains(formatFingerprint(card.fingerprint)));
      expect(text('Vingerafdruk van de kaart'), findsOneWidget);
      expect(
        find.textContaining('langs een andere weg dan de kaart'),
        findsOneWidget,
      );
      expect(text('Kaart maken'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse, reason: 'de naam staat op de kaart');
    });

    testWidgets('zonder naam komt er geen kaart', (tester) async {
      await present(tester);
      await openCard(tester);
      for (final bad in ['', '   ', 'x' * 81]) {
        await tester.enterText(find.byType(TextField), bad);
        await tester.tap(text('Kaart maken'));
        await tester.pump();
        expect(text('Vul een naam in van hooguit 80 tekens.'), findsOneWidget);
        expect(text('Vingerafdruk van de kaart'), findsNothing, reason: bad);
      }
    });

    testWidgets('witruimte rond de naam telt niet mee voor de 80 tekens', (
      tester,
    ) async {
      await present(tester);
      await openCard(tester);
      await tester.enterText(find.byType(TextField), ' ${'x' * 80} ');
      await tester.tap(text('Kaart maken'));
      await tester.pump();
      expect(text('Vingerafdruk van de kaart'), findsOneWidget);
    });

    testWidgets('Enter in het naamveld maakt de kaart', (tester) async {
      await present(tester);
      await openCard(tester);
      await tester.enterText(find.byType(TextField), 'Sari');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(text('Vingerafdruk van de kaart'), findsOneWidget);
    });

    testWidgets('Terug haalt de melding van de kaartstap weg', (tester) async {
      await present(tester);
      await openCard(tester);
      await tester.tap(text('Kaart maken'));
      await tester.pump();
      expect(text('Vul een naam in van hooguit 80 tekens.'), findsOneWidget);
      await tester.tap(text('Terug'));
      await tester.pump();
      expect(text('Vul een naam in van hooguit 80 tekens.'), findsNothing);
    });

    testWidgets('de kaart is te kopiëren', (tester) async {
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
      await present(tester);
      await openCard(tester);
      await tester.enterText(find.byType(TextField), 'Sari');
      await tester.tap(text('Kaart maken'));
      await tester.pump();
      await tester.tap(text('Kaart kopiëren'));
      await tester.pump();
      expect(copied, hasLength(1));
      expect(parseFormEditorCard(copied.single), isA<FormEditorCardParsed>());
    });

    testWidgets('Terug vergeet de kaart en laat het overzicht zien', (
      tester,
    ) async {
      await present(tester);
      await openCard(tester);
      await tester.enterText(find.byType(TextField), 'Sari');
      await tester.tap(text('Kaart maken'));
      await tester.pump();
      await tester.tap(text('Terug'));
      await tester.pump();
      expect(text('Herstelsleutel tonen…'), findsOneWidget);
      expect(text('Vingerafdruk van de kaart'), findsNothing);
      await tester.tap(text('Redacteurskaart maken…'));
      await tester.pump();
      expect(text('Kaart maken'), findsOneWidget, reason: 'een lege kaartstap');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('de knoppen zeggen in het Engels wat ze doen', (tester) async {
      await present(tester);
      await show(tester, language: 'en');
      await waitFor(tester, 'Create editor card…');
      await tester.tap(text('Create editor card…'));
      await tester.pump();
      expect(text('Your name on the card'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Sari');
      await tester.tap(text('Create card'));
      await tester.pump();
      expect(text('Fingerprint of the card'), findsOneWidget);
      expect(text('Copy card'), findsOneWidget);
      expect(text('Back'), findsOneWidget);
    });
  });

  testWidgets('de vingerafdruk is te kopiëren', (tester) async {
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
    final present = await tester.runAsync(() async {
      await service.create();
      return await service.read() as FormKeyPresent;
    });
    await show(tester);
    await waitFor(tester, 'Vingerafdruk kopiëren');
    await tester.tap(text('Vingerafdruk kopiëren'));
    await tester.pump();
    expect(copied, [formatFingerprint(present!.info.fingerprint)]);
  });

  testWidgets(
    'een sleutelhanger die de sleutel niet aanneemt: niets aangemaakt, en het zegt het',
    (tester) async {
      vault.failWrite = true;
      await show(tester);
      await waitFor(tester, 'Redactiesleutel aanmaken');
      await tester.tap(text('Redactiesleutel aanmaken'));
      await waitFor(
        tester,
        'De sleutelhanger nam de sleutel niet aan. Er is niets aangemaakt.',
      );
      expect(text('Redactiesleutel aanmaken'), findsOneWidget);
    },
  );

  testWidgets(
    'een sleutelhanger die niet te lezen is wordt niet voor leeg aangezien',
    (tester) async {
      vault.failRead = true;
      await show(tester);
      await waitFor(
        tester,
        'De sleutelhanger kon niet worden gelezen (vergrendeld, of toegang geweigerd). Er is niets aangenomen en niets aangemaakt.',
      );
      expect(text('Redactiesleutel aanmaken'), findsNothing);
      vault.failRead = false;
      await tester.tap(text('Opnieuw proberen'));
      await waitFor(tester, 'Redactiesleutel aanmaken');
    },
  );

  testWidgets(
    'een beschadigde sleutel blijft staan tot je hem zelf verwijdert',
    (tester) async {
      vault.data[SecretStore.formEditorialKeyKey] = 'rommel';
      await show(tester);
      await waitFor(tester, 'Redactiesleutel verwijderen…');
      expect(text('Redactiesleutel aanmaken'), findsNothing);
      await tester.tap(text('Redactiesleutel verwijderen…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
      await waitFor(tester, 'Redactiesleutel aanmaken');
      expect(vault.data, isEmpty);
    },
  );

  testWidgets('herstellen uit een herstelsleutel zet dezelfde sleutel terug', (
    tester,
  ) async {
    final original = await tester.runAsync(() async {
      await service.create();
      final present = await service.read() as FormKeyPresent;
      final recovery = (await service.recoveryKey())!;
      await service.delete();
      return (present, recovery);
    });
    await show(tester);
    await waitFor(tester, 'Herstellen uit herstelsleutel…');
    await tester.tap(text('Herstellen uit herstelsleutel…'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), original!.$2);
    await tester.tap(text('Herstellen'));
    await waitFor(tester, 'Hersteld uit de herstelsleutel.');
    expect(
      find.text(formatFingerprint(original.$1.info.fingerprint)),
      findsOneWidget,
    );
    expect(text('De herstelsleutel is gecontroleerd.'), findsOneWidget);
  });

  testWidgets(
    'een herstelsleutel die niet te lezen is herstelt niets, Terug gaat terug',
    (tester) async {
      await show(tester);
      await waitFor(tester, 'Herstellen uit herstelsleutel…');
      await tester.tap(text('Herstellen uit herstelsleutel…'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'onzin');
      await tester.tap(text('Herstellen'));
      await waitFor(
        tester,
        'Dit is geen herstelsleutel van een redactiesleutel.',
      );
      expect(vault.writes, isEmpty);
      await tester.tap(text('Terug'));
      await tester.pump();
      expect(text('Redactiesleutel aanmaken'), findsOneWidget);
    },
  );

  testWidgets('herstellen waar de sleutelhanger het niet aanneemt zegt dat', (
    tester,
  ) async {
    final recovery = (await tester.runAsync(() async {
      await service.create();
      final r = (await service.recoveryKey())!;
      await service.delete();
      return r;
    }))!;
    vault.failWrite = true;
    await show(tester);
    await waitFor(tester, 'Herstellen uit herstelsleutel…');
    await tester.tap(text('Herstellen uit herstelsleutel…'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), recovery);
    await tester.tap(text('Herstellen'));
    await waitFor(
      tester,
      'De sleutelhanger nam de sleutel niet aan. Er is niets hersteld.',
    );
  });

  group('exporteren als age-sleutelbestand', () {
    Future<FormKeyPresent> existing(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          await service.create();
          return await service.read() as FormKeyPresent;
        }))!;

    testWidgets(
      'geeft de tekst van het bestand aan de opslag en zegt waar het staat',
      (tester) async {
        final present = await existing(tester);
        final calls = <(String, String, String)>[];
        await show(
          tester,
          saveFile: (title, name, body) async {
            calls.add((title, name, body));
            return '/tmp/ocideck-redactiesleutel.txt';
          },
        );
        await waitFor(tester, 'Exporteren als age-sleutelbestand…');
        await tester.tap(text('Exporteren als age-sleutelbestand…'));
        await waitFor(
          tester,
          'Opgeslagen als /tmp/ocideck-redactiesleutel.txt. Wie dit bestand heeft, kan alles openen.',
        );
        expect(calls, hasLength(1));
        expect(
          calls.single.$1,
          'Redactiesleutel opslaan als age-sleutelbestand',
        );
        expect(calls.single.$2, 'ocideck-redactiesleutel.txt');
        expect(
          calls.single.$3,
          service.identityFileText(present.key, present.info),
        );
      },
    );

    testWidgets('annuleren zegt niets', (tester) async {
      await existing(tester);
      await show(tester, saveFile: (_, _, _) async => null);
      await waitFor(tester, 'Exporteren als age-sleutelbestand…');
      await tester.tap(text('Exporteren als age-sleutelbestand…'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Opgeslagen als'), findsNothing);
      expect(find.textContaining('kon niet worden opgeslagen'), findsNothing);
    });

    testWidgets('een bestand dat niet te schrijven valt wordt gemeld', (
      tester,
    ) async {
      await existing(tester);
      await show(
        tester,
        saveFile: (_, _, _) async => throw const FileSystemException('weigert'),
      );
      await waitFor(tester, 'Exporteren als age-sleutelbestand…');
      await tester.tap(text('Exporteren als age-sleutelbestand…'));
      await waitFor(tester, 'Het bestand kon niet worden opgeslagen.');
    });
  });

  group('verwijderen', () {
    testWidgets('vraagt eerst, en annuleren laat de sleutel staan', (
      tester,
    ) async {
      await tester.runAsync(service.create);
      await show(tester);
      await waitFor(tester, 'Redactiesleutel verwijderen…');
      await tester.tap(text('Redactiesleutel verwijderen…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('voorgoed onleesbaar'), findsOneWidget);
      await tester.tap(text('Annuleren'));
      await tester.pumpAndSettle();
      final state = await tester.runAsync(service.read);
      expect(state, isA<FormKeyPresent>());
      expect(text('Redactiesleutel verwijderd.'), findsNothing);
    });

    testWidgets('bevestigen wist hem en zegt dat', (tester) async {
      await tester.runAsync(service.create);
      await show(tester);
      await waitFor(tester, 'Redactiesleutel verwijderen…');
      await tester.tap(text('Redactiesleutel verwijderen…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
      await waitFor(tester, 'Redactiesleutel verwijderd.');
      expect(vault.data, isEmpty);
      expect(text('Redactiesleutel aanmaken'), findsOneWidget);
    });
  });

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

  testWidgets(
    'tijdens het aanmaken staan de knoppen vast, en na een mislukking weer los',
    (tester) async {
      vault.failWrite = true;
      await show(tester);
      await waitFor(tester, 'Redactiesleutel aanmaken');
      expect(enabled(tester, 'Redactiesleutel aanmaken'), isTrue);
      vault.writeGate = Completer<void>();
      await tester.tap(text('Redactiesleutel aanmaken'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.value());
      await tester.pump();
      expect(enabled(tester, 'Redactiesleutel aanmaken'), isFalse);
      expect(enabled(tester, 'Herstellen uit herstelsleutel…'), isFalse);
      vault.writeGate!.complete();
      await waitFor(
        tester,
        'De sleutelhanger nam de sleutel niet aan. Er is niets aangemaakt.',
      );
      expect(enabled(tester, 'Redactiesleutel aanmaken'), isTrue);
      expect(enabled(tester, 'Herstellen uit herstelsleutel…'), isTrue);
    },
  );

  testWidgets(
    'tijdens het herstellen staat de knop vast, en na een mislukking weer los',
    (tester) async {
      await show(tester);
      await waitFor(tester, 'Herstellen uit herstelsleutel…');
      await tester.tap(text('Herstellen uit herstelsleutel…'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'onzin');
      vault.readGate = Completer<void>();
      await tester.tap(text('Herstellen'));
      await tester.pump();
      expect(enabled(tester, 'Herstellen'), isFalse);
      vault.readGate!.complete();
      await waitFor(
        tester,
        'Dit is geen herstelsleutel van een redactiesleutel.',
      );
      expect(enabled(tester, 'Herstellen'), isTrue);
    },
  );

  testWidgets(
    'na een gelukte aanmaak of herstelling zijn de knoppen niet blijven vastzitten',
    (tester) async {
      await create(tester);
      final recovery = (await tester.runAsync(service.recoveryKey))!;
      await tester.tap(text('Later'));
      await tester.pump();
      // Weg met de sleutel: het scherm is weer leeg, en de knoppen horen te werken.
      await tester.tap(text('Redactiesleutel verwijderen…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
      await waitFor(tester, 'Redactiesleutel verwijderd.');
      expect(enabled(tester, 'Redactiesleutel aanmaken'), isTrue);
      expect(enabled(tester, 'Herstellen uit herstelsleutel…'), isTrue);
      // Herstellen, en dan weer weg.
      await tester.tap(text('Herstellen uit herstelsleutel…'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), recovery);
      await tester.tap(text('Herstellen'));
      await waitFor(tester, 'Hersteld uit de herstelsleutel.');
      await tester.tap(text('Redactiesleutel verwijderen…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
      await waitFor(tester, 'Redactiesleutel verwijderd.');
      expect(enabled(tester, 'Redactiesleutel aanmaken'), isTrue);
      expect(enabled(tester, 'Herstellen uit herstelsleutel…'), isTrue);
    },
  );

  testWidgets('de velden voor een herstelsleutel leren niets van wat je typt', (
    tester,
  ) async {
    await create(tester);
    final recoveryField = tester.widget<TextField>(find.byType(TextField));
    expect(recoveryField.autocorrect, isFalse);
    expect(recoveryField.enableSuggestions, isFalse);
    await tester.tap(text('Later'));
    await tester.pump();
    await tester.tap(text('Herstelsleutel tonen…'));
    await tester.pump();
    await tester.pump();
    await tester.tap(text('Later'));
    await tester.pump();
    await tester.runAsync(service.delete);
    await tester.tap(text('Sluiten'));
    await tester.pumpAndSettle();
    await show(tester);
    await waitFor(tester, 'Herstellen uit herstelsleutel…');
    await tester.tap(text('Herstellen uit herstelsleutel…'));
    await tester.pump();
    final restoreField = tester.widget<TextField>(find.byType(TextField));
    expect(restoreField.autocorrect, isFalse);
    expect(restoreField.enableSuggestions, isFalse);
  });

  testWidgets('de titel is een kop en een melding wordt voorgelezen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    await waitFor(tester, 'Redactiesleutel aanmaken');
    final header = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.header == true,
    );
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: text('Redactiesleutel')),
      findsOneWidget,
    );
    vault.failWrite = true;
    await tester.tap(text('Redactiesleutel aanmaken'));
    const message =
        'De sleutelhanger nam de sleutel niet aan. Er is niets aangemaakt.';
    await waitFor(tester, message);
    expect(
      tester.getSemantics(text(message)).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(
      tester
          .getSemantics(text('Redactiesleutel aanmaken'))
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('Sluiten sluit het venster', (tester) async {
    await show(tester);
    await waitFor(tester, 'Redactiesleutel aanmaken');
    await tester.tap(text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
