// Een bestand met een geheim erin: rechten eerst, het geheim daarna.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_key_file.dart';
import 'package:path/path.dart' as p;

import 'support/temp_dir.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ocideck_keyfile_'));
  tearDown(() => deleteTempDir(dir));

  int mode(String path) => FileStat.statSync(path).mode & 0x1ff;

  test('schrijft de tekst', () async {
    final path = p.join(dir.path, 'sleutel.txt');
    await writeSecretFile(path, 'geheim\n');
    expect(File(path).readAsStringSync(), 'geheim\n');
  });

  test(
    'het bestand is alleen voor de eigenaar leesbaar (waar bestandsrechten bestaan)',
    () async {
      if (Platform.isWindows) return;
      final path = p.join(dir.path, 'sleutel.txt');
      await writeSecretFile(path, 'geheim\n');
      expect(mode(path), 0x180, reason: '0600');
    },
  );

  test(
    'een bestaand bestand met wijde rechten wordt eerst beperkt, dan overschreven',
    () async {
      if (Platform.isWindows) return;
      final path = p.join(dir.path, 'sleutel.txt');
      File(path).writeAsStringSync('oud');
      await Process.run('chmod', ['644', path]);
      expect(mode(path), 0x1a4);
      await writeSecretFile(path, 'nieuw geheim\n');
      expect(mode(path), 0x180);
      expect(File(path).readAsStringSync(), 'nieuw geheim\n');
    },
  );

  test(
    'een map die niet bestaat is een bestandsfout, geen halve uitkomst',
    () async {
      final path = p.join(dir.path, 'bestaat-niet', 'sleutel.txt');
      await expectLater(
        writeSecretFile(path, 'geheim'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).existsSync(), isFalse);
    },
  );

  test(
    'een map waarin niet te schrijven valt laat geen bestand achter',
    () async {
      if (Platform.isWindows) return;
      final folder = Directory(p.join(dir.path, 'dicht'))..createSync();
      await Process.run('chmod', ['555', folder.path]);
      addTearDown(() => Process.run('chmod', ['755', folder.path]));
      final path = p.join(folder.path, 'sleutel.txt');
      await expectLater(
        writeSecretFile(path, 'geheim'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).existsSync(), isFalse);
    },
  );
}
