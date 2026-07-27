@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/temp_dir.dart';

// Regressie voor #933: de git-zware suites lieten hun tempmap in tearDown
// intermitterend achter op de Windows-CI, omdat git de handle nog vasthield
// (errno 32). De echte vergrendeling is op macOS niet na te bootsen, dus
// bewijzen we hier het gedrag dát die flakiness wegneemt: de opruiming geeft
// niet bij de eerste tegenvaller op, maar probeert het opnieuw — en een
// tearDown die het uiteindelijk tóch niet lukt, gooit niet en velt zo geen
// geslaagde test.

void main() {
  test('ruimt een gevulde map echt op', () async {
    final dir = Directory.systemTemp.createTempSync('ngm_del');
    File('${dir.path}/sub/f.txt')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');

    await deleteTempDir(dir);
    expect(dir.existsSync(), isFalse);
  });

  test('een reeds verdwenen map is een geluidloze no-op', () async {
    final dir = Directory.systemTemp.createTempSync('ngm_del');
    dir.deleteSync(recursive: true);

    await deleteTempDir(dir); // mag niet gooien
    expect(dir.existsSync(), isFalse);
  });

  test('probeert opnieuw en slaagt zodra de handle los is', () async {
    var calls = 0;
    await deleteTempDir(
      Directory.systemTemp, // ongebruikt: deleteOnce vervangt de echte delete
      retryDelay: Duration.zero,
      deleteOnce: () {
        calls++;
        if (calls < 3) {
          throw const FileSystemException(
            'Deletion failed',
            '',
            OSError('being used by another process', 32),
          );
        }
      },
    );
    expect(calls, 3, reason: 'twee keer geweigerd, de derde poging lukte');
  });

  test('geeft na de laatste poging op zonder te gooien', () async {
    var calls = 0;
    await deleteTempDir(
      Directory.systemTemp,
      attempts: 4,
      retryDelay: Duration.zero,
      deleteOnce: () {
        calls++;
        throw const FileSystemException(
          'Deletion failed',
          '',
          OSError('being used by another process', 32),
        );
      },
    );
    // Vier pogingen gedaan, daarna berust — geen exceptie die de tearDown velt.
    expect(calls, 4);
  });
}
