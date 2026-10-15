import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/document_dossier.dart';
import 'package:ocideck/services/document_dossier_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late DocumentDossierStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dossier-test-');
    store = DocumentDossierStore(File(p.join(temp.path, 'zaak.dossier.json')));
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('indexes original bytes and detects source changes', () async {
    final source = File(p.join(temp.path, 'source.md'));
    await source.writeAsString('Begin');
    var dossier = await store.create('Zaak');
    dossier = await store.addFile(dossier, source, title: 'Bijlage A');
    expect(dossier.entries.single.title, 'Bijlage A');
    expect(
      dossier.entries.single.sourcePath,
      await source.resolveSymbolicLinks(),
    );
    expect(dossier.entries.single.originalName, 'source.md');
    expect(dossier.entries.single.sizeBytes, 5);
    expect(dossier.entries.single.checkedAt, isNotNull);
    expect(await source.readAsString(), 'Begin');
    expect(
      (await store.verify(dossier.entries.single)).status,
      DossierIntegrityStatus.matches,
    );
    expect(
      (await store.load()).entries.single.sha256,
      dossier.entries.single.sha256,
    );

    await source.writeAsString('Gewijzigd');
    expect(
      (await store.verify(dossier.entries.single)).status,
      DossierIntegrityStatus.changed,
    );
    expect(
      (await store.load()).entries.single.sha256,
      dossier.entries.single.sha256,
      reason: 'controle accepteert de wijziging niet stilzwijgend',
    );
    await expectLater(
      store.refreshReference(
        dossier,
        dossier.entries.single.id,
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
    dossier = await store.refreshReference(dossier, dossier.entries.single.id);
    expect(
      dossier.entries.single.hashHistory.single.sha256,
      isNot(dossier.entries.single.sha256),
    );
    expect(dossier.entries.single.sizeBytes, 9);
    expect(
      (await store.verify(dossier.entries.single)).status,
      DossierIntegrityStatus.matches,
    );
  });

  test(
    'writes a readable, ordered overview with safe links and full hashes',
    () async {
      var dossier = await store.create('Zaak #1');
      final first = File(p.join(temp.path, 'eerste.md'));
      final second = File(p.join(temp.path, 'tweede.pptx'));
      await first.writeAsString('A');
      await second.writeAsBytes([1, 2, 3]);
      dossier = await store.addFile(dossier, first, title: 'Eerste [stuk]');
      dossier = await store.addFile(dossier, second, title: 'Presentatie');
      final reordered = dossier.copyWith(
        entries: dossier.entries.reversed.toList(),
      );
      await store.save(reordered);
      final overview = await store.overviewFile.readAsString();
      expect(overview, startsWith('# Zaak \\#1\n'));
      expect(overview, contains('1. [Presentatie](tweede.pptx)'));
      expect(overview, contains('2. [Eerste \\[stuk\\]](eerste.md)'));
      for (final entry in reordered.entries) {
        expect(overview, contains('SHA-256: `${entry.sha256}`'));
      }
      expect(
        overview.indexOf('Presentatie'),
        lessThan(overview.indexOf('Eerste')),
      );
    },
  );

  test('keeps user-edited overview and manifest unchanged on save', () async {
    final dossier = await store.create('Zaak');
    await store.overviewFile.writeAsString('# Mijn eigen aantekeningen\n');
    final previousManifest = await store.manifestFile.readAsString();
    await expectLater(
      store.save(dossier.copyWith(title: 'Nieuwe titel')),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await store.overviewFile.readAsString(),
      '# Mijn eigen aantekeningen\n',
    );
    expect(await store.manifestFile.readAsString(), previousManifest);
  });

  test('round trips unknown dossier and entry fields', () async {
    var dossier = await store.create('Zaak');
    final source = File(p.join(temp.path, 'bijlage.pptx'));
    await source.writeAsBytes([1, 2, 3]);
    dossier = await store.addFile(dossier, source);
    final json =
        jsonDecode(await store.manifestFile.readAsString())
            as Map<String, dynamic>;
    json['futureField'] = {'style': 'blue'};
    (json['entries'] as List).single['futureEntryField'] = [42];
    await store.manifestFile.writeAsString(jsonEncode(json));
    final loaded = await store.load();
    await store.save(loaded.copyWith(title: 'Nieuw'));
    final reread =
        jsonDecode(await store.manifestFile.readAsString())
            as Map<String, dynamic>;
    expect(reread['futureField'], {'style': 'blue'});
    expect((reread['entries'] as List).single['futureEntryField'], [42]);
  });

  test(
    'rejects traversal and outside symlink before opening or hashing',
    () async {
      final dossier = await store.create('Zaak');
      final outsideDir = await Directory.systemTemp.createTemp(
        'dossier-outside-',
      );
      addTearDown(() => outsideDir.delete(recursive: true));
      final outside = File(p.join(outsideDir.path, 'outside.md'));
      await outside.writeAsString('secret');
      final forged = DossierEntry(
        id: 'one',
        title: 'Forged',
        relativePath: '../outside.md',
        sha256: '0' * 64,
      );
      expect(
        (await store.verify(forged)).status,
        DossierIntegrityStatus.unsafe,
      );
      expect(await store.resolvedPath(forged), isNull);
      await expectLater(
        store.save(dossier.copyWith(entries: [forged])),
        throwsFormatException,
      );

      final linkDir = Directory(p.join(temp.path, 'attachments'));
      await linkDir.create();
      final link = Link(p.join(linkDir.path, 'escape.md'));
      await link.create(outside.path);
      final linked = forged.copyWith(relativePath: 'attachments/escape.md');
      expect(
        (await store.verify(linked)).status,
        DossierIntegrityStatus.unsafe,
      );
      expect(await store.resolvedPath(linked), isNull);
    },
  );

  test('missing attachment is reported separately', () async {
    var dossier = await store.create('Zaak');
    final source = File(p.join(temp.path, 'source.md'));
    await source.writeAsString('Text');
    dossier = await store.addFile(dossier, source);
    await source.delete();
    expect(
      (await store.verify(dossier.entries.single)).status,
      DossierIntegrityStatus.missing,
    );
  });

  test('records check time without accepting changed bytes', () async {
    final source = File(p.join(temp.path, 'source.md'));
    await source.writeAsString('A');
    var dossier = await store.create('Zaak');
    dossier = await store.addFile(dossier, source);
    final originalHash = dossier.entries.single.sha256;
    await source.writeAsString('B');
    final (checked, result) = await store.verifyAndRecord(
      dossier,
      dossier.entries.single,
    );
    expect(result.status, DossierIntegrityStatus.changed);
    expect(result.checkedAt, isNotNull);
    expect(checked.entries.single.sha256, originalHash);
    final reopened = await store.load();
    expect(reopened.entries.single.checkedAt, result.checkedAt);
    expect(reopened.entries.single.sha256, originalHash);
  });

  test('migrates v1 copied attachment without losing unknown fields', () async {
    final attachment = File(p.join(temp.path, 'attachments', 'old.md'));
    await attachment.parent.create();
    await attachment.writeAsString('old');
    final legacy = {
      'version': 1,
      'title': 'Oud',
      'entries': [
        {
          'id': 'old',
          'title': 'Oud document',
          'relativePath': 'attachments/old.md',
          'sha256':
              'cba06b5736faf67e54b07b561eae94395e774c517a7d910a54369e1263ccfbd4',
          'futureEntry': 42,
        },
      ],
      'createdAt': DateTime.utc(2020).toIso8601String(),
      'updatedAt': DateTime.utc(2020).toIso8601String(),
      'futureDossier': true,
    };
    await store.manifestFile.writeAsString(jsonEncode(legacy));
    final dossier = await store.load();
    expect(
      await store.resolvedPath(dossier.entries.single),
      await attachment.resolveSymbolicLinks(),
    );
    await store.save(dossier);
    final migrated =
        jsonDecode(await store.manifestFile.readAsString())
            as Map<String, dynamic>;
    expect(migrated['version'], 2);
    expect(migrated['futureDossier'], true);
    expect((migrated['entries'] as List).single['futureEntry'], 42);
  });

  test('source replacement by symlink is unsafe', () async {
    final source = File(p.join(temp.path, 'source.md'));
    await source.writeAsString('Original');
    var dossier = await store.create('Zaak');
    dossier = await store.addFile(dossier, source);
    final outsideDir = await Directory.systemTemp.createTemp('dossier-escape-');
    addTearDown(() => outsideDir.delete(recursive: true));
    final outside = File(p.join(outsideDir.path, 'outside.md'));
    await outside.writeAsString('Outside');
    await source.delete();
    await Link(source.path).create(outside.path);
    expect(
      (await store.verify(dossier.entries.single)).status,
      DossierIntegrityStatus.unsafe,
    );
    expect(await store.resolvedPath(dossier.entries.single), isNull);
  });

  test('relative source follows dossier moved as a whole', () async {
    final source = File(p.join(temp.path, 'inside.md'));
    await source.writeAsString('Portable');
    var dossier = await store.create('Zaak');
    dossier = await store.addFile(dossier, source);
    expect(dossier.entries.single.sourceRelativePath, 'inside.md');
    final movedRoot = await Directory.systemTemp.createTemp('dossier-moved-');
    addTearDown(() => movedRoot.delete(recursive: true));
    final moved = await temp.rename(p.join(movedRoot.path, 'zaak'));
    final movedStore = DocumentDossierStore(
      File(p.join(moved.path, 'zaak.dossier.json')),
    );
    final reopened = await movedStore.load();
    expect(
      (await movedStore.verify(reopened.entries.single)).status,
      DossierIntegrityStatus.matches,
    );
    expect(
      await movedStore.resolvedPath(reopened.entries.single),
      await File(p.join(moved.path, 'inside.md')).resolveSymbolicLinks(),
    );
  });

  test('manual numbers reserve slots and duplicates are rejected', () async {
    var dossier = await store.create('Zaak');
    final first = File(p.join(temp.path, 'first.md'));
    final second = File(p.join(temp.path, 'second.md'));
    await first.writeAsString('1');
    await second.writeAsString('2');
    dossier = await store.addFile(dossier, first);
    dossier = await store.addFile(dossier, second);
    dossier = dossier.copyWith(
      entries: [
        dossier.entries.first.copyWith(numberOverride: 2),
        dossier.entries.last,
      ],
    );
    expect(dossier.displayNumbers, [2, 1]);
    await store.save(dossier);
    final duplicate = dossier.copyWith(
      entries: [
        dossier.entries.first,
        dossier.entries.last.copyWith(numberOverride: 2),
      ],
    );
    await expectLater(store.save(duplicate), throwsFormatException);
  });
}
