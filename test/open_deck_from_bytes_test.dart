import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het in-memory open-pad (webversie: picker/drag-drop levert bytes, geen pad)
/// moet dezelfde fail-closed gates hebben als [TabsNotifier.openFileByPath]:
/// size-cap, UTF-8, security-scan, marp-check — en een geopend tabblad heeft
/// géén filePath, zodat opslaan het downloadpad kiest.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  const validDeck = '''
---
marp: true
theme: ocideck
---

# Webdeck

---

## Tweede slide

- punt één
- punt twee
''';

  (ProviderContainer, TabsNotifier) build() {
    final container = ProviderContainer(
      overrides: [
        // Geen echte herstelmap in tests (path_provider ontbreekt op de VM).
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, container.read(tabsProvider.notifier));
  }

  test(
    'een geldig marp-deck opent in het lege tabblad, zonder filePath',
    () async {
      final (container, tabs) = build();

      final result = await tabs.openDeckFromBytes(bytes(validDeck), 'deck.md');

      expect(result, OpenResult.opened);
      final tab = container.read(tabsProvider).current!;
      expect(tab.isOpen, isTrue);
      // Geen pad: opslaan van dit tabblad moet het downloadpad kiezen.
      expect(tab.deckNotifier.currentState.filePath, isNull);
      expect(tab.deckNotifier.currentState.deck!.slides.length, 2);
      // In-memory bytes hebben geen projectmap.
      expect(tab.deckNotifier.currentState.deck!.projectPath, isNull);
    },
  );

  test(
    'markdown zonder marp-frontmatter wordt geweigerd als niet-presentatie',
    () async {
      final (_, tabs) = build();

      final result = await tabs.openDeckFromBytes(
        bytes('# Gewoon een README\n\nTekst.\n'),
        'README.md',
      );

      expect(result, OpenResult.notAPresentation);
    },
  );

  test(
    'uitvoerbare inhoud wordt geblokkeerd en zet het security-alarm',
    () async {
      final (container, tabs) = build();

      final result = await tabs.openDeckFromBytes(
        bytes('$validDeck\n<script>alert(1)</script>\n'),
        'kwaadaardig.md',
      );

      expect(result, OpenResult.blocked);
      final alarm = container.read(importSecurityAlarmProvider);
      expect(alarm, isNotNull);
      expect(alarm!.path, 'kwaadaardig.md');
      expect(alarm.findings, isNotEmpty);
      // Geblokkeerd = niet geopend.
      expect(container.read(tabsProvider).current!.isOpen, isFalse);
    },
  );

  test('niet-UTF-8-bytes zijn onleesbaar', () async {
    final (_, tabs) = build();

    final result = await tabs.openDeckFromBytes(
      Uint8List.fromList([0xC3, 0x28, 0xA0, 0xA1]),
      'binair.md',
    );

    expect(result, OpenResult.unreadable);
  });

  test(
    'bytes boven de deck-cap zijn onleesbaar (geen decode-poging)',
    () async {
      final (_, tabs) = build();

      final oversized = Uint8List(FileService.maxDeckMarkdownBytes + 1);
      final result = await tabs.openDeckFromBytes(oversized, 'groot.md');

      expect(result, OpenResult.unreadable);
    },
  );
}
