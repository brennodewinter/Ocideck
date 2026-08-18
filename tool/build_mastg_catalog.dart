// Genereert de offline MASTG-testindex uit een uitgepakte OWASP/mastg-release,
// tegenhanger van tool/build_cwe_catalog.dart.
//
// Invoer: de release-tarball van github.com/OWASP/mastg, uitgepakt.
//   curl -sL https://github.com/OWASP/mastg/archive/refs/tags/v2.0.0.tar.gz | tar xz
// dan:
//   dart run tool/build_mastg_catalog.dart mastg-2.0.0 2.0.0
//
// Uitvoer: lib/services/mastg_catalog_android.dart en _ios.dart — twee delen,
// omdat 186 tests in één bestand over de regelratchet van 1000 gaan en de
// splitsing per platform ook inhoudelijk klopt.
//
// Twee dingen die deze generator bewust weglaat, en waarom:
//
//   1. Alles onder `tests/` — dat zijn de 92 v1-tests, in v2.0.0 stuk voor stuk
//      `status: deprecated` met een verwijzing naar hun opvolger. Ze bundelen
//      zou een checklist vullen met tests die OWASP heeft ingetrokken.
//   2. Alles met `status: placeholder` — 14 stuks: wél een titel en een
//      voorgenomen aanpak, maar geen uitgeschreven test. In een klantrapport
//      zou zo'n regel een controle suggereren die niemand kan uitvoeren.
//
// De v2-tests staan in `tests-beta/`. Die naam is verwarrend maar klopt: de
// herbouwde inhoud van v2.0.0 woont daar, en `tests/` is het archief.
import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/build_mastg_catalog.dart <uitgepakte-repo> <versie>',
    );
    exit(2);
  }
  final root = Directory(args[0]);
  final version = args[1];
  if (!root.existsSync()) {
    stderr.writeln('build_mastg_catalog: ${root.path} bestaat niet');
    exit(2);
  }

  final tests = <_Test>[];
  final beta = Directory('${root.path}/tests-beta');
  if (!beta.existsSync()) {
    stderr.writeln(
      'build_mastg_catalog: geen tests-beta/ — verkeerde release?',
    );
    exit(2);
  }

  for (final entity in beta.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    if (entity.uri.pathSegments.last == 'index.md') continue;
    final test = _parse(entity, beta.path);
    if (test != null) tests.add(test);
  }

  if (tests.isEmpty) {
    stderr.writeln(
      'build_mastg_catalog: niets gevonden — is de opzet gewijzigd?',
    );
    exit(1);
  }
  tests.sort((a, b) => a.id.compareTo(b.id));

  for (final platform in ['android', 'ios']) {
    // `network` is een derde platform met twee tests; die horen bij het
    // mobiele netwerkverkeer en gaan bij Android mee, zodat er niet voor twee
    // regels een derde bestand bijkomt.
    final selected = tests
        .where(
          (t) =>
              platform == 'android' ? t.platform != 'ios' : t.platform == 'ios',
        )
        .toList();
    File('lib/services/mastg_catalog_$platform.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(_render(platform, selected));
    stdout.writeln('mastg_catalog_$platform.dart: ${selected.length} tests');
  }
  stdout.writeln(
    'Totaal ${tests.length} tests uit MASTG v$version.\n'
    'Draai je dit gereedschap los, leg de versie dan zelf vast: '
    'dart run tool/record_catalog_version.dart mastg $version '
    '(scripts/refresh_catalogs.sh doet dat al voor je).',
  );
}

class _Test {
  _Test(this.id, this.title, this.platform, this.category, this.weakness);
  final String id, title, platform, category, weakness;
}

/// Leest de front matter. Geeft null voor een placeholder of een bestand
/// zonder front matter — beide zijn geen bundelbare test.
_Test? _parse(File file, String betaRoot) {
  final text = file.readAsStringSync();
  if (!text.startsWith('---')) return null;
  final end = text.indexOf('\n---', 3);
  if (end < 0) return null;
  final front = text.substring(3, end);

  String field(String key) =>
      RegExp(
        '^$key:\\s*(.+)\$',
        multiLine: true,
      ).firstMatch(front)?.group(1).toString().trim() ??
      '';

  if (field('status') == 'placeholder') return null;

  // tests-beta/<platform>/<MASVS-CATEGORIE>/<id>.md
  final rel = file.path
      .substring(betaRoot.length + 1)
      .split(Platform.pathSeparator);
  if (rel.length < 3) return null;

  final id = field('id').isEmpty
      ? file.uri.pathSegments.last.replaceAll('.md', '')
      : field('id');
  final title = field('title');
  if (id.isEmpty || title.isEmpty) return null;

  return _Test(
    id,
    title,
    field('platform').isEmpty ? rel[0] : field('platform'),
    rel[1],
    field('weakness'),
  );
}

String _render(String platform, List<_Test> tests) {
  final label = platform == 'android' ? 'Android' : 'iOS';
  final b = StringBuffer()
    ..writeln('// GEGENEREERD door tool/build_mastg_catalog.dart — niet met de')
    ..writeln('// hand bijwerken. Zie dat bestand voor de bron en de regels.')
    ..writeln('//')
    ..writeln(
      '// OWASP MASTG, © de OWASP Foundation, CC-BY-SA-4.0. Gebundeld is',
    )
    ..writeln(
      '// alleen de test-index (id, titel, MASVS-categorie, MASWE-koppeling);',
    )
    ..writeln('// de inhoud van de tests staat op mas.owasp.org.')
    ..writeln("part of 'mastg_catalog.dart';")
    ..writeln()
    ..writeln('/// De $label-tests uit de MASTG-index (${tests.length}).')
    ..writeln('const List<MastgTest> _${platform}Tests = [');
  for (final t in tests) {
    b
      ..writeln('  MastgTest(')
      ..writeln("    id: '${_esc(t.id)}',")
      ..writeln("    title: '${_esc(t.title)}',")
      ..writeln("    platform: '${_esc(t.platform)}',")
      ..writeln("    category: '${_esc(t.category)}',")
      ..writeln("    weakness: '${_esc(t.weakness)}',")
      ..writeln('  ),');
  }
  b.writeln('];');
  return b.toString();
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
