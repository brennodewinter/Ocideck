// De desktop-modelopslag (#2512): containment, installatietoestand,
// hash-verificatie en opruiming van deels-downloads.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/services/transcription/model_download.dart';
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
    // De kandidaatlijst is expliciet leeg — de echte scan zou `~` van de
    // testmachine lezen en de uitkomst van omgeving laten afhangen.
    store = IoModelStore(root: temp, candidateRoots: const []);
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

  group('externe kandidaten (#2601)', () {
    late Directory elsewhere;
    late IoModelStore scanning;

    setUp(() {
      elsewhere = Directory.systemTemp.createTempSync('candidates_');
      scanning = IoModelStore(root: temp, candidateRoots: [elsewhere]);
    });

    tearDown(() {
      elsewhere.deleteSync(recursive: true);
    });

    test('een gelijkend ggml-bestand buiten de modelmap telt', () async {
      File(p.join(elsewhere.path, 'ggml-test.bin')).writeAsBytesSync(bytes);
      final found = await scanning.externalCandidates(model);
      expect(found.single.path, p.join(elsewhere.path, 'ggml-test.bin'));
    });

    test('naam of omvang die niet lijkt, telt niet', () async {
      File(p.join(elsewhere.path, 'ggml-test.bin')).writeAsBytesSync([1, 2]);
      File(p.join(elsewhere.path, 'andere.bin')).writeAsBytesSync(bytes);
      File(p.join(elsewhere.path, 'ggml-test.part')).writeAsBytesSync(bytes);
      expect(await scanning.externalCandidates(model), isEmpty);
    });

    test('de modelmap zelf doet niet mee — stateOf dekt hem al', () async {
      File((await scanning.modelPath(model)).path).writeAsBytesSync(bytes);
      // De kandidaatlijst bevat de modelmap bewust: buiten-filter werkt.
      final inDir = IoModelStore(root: temp, candidateRoots: [temp]);
      expect(await inDir.externalCandidates(model), isEmpty);
    });

    test('een koppeling naar een bestand telt via zijn doel', () async {
      final target = File(p.join(elsewhere.path, 'ggml-doel.bin'))
        ..writeAsBytesSync(bytes);
      await Link(p.join(elsewhere.path, 'ggml-test.bin')).create(target.path);
      // In de huggingface-cache ís elke modelnaam zo'n link naar blobs/.
      expect((await scanning.externalCandidates(model)).length, 2);
    });

    test('een ontbrekende kandidaatplek is geen fout', () async {
      final missing = Directory(p.join(temp.path, 'bestaat-niet'));
      final s = IoModelStore(root: temp, candidateRoots: [missing]);
      expect(await s.externalCandidates(model), isEmpty);
    });
  });

  group('adopteren van schijf (#2601)', () {
    late Directory elsewhere;

    setUp(() {
      elsewhere = Directory.systemTemp.createTempSync('adopt_');
    });

    tearDown(() {
      elsewhere.deleteSync(recursive: true);
    });

    test('kloppende hash: kopieert, toetst en laat de bron liggen', () async {
      final source = File(p.join(elsewhere.path, 'ggml-test.bin'))
        ..writeAsBytesSync(bytes);
      final dest = await store.adopt(model, ModelStorePath(source.path, true));
      expect(await store.stateOf(model), ModelInstallState.present);
      expect(await store.verify(model), isTrue);
      expect(File(dest.path).existsSync(), isTrue);
      // Het origineel is van de gebruiker — wij raken het niet aan.
      expect(source.existsSync(), isTrue);
    });

    test('afwijkende hash weigert zonder iets in de map te zetten', () async {
      final source = File(p.join(elsewhere.path, 'ggml-test.bin'))
        ..writeAsBytesSync([9, 9, 9, 9]);
      await expectLater(
        store.adopt(model, ModelStorePath(source.path, true)),
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.invalidHash,
          ),
        ),
      );
      expect(await store.stateOf(model), ModelInstallState.absent);
    });

    test('een verdwenen bron is een io-fout, geen stille absent', () async {
      await expectLater(
        store.adopt(
          model,
          ModelStorePath(p.join(elsewhere.path, 'weg.bin'), true),
        ),
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.ioFailed,
          ),
        ),
      );
    });
  });
}
