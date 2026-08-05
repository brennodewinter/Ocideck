import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// De identiteitspoort is een router, geen muur (DOCUMENT_MODE.md §2): een `.md`
/// zonder `marp: true` opent als plat document in plaats van geweigerd te worden.
void main() {
  late Directory temp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('doc_router');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('een plat .md opent als documenttabblad, byte-getrouw', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const source = '# Memo\n\nEen gewoon document.\n';
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync(source);

    final result = await container
        .read(tabsProvider.notifier)
        .openFileByPath(path);
    expect(result, OpenResult.opened);

    final current = container.read(tabsProvider).current!;
    expect(current.kind, MarkdownKind.document);
    expect(
      current.documentNotifier!.currentState.document!.toMarkdown(),
      source,
    );
  });

  test('een marp-deck opent nog steeds als presentatie', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final path = p.join(temp.path, 'deck.md');
    File(
      path,
    ).writeAsStringSync('---\nmarp: true\ntheme: ocideck\n---\n\n# Titel\n');

    final result = await container
        .read(tabsProvider.notifier)
        .openFileByPath(path);
    expect(result, OpenResult.opened);
    expect(
      container.read(tabsProvider).current!.kind,
      MarkdownKind.presentation,
    );
  });
}
