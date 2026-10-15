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

  test('copies bytes, preserves source, and verifies exact contents', () async {
    final source = File(p.join(temp.path, 'source.md'));
    await source.writeAsString('Begin');
    var dossier = await store.create('Zaak');
    dossier = await store.addFile(dossier, source, title: 'Bijlage A');
    expect(dossier.entries.single.title, 'Bijlage A');
    expect(dossier.entries.single.relativePath, startsWith('attachments/'));
    expect(await source.readAsString(), 'Begin');
    expect(
      (await store.verify(dossier.entries.single)).status,
      DossierIntegrityStatus.matches,
    );
    expect(
      (await store.load()).entries.single.sha256,
      dossier.entries.single.sha256,
    );

    await File(
      (await store.resolvedPath(dossier.entries.single))!,
    ).writeAsString('Gewijzigd');
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
      expect(
        overview,
        contains('1. [Presentatie](${reordered.entries[0].relativePath})'),
      );
      expect(
        overview,
        contains(
          '2. [Eerste \\[stuk\\]](${reordered.entries[1].relativePath})',
        ),
      );
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
    await File((await store.resolvedPath(dossier.entries.single))!).delete();
    expect(
      (await store.verify(dossier.entries.single)).status,
      DossierIntegrityStatus.missing,
    );
  });
}
