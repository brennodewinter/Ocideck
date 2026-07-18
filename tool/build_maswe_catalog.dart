// Genereert de offline MASWE-zwakhedenlijst uit een uitgepakte
// OWASP/maswe-checkout, naast tool/build_mastg_catalog.dart.
//
// Invoer: de repo van github.com/OWASP/maswe, uitgepakt.
//   curl -sL https://github.com/OWASP/maswe/archive/<sha>.tar.gz | tar xz
// dan:
//   dart run tool/build_maswe_catalog.dart maswe-<sha> 2026-06-12
//
// De tweede parameter is een **datum**, geen versienummer, en dat is geen
// slordigheid: MASWE heeft geen releases en geen tags. Er is alleen een
// doorlopende branch, dus het enige eerlijke antwoord op "welke versie heb je
// gebruikt" is de dag waarop je hem hebt overgenomen. De verouderingspoort
// vergelijkt daarom met de datum van de laatste commit.
//
// Anders dan de MASTG-generator worden placeholders hier **wél** meegenomen.
// Dat verschil is opzettelijk. Een MASTG-placeholder belooft een test die
// niemand kan uitvoeren — die in een klantchecklist zetten is misleidend. Een
// MASWE-placeholder is een zwakheid die OWASP heeft geïdentificeerd, met id,
// titel, CWE-koppeling en een conceptomschrijving; alleen de toelichting is nog
// niet geschreven. Ernaar verwijzen in een bevinding is gewoon juist. Ze worden
// wel gemarkeerd, zodat een aanroeper kan tonen dat de uitleg dun is.
//
// Wat er níét in gaat: `status: deprecated`. Een ingetrokken zwakheid citeren
// zou een bevinding aan iets hangen dat de bron zelf heeft teruggetrokken.
import 'dart:io';

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
  var deprecated = 0;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    if (entity.uri.pathSegments.last == 'index.md') continue;
    final w = _parse(entity, dir.path);
    if (w == null) {
      deprecated++;
      continue;
    }
    out.add(w);
  }
  if (out.isEmpty) {
    stderr.writeln('build_maswe_catalog: niets gevonden — opzet gewijzigd?');
    exit(1);
  }
  out.sort((a, b) => a.id.compareTo(b.id));

  // Gesplitst op uitgeschreven versus concept. Niet omdat 117 in één bestand
  // over de regelratchet gaat — al is dat zo — maar omdat dat precies het
  // onderscheid is dat de catalogus zelf maakt: wie alleen afgeronde zwakheden
  // wil, leest één lijst.
  final written = out.where((w) => !w.placeholder).toList();
  final draft = out.where((w) => w.placeholder).toList();
  File('lib/services/maswe_catalog_written.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(_render(written, 'written', 'uitgeschreven'));
  File('lib/services/maswe_catalog_draft.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(_render(draft, 'draft', 'nog niet uitgeschreven'));

  final placeholders = draft.length;
  stdout
    ..writeln('maswe_catalog_{written,draft}.dart: ${out.length} zwakheden')
    ..writeln('  waarvan nog niet uitgeschreven: $placeholders')
    ..writeln('  overgeslagen (ingetrokken): $deprecated')
    ..writeln(
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
    this.placeholder,
    this.description,
  );
  final String id, title, category, description;
  final List<String> platforms;
  final List<int> cwe;
  final bool placeholder;
}

/// Null voor een ingetrokken zwakheid of een bestand zonder front matter.
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

  final status = field('status');
  if (status == 'deprecated') return null;

  final id = field('id');
  final title = field('title');
  if (id.isEmpty || title.isEmpty) return null;

  // weaknesses/<MASVS-CATEGORIE>/<id>.md
  final rel = file.path
      .substring(root.length + 1)
      .split(Platform.pathSeparator);
  final category = rel.length >= 2 ? rel[0] : '';

  final cwe = <int>[];
  final cweLine = RegExp(
    r'^\s+cwe:\s*\[([^\]]*)\]',
    multiLine: true,
  ).firstMatch(front);
  if (cweLine != null) {
    for (final part in cweLine.group(1)!.split(',')) {
      final n = int.tryParse(part.trim());
      if (n != null) cwe.add(n);
    }
  }

  // Bij een placeholder staat de omschrijving onder `draft:`; die is beter dan
  // niets tonen, en het is wat OWASP zelf als samenvatting heeft opgeschreven.
  final desc =
      RegExp(
        r'^\s+description:\s*(.+?)(?=\n\s*\w+:|\n\s*-|\Z)',
        multiLine: true,
        dotAll: true,
      ).firstMatch(front)?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ??
      '';

  return _W(
    id,
    title,
    category,
    _list(field('platform')),
    cwe,
    status == 'placeholder',
    desc,
  );
}

/// `["android", "ios"]` → `[android, ios]`.
List<String> _list(String raw) => raw
    .replaceAll(RegExp(r'[\[\]"]'), '')
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

String _render(List<_W> ws, String name, String omschrijving) {
  final b = StringBuffer()
    ..writeln('// GEGENEREERD door tool/build_maswe_catalog.dart — niet met de')
    ..writeln('// hand bijwerken. Zie dat bestand voor de bron en de regels.')
    ..writeln('//')
    ..writeln('// OWASP MASWE, © de OWASP Foundation, CC-BY-SA-4.0.')
    ..writeln("part of 'maswe_catalog.dart';")
    ..writeln()
    ..writeln('/// De MASWE-zwakheden die $omschrijving zijn (${ws.length}).')
    ..writeln('const List<MasweWeakness> _${name}Weaknesses = [');
  for (final w in ws) {
    b
      ..writeln('  MasweWeakness(')
      ..writeln("    id: '${_esc(w.id)}',")
      ..writeln("    title: '${_esc(w.title)}',")
      ..writeln("    category: '${_esc(w.category)}',")
      ..writeln(
        '    platforms: [${w.platforms.map((p) => "'${_esc(p)}'").join(', ')}],',
      )
      ..writeln('    cweIds: [${w.cwe.join(', ')}],')
      ..writeln('    isPlaceholder: ${w.placeholder},');
    if (w.description.isNotEmpty) {
      b.writeln("    description: '${_esc(w.description)}',");
    }
    b.writeln('  ),');
  }
  b.writeln('];');
  return b.toString();
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
