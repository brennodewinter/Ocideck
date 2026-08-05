import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Regressie (beeldkeuring): Instellingen openen op een documenttabblad liet de
/// hele app crashen met "deckNotifier opgevraagd op een documenttabblad".
/// settings_dialog las `current?.deckNotifier…`, waar de `?.` alleen een null
/// `current` afving — niet de gooiende compat-getter op een documenttab. De fix
/// leest `deckNotifierOrNull`. Instellingen is globaal, dus dit is blokkerend.
void main() {
  testWidgets('Instellingen openen op een documenttabblad crasht niet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final temp = Directory.systemTemp.createTempSync('doc_settings');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync('# Memo\n\nGewoon een document.\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Open een plat document → het actieve tabblad is een documenttabblad.
    // In runAsync: openFileByPath doet echte schijf-IO die de test-klok niet
    // aandrijft (anders hangt de test).
    await tester.runAsync(
      () => container.read(tabsProvider.notifier).openFileByPath(path),
    );
    expect(container.read(tabsProvider).current!.kind, MarkdownKind.document);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    await tester.pump();
    await tester.tap(find.text('open'));
    // Bewust géén pumpAndSettle: de crash (vóór de fix) valt al in de eerste
    // build/initState van de dialoog; het volledige instellingenvenster settelt
    // niet snel genoeg door zijn eigen timers, en dat is niet wat we toetsen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Vóór de fix gooide de dialoog-init hier "deckNotifier opgevraagd op een
    // documenttabblad"; nu opent hij gewoon.
    expect(tester.takeException(), isNull);
    // Ruim eventuele lopende timers van de (half opgebouwde) dialoog netjes op.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
