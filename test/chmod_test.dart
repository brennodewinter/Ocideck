// `chmod` is één aanroep op één plek (lib/utils/chmod.dart): wat erdoor komt, en wat niet.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/chmod.dart';
import 'package:path/path.dart' as p;

import 'support/temp_dir.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ocideck_chmod_'));
  tearDown(() => deleteTempDir(dir));

  int mode(String path) => FileStat.statSync(path).mode & 0x1ff;

  test('zet de rechten en zegt dat het gelukt is', () async {
    if (Platform.isWindows) return;
    final file = File(p.join(dir.path, 'a'))..writeAsStringSync('x');
    expect(await chmodPath('600', file.path), isTrue);
    expect(mode(file.path), 0x180);
    expect(await chmodPath('644', file.path), isTrue);
    expect(mode(file.path), 0x1a4);
  });

  test('een map werkt ook, met een modus van vier cijfers', () async {
    if (Platform.isWindows) return;
    expect(await chmodPath('0700', dir.path), isTrue);
    expect(mode(dir.path), 0x1c0);
  });

  test('een pad dat er niet is: false, geen uitzondering', () async {
    if (Platform.isWindows) return;
    expect(await chmodPath('600', p.join(dir.path, 'bestaat-niet')), isFalse);
  });

  test(
    'alleen een octale modus komt door: nooit een optie of een uitdrukking',
    () async {
      final file = File(p.join(dir.path, 'a'))..writeAsStringSync('x');
      for (final bad in [
        '',
        '60',
        '66666',
        '8',
        '-R',
        '600;',
        'u+rwx',
        '600 ',
        ' 600',
        '+x',
      ]) {
        await expectLater(
          chmodPath(bad, file.path),
          throwsA(isA<ArgumentError>()),
          reason: '"$bad"',
        );
      }
    },
  );
}
