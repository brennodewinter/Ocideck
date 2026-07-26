import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/utils/archive_utils.dart';
import 'package:ocideck/services/import/utils/import_budget.dart';

/// De zip-bom-beveiliging van de presentatie-import, nu gedreven door één
/// centraal [ImportBudget] (#874).
///
/// De productiegrenzen staan in honderden mebibytes, dus deze tests zetten met
/// [ImportBudget.forTest] een piepklein budget; anders zou je een halve gigabyte
/// moeten aanmaken om één `if` te raken en bleef de hele beveiliging onbeproefd.
///
/// Een budgetoverschrijding is een [ImportBudgetException] (niet meer een kale
/// `FormatException`): de importer vertaalt die naar de echte reden "te groot",
/// niet "beschadigd". Alleen een ontbrekende zip-kop blijft een `FormatException`
/// — dat is een ander soort fout.
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
    // terwijl zijn bestand kapot was. Dit blijft een FormatException: geen zip,
    // niet "te groot".
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

  test('te grote invoer wordt geweigerd als budgetoverschrijding', () {
    final bytes = zipOf({'a.txt': 'hallo'});
    expect(
      () => safeDecodeZip(
        bytes,
        budget: ImportBudget.forTest(maxSourceBytes: 10),
      ),
      throwsA(
        isA<ImportBudgetException>().having(
          (e) => e.limitLabel,
          'limitLabel',
          contains('10 bytes'),
        ),
      ),
    );
  });

  test('te veel onderdelen wordt geweigerd, los van de grootte', () {
    // Drie piepkleine onderdelen, budget van twee: de telling begrenst de
    // uitpaklus onafhankelijk van de bytegrootte.
    expect(
      () => safeDecodeZip(
        zipOf({'a.txt': 'x', 'b.txt': 'y', 'c.txt': 'z'}),
        budget: ImportBudget.forTest(maxArchiveEntries: 2),
      ),
      throwsA(
        isA<ImportBudgetException>().having(
          (e) => e.limitLabel,
          'limitLabel',
          contains('2 onderdelen'),
        ),
      ),
    );
  });

  test('een te grote losse entry wordt geweigerd', () {
    expect(
      () => safeDecodeZip(
        zipOf({'groot.bin': 'abcdefghij'}),
        budget: ImportBudget.forTest(maxUncompressedEntry: 5),
      ),
      throwsA(
        isA<ImportBudgetException>().having(
          (e) => e.limitLabel,
          'limitLabel',
          contains('per onderdeel'),
        ),
      ),
    );
  });

  test('de opgetelde uitgepakte omvang wordt begrensd', () {
    expect(
      () => safeDecodeZip(
        zipOf({'a.txt': 'abcde', 'b.txt': 'fghij'}),
        budget: ImportBudget.forTest(maxUncompressedTotal: 6),
      ),
      throwsA(
        isA<ImportBudgetException>().having(
          (e) => e.limitLabel,
          'limitLabel',
          contains('uitgepakt'),
        ),
      ),
    );
  });
}
