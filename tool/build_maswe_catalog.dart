// Genereert de offline MASWE-zwakhedenlijst uit een uitgepakte
// OWASP/maswe-checkout, naast tool/build_mastg_catalog.dart.
//
// Invoer: de repo van github.com/OWASP/maswe, uitgepakt.
//   curl -sL https://github.com/OWASP/maswe/archive/<sha>.tar.gz | tar xz
// dan:
//   dart run tool/build_maswe_catalog.dart maswe-<sha> 2026-08-03
//
// De tweede parameter is een **datum**, geen versienummer, en dat is geen
// slordigheid: MASWE heeft geen releases en geen tags. Er is alleen een
// doorlopende branch, dus het enige eerlijke antwoord op "welke versie heb je
// gebruikt" is de dag waarop je hem hebt overgenomen. De verouderingspoort
// vergelijkt daarom met de datum van de laatste commit.
//
// ── Het herbouwde formaat (medio 2026) ──────────────────────────────────────
// OWASP heeft MASWE grondig herzien. Wat dat voor deze generator betekent:
//   * De collectie is van 117 (waarvan het gros concept) teruggebracht naar 78
//     **uitgeschreven** zwakheden, MASWE-0001..0078. Het onderscheid
//     uitgeschreven/concept — vroeger de front-matter `status:` — bestaat niet
//     meer; álle 78 hebben een volledige pagina. Daarmee vervalt ook de
//     placeholder-splitsing die deze generator ooit maakte.
//   * De omschrijving staat niet meer in de front matter maar in de body onder
//     `## Overview`. De front matter dráágt wel een `requirement:`: één zin die
//     zegt wat de app moet doen. Dat is een scherpere, kortere samenvatting dan
//     de eerste alinea van de Overview, en die nemen we als omschrijving.
//   * Hoger genummerde concept-id's (tot 0119) bestaan niet meer als bestand.
//     Ze leven voort in het nieuwe veld `mappings.maswe-beta`: per canonieke
//     zwakheid de oude beta-id's die erin zijn opgegaan. Dat veld is de brug
//     naar de gebundelde MASTG v2.0.0, die nog naar de beta-nummering verwijst
//     (zie `_betaAliases` verderop).
import 'dart:io';

// Twee beta-id's die MASTG v2.0.0 noemt maar die upstream heeft laten vallen
// zónder `maswe-beta`-koppeling, of die naar meerdere canonieke zwakheden
// splitsen. Zonder deze hand-koppelingen zou de MASTG-kruiskoppeling breken.
// Beide volgen dwingend uit de titel van de MASTG-tests die ze noemen:
//   * MASWE-0097 wordt genoemd door vier tests over root-/jailbreak-detectie
//     ("Jailbreak Detection in Code", "References to Root Detection Mechanisms",
//     …). Upstream gaf er geen beta-koppeling voor; de canonieke tegenhanger is
//     onmiskenbaar MASWE-0051 "Root/Jailbreak Detection Not Implemented".
//   * MASWE-0108 splitst upstream naar 0073 (data-declaraties) én 0074
//     (tracking-domein-declaraties). Een globale alias kan er maar één kiezen;
//     0073 dekt de bredere PII-test, en de tracking-test blijft binnen dezelfde
//     MASVS-PRIVACY-categorie oplosbaar.
const _manualBetaAliases = <String, String>{
  'MASWE-0097': 'MASWE-0051',
  'MASWE-0108': 'MASWE-0073',
};

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/build_maswe_catalog.dart <uitgepakte-repo> <datum>',
    );
    exit(2);
  }
  final dir = Directory('${args[0]}/weaknesses');
  if (!dir.existsSync()) {
    stderr.writeln('build_maswe_catalog: geen weaknesses/ in ${args[0]}');
    exit(2);
  }

  final out = <_W>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    if (entity.uri.pathSegments.last == 'index.md') continue;
    final w = _parse(entity, dir.path);
    if (w == null) continue;
    out.add(w);
  }
  if (out.isEmpty) {
    stderr.writeln('build_maswe_catalog: niets gevonden — opzet gewijzigd?');
    exit(1);
  }
  out.sort((a, b) => a.id.compareTo(b.id));

  // De beta-brug: elk oud beta-id naar de canonieke zwakheid die het heeft
  // opgeslokt. Meerdere kandidaten → de laagste, zodat de uitkomst niet van de
  // bestandsvolgorde afhangt; de hand-koppelingen winnen daar altijd van.
  //
  // Beta- en canonieke id's delen dezelfde nummerruimte: `MASWE-0002` is zowel
  // een huidige zwakheid als een beta-id dat elders is opgegaan. Zo'n sleutel
  // laten we wég uit de brug — `byId` geeft een canoniek id altijd voorrang, dus
  // de alias zou nooit geraadpleegd worden en alleen verwarren. Alleen echt
  // ingetrokken id's (de hoge concept-nummers) blijven over.
  final canonicalIds = {for (final w in out) w.id};
  final betaTargets = <String, List<String>>{};
  for (final w in out) {
    for (final beta in w.betaIds) {
      if (canonicalIds.contains(beta)) continue;
      (betaTargets[beta] ??= []).add(w.id);
    }
  }
  final aliases = <String, String>{};
  final ambiguous = <String, List<String>>{};
  for (final entry in betaTargets.entries) {
    final targets = entry.value..sort();
    if (targets.length > 1) ambiguous[entry.key] = targets;
    aliases[entry.key] = targets.first;
  }
  aliases.addAll(_manualBetaAliases);
  final sortedAliases = aliases.keys.toList()..sort();

  File('lib/services/maswe_catalog_data.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      _render(out, [for (final k in sortedAliases) MapEntry(k, aliases[k]!)]),
    );

  stdout
    ..writeln('maswe_catalog_data.dart: ${out.length} zwakheden')
    ..writeln(
      '  beta-aliassen: ${aliases.length} '
      '(${_manualBetaAliases.length} met de hand)',
    );
  if (ambiguous.isNotEmpty) {
    stdout.writeln(
      '  meervoudig gekoppelde beta-id\'s (laagste gekozen, hand wint):',
    );
    for (final e in ambiguous.entries) {
      stdout.writeln('    ${e.key} -> ${e.value.join(', ')}');
    }
  }
  stdout.writeln(
    'Zet de datum ${args[1]} in lib/services/maswe_catalog.dart én in '
    'lib/services/reference_standards.dart, en controleer '
    'docs/LICENSE_COMPLIANCE.md.',
  );
}

class _W {
  _W(
    this.id,
    this.title,
    this.category,
    this.platforms,
    this.cwe,
    this.description,
    this.betaIds,
  );
  final String id, title, category, description;
  final List<String> platforms;
  final List<int> cwe;
  final List<String> betaIds;
}

/// Null voor een bestand zonder bruikbare front matter.
_W? _parse(File file, String root) {
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

  final id = field('id');
  final title = field('title');
  if (id.isEmpty || title.isEmpty) return null;

  // weaknesses/<MASVS-CATEGORIE>/<id>.md
  final rel = file.path
      .substring(root.length + 1)
      .split(Platform.pathSeparator);
  final category = rel.length >= 2 ? rel[0] : '';

  final cwe = _ints(_bracket('cwe', front));
  final betaIds = _list(_bracket('maswe-beta', front));

  // De `requirement:` is één zin over wat de app moet doen — de scherpste korte
  // omschrijving die de front matter biedt nu `description:` weg is.
  final description = _unquote(field('requirement'));

  return _W(
    id,
    title,
    category,
    _list(field('platform')),
    cwe,
    description,
    betaIds,
  );
}

/// De inhoud van `key: [ ... ]`, waar de sleutel ook ingesprongen onder
/// `mappings:` kan staan.
String _bracket(String key, String front) =>
    RegExp(
      '^\\s*$key:\\s*\\[([^\\]]*)\\]',
      multiLine: true,
    ).firstMatch(front)?.group(1) ??
    '';

List<int> _ints(String raw) => [
  for (final part in raw.split(',')) ?int.tryParse(part.trim()),
];

/// `["android", "ios"]` → `[android, ios]`.
List<String> _list(String raw) => raw
    .replaceAll(RegExp(r'[\[\]"]'), '')
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Haalt de omringende dubbele of enkele aanhalingstekens weg.
String _unquote(String s) {
  if (s.length >= 2 &&
      ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'")))) {
    return s.substring(1, s.length - 1).trim();
  }
  return s;
}

String _render(List<_W> ws, List<MapEntry<String, String>> aliases) {
  final b = StringBuffer()
    ..writeln('// GEGENEREERD door tool/build_maswe_catalog.dart — niet met de')
    ..writeln('// hand bijwerken. Zie dat bestand voor de bron en de regels.')
    ..writeln('//')
    ..writeln('// OWASP MASWE, © de OWASP Foundation, CC-BY-SA-4.0.')
    ..writeln("part of 'maswe_catalog.dart';")
    ..writeln()
    ..writeln('/// De MASWE-zwakheden (${ws.length}), op id gesorteerd.')
    ..writeln('const List<MasweWeakness> _weaknesses = [');
  for (final w in ws) {
    b
      ..writeln('  MasweWeakness(')
      ..writeln("    id: '${_esc(w.id)}',")
      ..writeln("    title: '${_esc(w.title)}',")
      ..writeln("    category: '${_esc(w.category)}',")
      ..writeln(
        '    platforms: [${w.platforms.map((p) => "'${_esc(p)}'").join(', ')}],',
      )
      ..writeln('    cweIds: [${w.cwe.join(', ')}],');
    if (w.description.isNotEmpty) {
      b.writeln("    description: '${_esc(w.description)}',");
    }
    b.writeln('  ),');
  }
  b
    ..writeln('];')
    ..writeln()
    ..writeln('/// Oude beta-id\'s (MASWE v0.x, tot 0119) naar de canonieke')
    ..writeln('/// zwakheid die ze heeft opgeslokt. De gebundelde MASTG v2.0.0')
    ..writeln('/// verwijst nog naar de beta-nummering; deze brug houdt die')
    ..writeln('/// kruiskoppeling heel zonder de MASTG-data te vervalsen.')
    ..writeln('const Map<String, String> _betaAliases = {');
  for (final a in aliases) {
    b.writeln("  '${_esc(a.key)}': '${_esc(a.value)}',");
  }
  b.writeln('};');
  return b.toString();
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
