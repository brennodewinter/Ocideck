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
}
