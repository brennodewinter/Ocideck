// De staging-levenscyclus uit §3.2 op het echte bestandssysteem — de
// "platformproef" uit de acceptatie van #2510: aanmaken, per sessie
// weggooien, verlopen sporen vegen en alles wissen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/recording_staging_io.dart';
import 'package:ocideck/services/transcription/recording_staging_stub.dart'
    as stub;
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late IoRecordingStaging staging;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ocideck_staging_test');
    staging = IoRecordingStaging(baseDir: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory fakeSessionDir(String name) {
    final dir = Directory(p.join(root.path, name))..createSync();
    File(p.join(dir.path, 'opname.wav')).writeAsBytesSync([0, 1, 2]);
    return dir;
  }

  test(
    'createSessionDir maakt een unieke map onder de stagingwortel',
    () async {
      final a = await staging.createSessionDir();
      final b = await staging.createSessionDir();
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(b));
      expect(Directory(a!).existsSync(), isTrue);
      expect(p.dirname(a), root.path);
    },
  );

  test('listSessionDirs noemt alleen echte sessiemappen', () async {
    final dir = await staging.createSessionDir();
    File(p.join(root.path, 'los.txt')).writeAsStringSync('geen map');
    final listed = await staging.listSessionDirs();
    expect(listed, [dir]);
  });

  test('discardDir verwijdert de sessiemap, null doet niets', () async {
    final dir = await staging.createSessionDir();
    await staging.discardDir(dir);
    expect(Directory(dir!).existsSync(), isFalse);
    await staging.discardDir(null);
    await staging.discardDir(dir); // tweede keer is even onschuldig
  });

  test('sweep veegt alleen mappen ouder dan maxAge', () async {
    final dag = const Duration(days: 1).inMilliseconds;
    final nu = DateTime.now().millisecondsSinceEpoch;
    final oud = fakeSessionDir('${nu - 8 * dag}'); // acht dagen oud
    final jong = fakeSessionDir('$nu');
    final vreemd = fakeSessionDir('geen-timestamp');

    await staging.sweep(maxAge: const Duration(days: 7));

    expect(oud.existsSync(), isFalse, reason: 'ouder dan de herstelperiode');
    expect(jong.existsSync(), isTrue, reason: 'herstelperiode loopt nog');
    expect(
      vreemd.existsSync(),
      isTrue,
      reason: 'geen sessienaam, geen leeftijd, dus laten liggen',
    );
  });

  test('sweep met een nummer-achtervoegsel kent de leeftijd ook', () async {
    final dag = const Duration(days: 1).inMilliseconds;
    final nu = DateTime.now().millisecondsSinceEpoch;
    final oud = fakeSessionDir('${nu - 30 * dag}-2');
    await staging.sweep(maxAge: const Duration(days: 7));
    expect(oud.existsSync(), isFalse);
  });

  test('discardAll wist de hele stagingwortel', () async {
    fakeSessionDir('1');
    fakeSessionDir('2');
    await staging.discardAll();
    expect(root.existsSync(), isFalse);
  });

  group('web-stub (§3.2 "Web")', () {
    test('elke call is een eerlijke no-op', () async {
      const s = stub.NoopRecordingStaging();
      expect(await s.createSessionDir(), isNull);
      await s.discardDir('nep-pad');
      await s.discardDir(null);
      await s.sweep(maxAge: const Duration(days: 7));
      await s.discardAll();
      expect(await s.listSessionDirs(), isEmpty);
    });

    test('de fabriek geeft de no-op terug', () {
      expect(stub.createRecordingStaging(), isA<stub.NoopRecordingStaging>());
    });
  });
}
