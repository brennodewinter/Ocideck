// Genereert de offline WSTG-testindex uit de `checklist.json` van een
// OWASP/wstg-release, naast build_mastg_catalog.dart en build_maswe_catalog.dart.
//
// Invoer: https://raw.githubusercontent.com/OWASP/wstg/v4.2/checklist/checklist.json
//   curl -sLO https://raw.githubusercontent.com/OWASP/wstg/v4.2/checklist/checklist.json
// dan:
//   dart run tool/build_wstg_catalog.dart checklist.json 4.2
//
// Deze catalogus was tot 18-07-2026 met de hand overgetikt. Dat werkte, maar
// maakte een versiesprong duur genoeg om uit te stellen — precies hoe MASTG
// een half jaar bleef liggen. De generator haalt die drempel weg; hij is
// gedraaid tegen v4.2 en levert exact dezelfde 97 tests op als de handmatige
// versie, dus hij verandert vandaag niets en werkt morgen wel.
//
// Eén eigenaardigheid van de bron, die dit gereedschap **meldt** in plaats van
// stilzwijgend op te lossen: in v4.2 komt `WSTG-INPV-13` twee keer voor, met
// twee verschillende titels (Buffer Overflow én Format String Injection). De
// gepubliceerde gids voert de laatste, dus die wint — maar een dubbel id is een
// signaal dat de bron is verschoven, en dat hoort een mens te zien.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/build_wstg_catalog.dart <checklist.json> <versie>',
    );
    exit(2);
  }
  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('build_wstg_catalog: ${file.path} bestaat niet');
    exit(2);
  }
  final version = args[1];

  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final categories = root['categories'];
  if (categories is! Map) {
    stderr.writeln('build_wstg_catalog: geen `categories` — opzet gewijzigd?');
    exit(2);
  }

  final byId = <String, _T>{};
  final collisions = <String, List<String>>{};
  for (final entry in categories.entries) {
    final tests = (entry.value as Map)['tests'];
    if (tests is! List) continue;
    for (final t in tests) {
      final id = (t as Map)['id']?.toString() ?? '';
      final name = t['name']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final existing = byId[id];
      if (existing != null && existing.title != name) {
        collisions.putIfAbsent(id, () => [existing.title]).add(name);
      }
      // Laatste wint: dat is wat de gepubliceerde gids voert.
      byId[id] = _T(id, name, entry.key.toString());
    }
  }

  if (byId.isEmpty) {
    stderr.writeln('build_wstg_catalog: geen tests gevonden');
    exit(1);
  }

  // Bronvolgorde aanhouden, niet sorteren op id. De `categories` in de JSON
  // staan in de volgorde van de gids (Information Gathering eerst, API Testing
  // laatst) en dat is de volgorde waarin een tester de checklist afwerkt.
  // Alfabetisch sorteren zette WSTG-APIT bovenaan en gooide die volgorde om.
  final tests = byId.values.toList();
  File('lib/services/wstg_catalog_data.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(_render(tests, version));

  stdout.writeln('wstg_catalog_data.dart: ${tests.length} tests (v$version)');
  for (final e in collisions.entries) {
    stdout.writeln(
      '  LET OP: ${e.key} komt meer dan eens voor — ${e.value.join(' / ')}. '
      'De laatste is gebruikt; controleer of dat nog klopt met de gids.',
    );
  }
  stdout.writeln(
    'Draai je dit gereedschap los, leg de versie dan zelf vast: '
    'dart run tool/record_catalog_version.dart wstg $version '
    '(scripts/refresh_catalogs.sh doet dat al voor je).',
  );
}

class _T {
  _T(this.id, this.title, this.category);
  final String id, title, category;
}

String _render(List<_T> tests, String version) {
  final b = StringBuffer()
    ..writeln('// GEGENEREERD door tool/build_wstg_catalog.dart — niet met de')
    ..writeln('// hand bijwerken. Zie dat bestand voor de bron en de regels.')
    ..writeln('//')
    ..writeln('// OWASP WSTG v$version, © de OWASP Foundation, CC-BY-SA-4.0.')
    ..writeln(
      '// Gebundeld is alleen de checklist-index; de inhoud van de gids',
    )
    ..writeln('// staat op owasp.org.')
    ..writeln("part of 'wstg_catalog.dart';")
    ..writeln()
    ..writeln('/// De WSTG-checklist (${tests.length} tests).')
    ..writeln('const List<WstgTest> _tests = [');
  for (final t in tests) {
    b
      ..writeln('  WstgTest(')
      ..writeln("    id: '${_esc(t.id)}',")
      ..writeln("    title: '${_esc(t.title)}',")
      ..writeln("    category: '${_esc(t.category)}',")
      ..writeln('  ),');
  }
  b.writeln('];');
  return b.toString();
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
