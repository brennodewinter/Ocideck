@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/browser_deck_store.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/data_impact_log.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/dialogs/browser_storage_dialog.dart';
import 'package:ocideck/widgets/dialogs/settings/browser_storage_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;

import 'support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // De webtestbinding bedient flutter/assets niet zoals de echte engine.
    // Alleen de pakketstijl is een fixture; localStorage blijft de echte backend.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (key == 'assets/themes/ocideck.css') {
            return ByteData.sublistView(
              Uint8List.fromList(
                utf8.encode('/* @theme ocideck */ section { color: black; }'),
              ),
            );
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null),
  );
  test(
    'Chrome storage: real localStorage package and media roundtrip',
    () async {
      SharedPreferencesPlugin.registerWith(null);
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final image = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        13,
        10,
        26,
        10,
        1,
        2,
        3,
      ]);
      final path = WebAssetStore.put(image, name: 'private.png');
      final notifier =
          DeckNotifier(
            c.read(markdownServiceProvider),
            c.read(fileServiceProvider),
          )..newDeck(
            'Persistent copy',
            slides: [
              Slide.create(
                SlideType.image,
              ).copyWith(title: 'Picture', imagePath: path),
            ],
          );
      addTearDown(notifier.dispose);
      final bytes = await c
          .read(fileServiceProvider)
          .buildPackageBytes(notifier.currentState.deck!);
      final id = await BrowserDeckStore().save('Persistent copy', bytes);
      addTearDown(() async {
        await BrowserDeckStore().remove(id);
        WebAssetStore.clear();
      });
      expect(
        web.window.localStorage.getItem('flutter.${BrowserDeckStore.key}$id'),
        isNotNull,
      );
      WebAssetStore.clear();
      await prefs.reload();
      final entry = (await BrowserDeckStore().list()).singleWhere(
        (e) => e.id == id,
      );
      final result = await c
          .read(tabsProvider.notifier)
          .openDeckFromBytes(entry.bytes, '$id.ocideck');
      expect(result, OpenResult.opened);
      final reopened = c
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      expect(reopened.title, 'Persistent copy');
      expect(WebAssetStore.bytesFor(reopened.slides.single.imagePath), image);
      await BrowserDeckStore().remove(id);
      expect(
        (await BrowserDeckStore().list()).where((e) => e.id == id),
        isEmpty,
      );
    },
  );
  testWidgets(
    'Chrome: explicit browser save persists media, reopens and deletes',
    (tester) async {
      SharedPreferencesPlugin.registerWith(null);
      AppLocalizations.setActiveLanguageCode('nl');
      final prefs = await SharedPreferences.getInstance();
      for (final key
          in prefs
              .getKeys()
              .where(
                (k) =>
                    k.startsWith(BrowserDeckStore.key) ||
                    k == DataImpactLog.key,
              )
              .toList()) {
        await prefs.remove(key);
      }
      addTearDown(() async {
        for (final entry in await BrowserDeckStore().list()) {
          await BrowserDeckStore().remove(entry.id);
        }
        await prefs.remove(DataImpactLog.key);
        WebAssetStore.clear();
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final image = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        13,
        10,
        26,
        10,
        1,
        2,
        3,
      ]);
      final imagePath = WebAssetStore.put(image, name: 'private.png');
      final notifier = DeckNotifier(
        c.read(markdownServiceProvider),
        c.read(fileServiceProvider),
      );
      addTearDown(notifier.dispose);
      notifier.newDeck(
        'Browser roundtrip',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(title: 'Picture', imagePath: imagePath),
        ],
      );
      bool? result;
      var saveCompleted = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () async {
                        result = await chooseBrowserSave(
                          context,
                          notifier,
                          c.read(fileServiceProvider),
                        );
                        saveCompleted = true;
                      },
                      child: const Text('save'),
                    ),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AlertDialog(
                          content: SizedBox(
                            width: 600,
                            child: SingleChildScrollView(
                              child: BrowserStorageSection(),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('storage'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In browser bewaren'));
      await tester.pumpAndSettle();
      expect(find.textContaining('lokale schijf is veiliger'), findsOneWidget);
      expect(await BrowserDeckStore().list(), isEmpty);
      await tester.tap(find.text('Doorgaan'));
      await pumpUntil(
        tester,
        () => saveCompleted,
        reason: 'browser save did not finish',
      );
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(notifier.currentState.isDirty, isFalse);
      final saved = (await BrowserDeckStore().list()).single;
      expect(
        web.window.localStorage.getItem(
          'flutter.${BrowserDeckStore.key}${saved.id}',
        ),
        isNotNull,
      );
      final events = prefs
          .getStringList(DataImpactLog.key)!
          .map((s) => jsonDecode(s) as Map)
          .toList();
      expect(events.map((e) => e['decision']), ['shown', 'accepted']);
      WebAssetStore.clear();
      await tester.tap(find.text('storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Openen'));
      await pumpUntil(
        tester,
        () =>
            c
                .read(tabsProvider)
                .current
                ?.deckNotifierOrNull
                ?.currentState
                .deck
                ?.title ==
            'Browser roundtrip',
        reason: 'browser copy did not reopen',
      );
      await tester.pumpAndSettle();
      final reopened = c
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      expect(reopened.title, 'Browser roundtrip');
      expect(reopened.slides.single.title, 'Picture');
      expect(WebAssetStore.bytesFor(reopened.slides.single.imagePath), image);
      await tester.tap(find.text('storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Verwijderen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verwijderen'));
      await tester.pumpAndSettle();
      expect(await BrowserDeckStore().list(), isEmpty);
    },
  );
}
