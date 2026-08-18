// Legt vast wélke uitgave van een gebundelde catalogus er nu in zit: de
// constante in de catalogus zelf én de regel in docs/LICENSE_COMPLIANCE.md.
//
//   dart run tool/record_catalog_version.dart wstg 4.2
//   dart run tool/record_catalog_version.dart maswe 2026-08-04
//
// Dit was tot 18-08-2026 handwerk. De generatoren riepen "zet de versie nu ook
// even daar en daar", en dat ging zoals dat gaat: de Makefile droeg
// MASWE_DATE 2026-08-03, de catalogus 2026-08-04, en wie het advies van de
// Makefile opvolgde zette de datum terug in de tijd. Drie kopieën van hetzelfde
// feit, bijgehouden met de hand.
//
// Waarom dit een Dart-gereedschap is en geen sed-regel in het verversingsscript:
// het vervangen is niet zo triviaal als het lijkt. De licentietabel noemt
// "MITRE CWE 4.20" op de regel boven "WSTG v4.2", en een ongegrensde vervanging
// van 4.2 → 5.0 maakt daar "4.20" tot "5.00" — een licentiedocument dat een
// versie noemt die niet bestaat. Zulke randen horen in een test, en een test
// hoort bij code die je kunt aanroepen. Zie test/record_catalog_version_test.dart.
//
// De aantallen (97 tests, 78 zwakheden, 186 tests) komen uit de zojuist
// gegenereerde bestanden zelf, niet uit een logregel van de generator: een
// telling die je uit uitvoer vist verschuift zodra iemand die zin herschrijft.
import 'dart:io';

/// Eén gebundelde catalogus: waar zijn versie staat, waar zijn inhoud staat en
/// waaraan zijn regel in de licentietabel te herkennen is.
class CatalogRecord {
  const CatalogRecord({
    required this.constFile,
    required this.constName,
    required this.dataFiles,
    required this.entryToken,
    required this.docMarker,
  });

  /// Het handgeschreven catalogusbestand met `const <constName> = '…';`.
  final String constFile;
  final String constName;

  /// De gegenereerde delen waar de items in staan.
  final List<String> dataFiles;

  /// Het begin van één item in die delen; hier wordt op geteld.
  final String entryToken;

  /// Waaraan de rij in de licentietabel herkenbaar is. Bewust het pad van de
  /// catalogus en niet de omschrijving: die omschrijving is proza en wordt
  /// herschreven, het pad niet.
  final String docMarker;
}

const catalogs = <String, CatalogRecord>{
  'wstg': CatalogRecord(
    constFile: 'lib/services/wstg_catalog.dart',
    constName: 'wstgVersion',
    dataFiles: ['lib/services/wstg_catalog_data.dart'],
    entryToken: 'WstgTest(',
    docMarker: 'lib/services/wstg_catalog.dart',
  ),
  'mastg': CatalogRecord(
    constFile: 'lib/services/mastg_catalog.dart',
    constName: 'mastgVersion',
    dataFiles: [
      'lib/services/mastg_catalog_android.dart',
      'lib/services/mastg_catalog_ios.dart',
    ],
    entryToken: 'MastgTest(',
    docMarker: 'lib/services/mastg_catalog.dart',
  ),
  'maswe': CatalogRecord(
    constFile: 'lib/services/maswe_catalog.dart',
    constName: 'masweSnapshotDate',
    dataFiles: ['lib/services/maswe_catalog_data.dart'],
    entryToken: 'MasweWeakness(',
    docMarker: 'lib/services/maswe_catalog.dart',
  ),
};

void main(List<String> args) {
  if (args.length != 2 || !catalogs.containsKey(args[0])) {
    stderr.writeln(
      'usage: dart run tool/record_catalog_version.dart '
      '<${catalogs.keys.join('|')}> <versie>',
    );
    exit(2);
  }
  final id = args[0];
  final version = args[1];
  final record = catalogs[id]!;

  final constFile = File(record.constFile);
  if (!constFile.existsSync()) {
    stderr.writeln('record_catalog_version: ${record.constFile} ontbreekt.');
    exit(2);
  }
  final source = constFile.readAsStringSync();
  final previous = readConst(source, record.constName);
  if (previous == null) {
    stderr.writeln(
      'record_catalog_version: geen "const ${record.constName}" in '
      '${record.constFile} — is de catalogus hernoemd?',
    );
    exit(2);
  }

  var count = 0;
  for (final path in record.dataFiles) {
    final f = File(path);
    if (!f.existsSync()) {
      stderr.writeln(
        'record_catalog_version: $path ontbreekt — eerst genereren.',
      );
      exit(2);
    }
    count += record.entryToken.allMatches(f.readAsStringSync()).length;
  }
  if (count == 0) {
    stderr.writeln(
      'record_catalog_version: nul items geteld in ${record.dataFiles.join(', ')} '
      '— de generator schreef niets, of "${record.entryToken}" heet nu anders.',
    );
    exit(2);
  }

  constFile.writeAsStringSync(setConst(source, record.constName, version));

  final doc = File('docs/LICENSE_COMPLIANCE.md');
  final updated = updateLicenceRow(
    doc.readAsStringSync(),
    marker: record.docMarker,
    previousVersion: previous,
    version: version,
    count: count,
  );
  if (updated == null) {
    stderr.writeln(
      'record_catalog_version: geen rij met "${record.docMarker}" in '
      '${doc.path}. Elke gebundelde dataset hoort daar te staan '
      '(reference_standards_test bewaakt dat) — voeg de rij toe.',
    );
    exit(2);
  }
  doc.writeAsStringSync(updated);

  stdout.writeln(
    '$id: $previous → $version, $count items '
    '(${record.constFile} + ${doc.path}).',
  );
}

/// De waarde van `const <name> = '…';`, of null als hij er niet staat.
String? readConst(String source, String name) => RegExp(
  "^const $name = '([^']*)';",
  multiLine: true,
).firstMatch(source)?.group(1);

/// Diezelfde constante op [value] zetten. Laat de bron ongemoeid als hij er niet
/// in staat — de aanroeper heeft dat via [readConst] al afgevangen.
String setConst(String source, String name, String value) =>
    source.replaceFirst(
      RegExp("^const $name = '[^']*';", multiLine: true),
      "const $name = '$value';",
    );

/// Werkt de rij in de licentietabel bij: het aantal items en de genoemde versie.
/// Null als er geen rij met [marker] is — dat is een fout die de aanroeper hoort
/// te melden, geen stille no-op.
///
/// De vervanging is met opzet nauw: alléén [previousVersion], en alleen waar er
/// links en rechts geen cijfer, punt of streepje tegenaan staat. Zonder die
/// grenzen loopt "4.2" dwars door "MITRE CWE 4.20" heen.
String? updateLicenceRow(
  String doc, {
  required String marker,
  required String previousVersion,
  required String version,
  required int count,
}) {
  final lines = doc.split('\n');
  final index = lines.indexWhere(
    (l) => l.startsWith('|') && l.contains(marker),
  );
  if (index < 0) return null;

  var line = lines[index];
  // Het aantal staat vooraan in de dataset-kolom: "(97 tests: …" of
  // "(78 weaknesses: …". Alleen het eerste voorkomen; verderop in de regel kan
  // een ander getal staan dat niets met de omvang te maken heeft.
  line = line.replaceFirstMapped(
    RegExp(r'\((\d[\d,]*) (tests|weaknesses)'),
    (m) => '($count ${m[2]}',
  );
  if (previousVersion.isNotEmpty) {
    line = line.replaceAll(
      RegExp('(?<![\\d.-])${RegExp.escape(previousVersion)}(?![\\d.-])'),
      version,
    );
  }
  lines[index] = line;
  return lines.join('\n');
}
