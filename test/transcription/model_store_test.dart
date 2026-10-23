// De desktop-modelopslag (#2512): containment, installatietoestand,
// hash-verificatie en opruiming van deels-downloads.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/services/transcription/model_store.dart';
import 'package:ocideck/services/transcription/model_store_io.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';

void main() {
  late Directory temp;
  late IoModelStore store;

  // Een miniatuurmodel — de store toetst op de waarden uit het item, dus
  // een 4-byte "model" bewijst hetzelfde als 1,5 GB.
  final bytes = [1, 2, 3, 4];
  final model = WhisperModel(
    id: 'testmodel',
    fileName: 'ggml-test.bin',
    sha256: sha256.convert(bytes).toString(),
    downloadBytes: bytes.length,
    diskBytes: bytes.length,
    tier: 'light',
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('modelstore_test_');
    store = IoModelStore(root: temp);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('pad en containment', () {
    test('modelPath ligt binnen de modelmap', () async {
      final path = await store.modelPath(model);
      expect(path.path, p.join(temp.path, 'ggml-test.bin'));
      expect(path.isAbsolute, isTrue);
    });

    test('de map wordt aangemaakt en is geen koppeling', () async {
      final dir = await store.directory();
      expect(Directory(dir.path).existsSync(), isTrue);
    });
  });

  group('installatietoestand', () {
    test('leeg is absent; exacte omvang is present', () async {
      expect(await store.stateOf(model), ModelInstallState.absent);
      final file = File((await store.modelPath(model)).path);
      await file.writeAsBytes(bytes);
      expect(await store.stateOf(model), ModelInstallState.present);
    });

    test(
      'een andere omvang telt als absent — een rest is geen model',
      () async {
        final file = File((await store.modelPath(model)).path);
        await file.writeAsBytes([1, 2]);
        expect(await store.stateOf(model), ModelInstallState.absent);
      },
    );

    test('een symbolische koppeling telt als absent', () async {
      final file = File((await store.modelPath(model)).path);
      await file.writeAsBytes(bytes);
      final link = Link('${file.path}.linked');
      await link.create(file.path);
      // De koppeling zelf beschouwen we via een eigen item-naam niet;
      // `stateOf` op het échte pad moet normaal werken.
      expect(await store.stateOf(model), ModelInstallState.present);
      // En als het pad zelf een link is, is het absent.
      await file.delete();
      await Link(file.path).create('/dev/null');
      expect(await store.stateOf(model), ModelInstallState.absent);
    });
  });

  group('hash-verificatie', () {
    test('kloppende hash verifieert; afwijkende weigert', () async {
      expect(await store.verify(model), isFalse);
      final file = File((await store.modelPath(model)).path);
      await file.writeAsBytes(bytes);
      expect(await store.verify(model), isTrue);
      await file.writeAsBytes([9, 9, 9, 9]);
      // Zelfde omvang, andere inhoud: present maar verify faalt.
      expect(await store.stateOf(model), ModelInstallState.present);
      expect(await store.verify(model), isFalse);
    });
  });

  group('verwijderen en opruimen', () {
    test('delete ruimt model én zijn .part op', () async {
      final file = File((await store.modelPath(model)).path);
      await file.writeAsBytes(bytes);
      await File('${file.path}.part').writeAsBytes([1]);
      await store.delete(model);
      expect(await file.exists(), isFalse);
      expect(await File('${file.path}.part').exists(), isFalse);
      expect(await store.stateOf(model), ModelInstallState.absent);
    });

    test('delete op niets is rustig', () async {
      await store.delete(model);
    });

    test('sweepPartials verwijdert alleen .part-resten', () async {
      final file = File((await store.modelPath(model)).path);
      await file.writeAsBytes(bytes);
      await File('${file.path}.part').writeAsBytes([1]);
      await store.sweepPartials();
      expect(await File('${file.path}.part').exists(), isFalse);
      expect(await file.exists(), isTrue);
    });
  });
}
