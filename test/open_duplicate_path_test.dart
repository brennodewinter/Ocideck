import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

/// Dezelfde presentatie hoort maar één keer open te staan. Open je een bestand
/// dat al in een tabblad geladen is nog een keer, dan springt de app naar dat
/// bestaande tabblad in plaats van een tweede kopie te openen — dat voorkomt
/// versieverwarring (twee tabs die los van elkaar hetzelfde bestand bewerken).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const validDeck = '''
---
marp: true
theme: ocideck
---

# Eerste slide

---

## Tweede slide
''';

  (ProviderContainer, TabsNotifier) build() {
    final container = ProviderContainer(
      overrides: [
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, container.read(tabsProvider.notifier));
  }

  Future<String> writeDeck(String name) async {
    final dir = await Directory.systemTemp.createTemp('ocideck_dup_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, name));
    await file.writeAsString(validDeck);
    return file.path;
  }

  test(
    'hetzelfde bestand tweemaal openen springt naar het bestaande tabblad',
    () async {
      final (container, tabs) = build();
      final path = await writeDeck('deck.md');

      expect(await tabs.openFileByPath(path), OpenResult.opened);
      expect(container.read(tabsProvider).tabs.length, 1);

      // Open een tweede, ander deck ernaast zodat het originele tabblad niet
      // meer het geselecteerde is.
      final other = await writeDeck('ander.md');
      expect(await tabs.openFileByPath(other), OpenResult.opened);
      expect(container.read(tabsProvider).tabs.length, 2);
      expect(container.read(tabsProvider).selectedIndex, 1);

      // Het eerste deck opnieuw openen maakt géén derde tabblad, maar springt
      // terug naar het bestaande (index 0).
      expect(await tabs.openFileByPath(path), OpenResult.opened);
      expect(container.read(tabsProvider).tabs.length, 2);
      expect(container.read(tabsProvider).selectedIndex, 0);
    },
  );

  test(
    'een niet-genormaliseerd pad naar hetzelfde bestand telt als dubbel',
    () async {
      final (container, tabs) = build();
      final path = await writeDeck('deck.md');

      expect(await tabs.openFileByPath(path), OpenResult.opened);
      // Zelfde bestand, maar via een pad met een redundante `.`-component.
      final dir = p.dirname(path);
      final messy = p.join(dir, '.', p.basename(path));
      expect(await tabs.openFileByPath(messy), OpenResult.opened);

      expect(container.read(tabsProvider).tabs.length, 1);
      expect(container.read(tabsProvider).selectedIndex, 0);
    },
  );
}
