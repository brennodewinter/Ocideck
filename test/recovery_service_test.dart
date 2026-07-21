import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/recovery_service.dart';

void main() {
  late Directory tempDir;
  late RecoveryService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ocideck_recovery_test');
    service = RecoveryService(baseDir: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  RecoverySnapshot snap(String id, {String label = 'Deck'}) {
    return RecoverySnapshot(
      id: id,
      savedAt: DateTime(2026, 5, 31, 12, 0),
      filePath: '/tmp/$id.md',
      label: label,
      markdown: '# $label\n',
    );
  }

  test('save then loadAll round-trips a snapshot', () async {
    await service.save(snap('a', label: 'Eerste'));
    final all = await service.loadAll();
    expect(all, hasLength(1));
    expect(all.single.id, 'a');
    expect(all.single.label, 'Eerste');
    expect(all.single.markdown, '# Eerste\n');
    expect(all.single.filePath, '/tmp/a.md');
    expect(all.single.userNotes, isNull);
  });

  test('save round-trips user notes in snapshot', () async {
    const notesJson =
        '{"version":1,"slides":[{"index":0,"fp":"abc","text":"Cursusnotitie"}]}';
    await service.save(
      RecoverySnapshot(
        id: 'notes',
        savedAt: DateTime(2026, 6, 1),
        filePath: '/tmp/deck.md',
        label: 'Met notities',
        markdown: '# Deck\n',
        userNotes: notesJson,
      ),
    );
    final all = await service.loadAll();
    expect(all.single.userNotes, notesJson);
  });

  test('save round-trips the seal payload in a snapshot', () async {
    // Juist ná het verzegelen is het deck vuil en nog niet opgeslagen — precies
    // het venster waarin de autosave toeslaat. Zonder dit veld zou herstel de
    // zojuist gezette handtekening laten vallen: het zegelblok staat sinds
    // 0.1.0 niet meer in de markdown.
    const sealJson =
        '{"version":1,"finalized":true,"at":"2026-07-10T12:00:00.000Z",'
        '"signature":{"name":"Jan Jansen"}}';
    await service.save(
      RecoverySnapshot(
        id: 'seal',
        savedAt: DateTime(2026, 7, 10),
        filePath: '/tmp/deck.md',
        label: 'Verzegeld',
        markdown: '# Deck\n',
        seal: sealJson,
      ),
    );
    final all = await service.loadAll();
    expect(all.single.seal, sealJson);
  });

  test('loadAll returns newest first', () async {
    await service.save(
      RecoverySnapshot(
        id: 'old',
        savedAt: DateTime(2026, 1, 1),
        filePath: null,
        label: 'Oud',
        markdown: '',
      ),
    );
    await service.save(
      RecoverySnapshot(
        id: 'new',
        savedAt: DateTime(2026, 5, 1),
        filePath: null,
        label: 'Nieuw',
        markdown: '',
      ),
    );
    final all = await service.loadAll();
    expect(all.map((s) => s.id).toList(), ['new', 'old']);
  });

  test('discard removes only the given snapshot', () async {
    await service.save(snap('a'));
    await service.save(snap('b'));
    await service.discard('a');
    final all = await service.loadAll();
    expect(all.map((s) => s.id), ['b']);
  });

  test('clearAll empties the recovery directory', () async {
    await service.save(snap('a'));
    await service.save(snap('b'));
    await service.clearAll();
    expect(await service.loadAll(), isEmpty);
  });

  test('loadAll is empty (not throwing) for a fresh directory', () async {
    expect(await service.loadAll(), isEmpty);
  });

  test('discard is safe when the file does not exist', () async {
    await service.discard('nope'); // mag geen exception gooien
    expect(await service.loadAll(), isEmpty);
  });

  // The periodic autosave (save) and the "tab became clean" listener (discard)
  // fire independently for the same id. Per-id serialisation must make the
  // later call win, regardless of internal async interleaving.
  test('a discard issued after a save wins: no stale recovery file', () async {
    final saving = service.save(snap('race')); // in flight, not awaited
    final discarding = service.discard('race'); // issued right after
    await Future.wait([saving, discarding]);
    expect(await service.loadAll(), isEmpty);
  });

  test('a save issued after a discard persists', () async {
    await service.save(snap('x'));
    final discarding = service.discard('x');
    final saving = service.save(snap('x', label: 'Opnieuw'));
    await Future.wait([discarding, saving]);
    final all = await service.loadAll();
    expect(all, hasLength(1));
    expect(all.single.label, 'Opnieuw');
  });

  test('many interleaved save/discard pairs end deterministically', () async {
    final ops = <Future<void>>[];
    for (var i = 0; i < 20; i++) {
      ops.add(service.save(snap('loop')));
      ops.add(service.discard('loop')); // last op for the id is a discard
    }
    await Future.wait(ops);
    expect(await service.loadAll(), isEmpty);
  });

  test('pruneOlderThan deletes stale snapshots but keeps fresh ones', () async {
    await service.save(snap('old'));
    await service.save(snap('fresh'));

    // Backdate one file's mtime well past the threshold.
    final oldFile = File('${tempDir.path}/old.json');
    oldFile.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 40)),
    );

    final removed = await service.pruneOlderThan(const Duration(days: 30));
    expect(removed, 1);

    final remaining = await service.loadAll();
    expect(remaining.map((s) => s.id), ['fresh']);
  });

  test('loadAll prunes snapshots older than the default max age', () async {
    await service.save(snap('ancient'));
    File(
      '${tempDir.path}/ancient.json',
    ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 400)));

    expect(await service.loadAll(), isEmpty);
  });

  test('save leaves no .tmp residue behind', () async {
    await service.save(snap('a'));
    final leftovers = tempDir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.tmp'),
    );
    expect(leftovers, isEmpty);
  });

  test('prune and clearAll also remove crashed .json.tmp leftovers', () async {
    // Een .json.tmp is het restant van een atomaire write die een crash niet
    // haalde: plaintext deck-inhoud, dus dezelfde houdbaarheid en opruiming.
    final stale = File('${tempDir.path}/crashed.json.tmp')
      ..writeAsStringSync('{"half":')
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));
    expect(await service.pruneOlderThan(const Duration(days: 30)), 1);
    expect(stale.existsSync(), isFalse);

    File('${tempDir.path}/fresh.json.tmp').writeAsStringSync('{"half":');
    await service.clearAll();
    expect(
      tempDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json.tmp'),
      ),
      isEmpty,
    );
  });

  test('loadAll skips a corrupt snapshot and keeps the healthy ones', () async {
    await service.save(snap('goed'));
    File('${tempDir.path}/kapot.json').writeAsStringSync('{"id": "kapo');
    final all = await service.loadAll();
    expect(all.map((s) => s.id), ['goed']);
  });
}
