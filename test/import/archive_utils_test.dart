import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/utils/archive_utils.dart';

/// De zip-bom-beveiliging van de presentatie-import.
///
/// De grenzen zelf staan in gibibytes, dus deze tests zetten ze omlaag; anders
/// zou je twee gigabyte moeten aanmaken om één `if` te raken en bleef de hele
/// beveiliging onbeproefd.
///
/// De meldingen worden meegetoetst, en dat is geen pietluttigheid: ze droegen
/// `'$bytes.length'` in plaats van `'${bytes.length}'`, waardoor de foutmelding
/// bij een te grote invoer de héle bytelijst zou stringificeren — precies in het
/// geval waarin het geheugen al krap is.
void main() {
  List<int> zipOf(Map<String, String> entries) {
    final archive = Archive();
    for (final e in entries.entries) {
      final data = utf8.encode(e.value);
      archive.addFile(ArchiveFile(e.key, data.length, data));
    }
    return ZipEncoder().encode(archive);
  }

  test('een gewoon archief komt er gewoon doorheen', () {
    final archive = safeDecodeZip(zipOf({'a.txt': 'hallo'}));
    expect(archive.map((f) => f.name), contains('a.txt'));
  });

  test('rommel zonder zip-magie wordt geweigerd, niet stil leeg gelezen', () {
    // `archive` 4.x geeft op rommel een *leeg* archief terug waar 3.x nog
    // gooide. Zonder deze controle leest een beschadigd bestand als een
    // presentatie zonder dia's — de gebruiker kreeg "geen dia's gevonden"
    // terwijl zijn bestand kapot was.
    expect(
      () => safeDecodeZip(utf8.encode('dit is geen zip')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Not a ZIP archive'),
        ),
      ),
    );
  });

  test('te grote invoer wordt geweigerd, met het échte aantal bytes', () {
    final bytes = zipOf({'a.txt': 'hallo'});
    expect(
      () => safeDecodeZip(bytes, maxInput: 10),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('${bytes.length} bytes'),
            contains('10 byte limit'),
            // De bug: de bytelijst zelf in de melding.
            isNot(contains('[')),
          ),
        ),
      ),
    );
  });

  test('een te grote losse entry wordt geweigerd, met naam en maat', () {
    expect(
      () => safeDecodeZip(zipOf({'groot.bin': 'abcdefghij'}), maxFile: 5),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('groot.bin'),
            contains('10 bytes'),
            contains('5 byte limit'),
            isNot(contains('ArchiveFile')),
          ),
        ),
      ),
    );
  });

  test('de opgetelde uitgepakte omvang wordt begrensd', () {
    expect(
      () => safeDecodeZip(
        zipOf({'a.txt': 'abcde', 'b.txt': 'fghij'}),
        maxTotal: 6,
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('6 byte limit'),
        ),
      ),
    );
  });
}
