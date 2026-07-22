import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/consent_provider.dart';
import 'package:ocideck/widgets/dialogs/consent_dialog.dart';
import 'package:ocideck/widgets/language_flag.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:ocideck/widgets/privacy_statement_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een toestemmingsopslag die faalt waar de echte dat alleen op een kapot
/// apparaat doet. Zonder deze seam is elk foutpad in [ConsentNotifier] dode
/// tekst: de SharedPreferences-mock slaagt altijd.
class _FakeConsentStore implements ConsentStore {
  _FakeConsentStore({
    this.stored = false,
    this.readThrows = false,
    this.writeThrows = false,
  });

  bool stored;
  final bool readThrows;
  final bool writeThrows;
  int writes = 0;

  @override
  Future<bool> read() async {
    if (readThrows) throw StateError('voorkeuren onleesbaar');
    return stored;
  }

  @override
  Future<void> write(bool value) async {
    writes++;
    if (writeThrows) throw StateError('voorkeuren niet schrijfbaar');
    stored = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled EUPL licence', () {
    test('loads and strips its SPDX/comment header', () async {
      // Reset: een eerder (gerandomiseerd) gedraaide widgettest kan de memo
      // in een fake-async-zone gestart hebben; die future completeert hier
      // nooit meer. Vers laden maakt deze test volgorde-onafhankelijk.
      PrivacyStatementContent.resetLicenseCacheForTest();
      final text = await PrivacyStatementContent.loadFullLicense();
      // The HTML-comment header (with the SPDX line) is removed…
      expect(text.contains('SPDX-License-Identifier'), isFalse);
      // …and the actual licence body is present.
      expect(text.trimLeft(), startsWith('# European Union Public Licence'));
      expect(text, contains('EUPL'));
    });
  });

  group('ConsentDialog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ProviderContainer> pumpDialog(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: ConsentDialog())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    ElevatedButton acceptButton(WidgetTester tester) =>
        tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Akkoord gaan'),
        );

    testWidgets('accept stays disabled until the box is ticked', (
      tester,
    ) async {
      await pumpDialog(tester);

      expect(acceptButton(tester).onPressed, isNull);

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(acceptButton(tester).onPressed, isNotNull);
    });

    testWidgets('het vinkje staat meteen in beeld, zonder scrollen', (
      tester,
    ) async {
      // #646: het vinkje stond onder de hele privacyverklaring — vijf schermen
      // naar beneden. Wie de app voor het eerst opende zag een grijze knop
      // "Akkoord gaan" en kon niet zien waarom, laat staan wat eraan te doen.
      //
      // Let op de test hierboven: die moet `ensureVisible` doen om bij het
      // vinkje te komen. Dat is precies de handeling die de gebruiker ook moest
      // verrichten, en de reden dat de bestaande tests dit gebrek niet lieten
      // zien. Hier gebeurt dat bewust níét.
      await pumpDialog(tester);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(
        acceptButton(tester).onPressed,
        isNotNull,
        reason: 'het vinkje was niet aan te tikken zonder eerst te scrollen',
      );
    });

    testWidgets('en het staat naast de knop, niet in de scrollende tekst', (
      tester,
    ) async {
      // De structurele kant: de verklaring hoort scrollbaar te blijven — die
      // moet gelezen kunnen worden — maar de hándeling hoort daarbuiten, bij de
      // knop die hij vrijgeeft.
      await pumpDialog(tester);

      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('accepting records consent', (tester) async {
      final container = await pumpDialog(tester);
      expect(container.read(consentProvider).hasAccepted, isFalse);

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Akkoord gaan'));
      await tester.pumpAndSettle();

      expect(container.read(consentProvider).hasAccepted, isTrue);
    });
  });

  // De vlag staat op schijf; wat er gebeurt als die schijf niet meewerkt was
  // tot nu toe nergens getoetst. Het gevaarlijke geval is het intrekken: de
  // toestand zegt dan "ingetrokken", maar op schijf staat nog "toegestaan", en
  // de volgende start toont de toestemmingspoort dus NIET meer.
  group('ConsentNotifier bij een falende opslag', () {
    ProviderContainer containerWith(_FakeConsentStore store) {
      final container = ProviderContainer(
        overrides: [consentStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      // De notifier wordt pas bij de eerste read gebouwd, en pas dán start
      // `_initialize()`. Zonder deze regel pompt een test een lege wachtrij en
      // ziet hij altijd de begintoestand.
      container.read(consentProvider);
      return container;
    }

    test(
      'een onleesbare vlag houdt de poort dicht en stopt het laden',
      () async {
        final container = containerWith(_FakeConsentStore(readThrows: true));
        expect(container.read(consentProvider).isLoading, isTrue);

        await pumpEventQueue();

        expect(container.read(consentProvider).hasAccepted, isFalse);
        expect(container.read(consentProvider).isLoading, isFalse);
      },
    );

    test('een leesbare vlag komt in de toestand terecht', () async {
      final container = containerWith(_FakeConsentStore(stored: true));
      await pumpEventQueue();

      expect(container.read(consentProvider).hasAccepted, isTrue);
      expect(container.read(consentProvider).isLoading, isFalse);
    });

    test('intrekken dat niet wegschrijft meldt dat terug', () async {
      final store = _FakeConsentStore(stored: true, writeThrows: true);
      final container = containerWith(store);
      await pumpEventQueue();

      final ok = await container.read(consentProvider.notifier).revokeConsent();

      expect(ok, isFalse, reason: 'een mislukte schrijfactie mag niet slagen');
      expect(store.writes, 1);
      // Op schijf staat de toestemming er nog: precies het gat dat de melding
      // aan de gebruiker moet dichten.
      expect(store.stored, isTrue);
      // Deze sessie gedraagt zich wél als ingetrokken.
      expect(container.read(consentProvider).hasAccepted, isFalse);
    });

    test('intrekken dat wél wegschrijft meldt succes', () async {
      final store = _FakeConsentStore(stored: true);
      final container = containerWith(store);
      await pumpEventQueue();

      final ok = await container.read(consentProvider.notifier).revokeConsent();

      expect(ok, isTrue);
      expect(store.stored, isFalse);
      expect(container.read(consentProvider).hasAccepted, isFalse);
    });

    test('toestemmen dat niet wegschrijft meldt dat terug', () async {
      final store = _FakeConsentStore(writeThrows: true);
      final container = containerWith(store);
      await pumpEventQueue();

      final ok = await container.read(consentProvider.notifier).acceptConsent();

      expect(ok, isFalse);
      // Deze sessie mag door; de poort komt bij de volgende start terug.
      expect(container.read(consentProvider).hasAccepted, isTrue);
      expect(store.stored, isFalse);
    });
  });

  testWidgets('een intrekking die niet wegschrijft wordt aan de gebruiker '
      'gemeld', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = _FakeConsentStore(stored: true, writeThrows: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [consentStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.privacy_tip_outlined));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Toestemming intrekken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toestemming intrekken'));
    await tester.pumpAndSettle();

    // Bevestigen in het waarschuwingsvenster.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Intrekken'));
    await tester.pumpAndSettle();

    expect(store.writes, 1, reason: 'de intrekking is wel geprobeerd');
    expect(find.byType(SettingsDialog), findsNothing);
    expect(
      find.text(
        'Intrekken is niet vastgelegd. Bij de volgende start geldt uw '
        'toestemming weer.',
      ),
      findsOneWidget,
    );
  });

  group('language flags', () {
    testWidgets('Frisian uses the bundled flag image', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: languageFlag('fy'))),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/flag_fy.png',
      );
    });

    testWidgets('other languages use a flag emoji, not an image', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: languageFlag('en'))),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('🇬🇧'), findsOneWidget);
    });

    testWidgets('Klingon shows a neutral letter badge, not an emblem', (
      tester,
    ) async {
      // `assets/images/flag_tlh.png` was the Klingon trefoil — a third-party
      // emblem from the Star Trek franchise, carried in every binary. Naming a
      // product is nominative use; reproducing its mark as artwork is not. The
      // language stays, the mark does not.
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: languageFlag('tlh'))),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('tlh'), findsOneWidget);
      expect(find.text('🖖'), findsNothing);
    });

    test('the Klingon emblem is gone from the repository and the bundle', () {
      expect(File('assets/images/flag_tlh.png').existsSync(), isFalse);
      expect(
        File('pubspec.yaml').readAsStringSync().contains('flag_tlh'),
        isFalse,
      );
    });

    testWidgets('an option row shows the flag beside the name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: languageOptionRow('fy', 'Frysk'))),
      );
      expect(find.text('Frysk'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
