// Export/import-rondje voor deck-template-content.
//
// Usage:
//   dart run tool/template_l10n_po.dart export <id> [out.json]
//   dart run tool/template_l10n_po.dart import <id> <taal> <in.json>
//   dart run tool/template_l10n_po.dart skeleton <id> <taal>
//
// Waarom dit bestaat: `assets/templates/<id>.<taal>.md` is gewone Markdown/Marp.
// Een vertaler hoeft die structuur niet aan te raken — deze tool pelt de
// vertaalbare tekst eruit in plat JSON en plakt de vertaling weer terug.
// `skeleton` maakt snel een identieke kopie met alleen `language:` aangepast.
//
// ponytail: de parser is lijngebaseerd en herkent geen ingebedde HTML of
// geneste tabellen; HTML-blokken en `<div>...</div>`-rijen worden 1-op-1
// overgenomen. Wil je die vertalen, bewerk dan het bron-`.md` handmatig.
import 'dart:convert';
import 'dart:io';

const supportedLangs = [
  'nl',
  'en',
  'it',
  'de',
  'fr',
  'es',
  'fy',
  'pap',
  'la',
  'id',
  'pl',
  'uk',
  'gsw',
  'el',
  'da',
  'sv',
  'hr',
  'cs',
  'fi',
  'bg',
  'lv',
  'lt',
  'mt',
  'et',
  'hu',
  'ga',
  'pt',
  'ro',
  'sl',
  'sk',
  'tlh',
  'tr',
];

Never fail(String message) {
  stderr.writeln('template_l10n_po: $message');
  exit(1);
}

class Segment {
  final String type;
  final String? raw;
  final String? text;
  final String? key;
  final String? bulletMarker;
  final List<String>? cells;
  final List<String>? cellKeys;

  Segment._({
    required this.type,
    this.raw,
    this.text,
    this.key,
    this.bulletMarker,
    this.cells,
    this.cellKeys,
  });

  factory Segment.rawLine(String value) => Segment._(type: 'raw', raw: value);

  factory Segment.htmlComment(String value) =>
      Segment._(type: 'htmlComment', raw: value);

  factory Segment.slideSeparator() =>
      Segment._(type: 'slideSeparator', raw: '---');

  factory Segment.tableDelimiter(String value) =>
      Segment._(type: 'tableDelimiter', raw: value);

  factory Segment.h1(String text, String key) =>
      Segment._(type: 'h1', text: text, key: key);

  factory Segment.h2(String text, String key) =>
      Segment._(type: 'h2', text: text, key: key);

  factory Segment.bullet(String text, String marker, String key) =>
      Segment._(type: 'bullet', text: text, bulletMarker: marker, key: key);

  factory Segment.tableRow(List<String> cells, List<String> cellKeys) =>
      Segment._(type: 'tableRow', cells: cells, cellKeys: cellKeys);
}

class Template {
  final Map<String, String> frontMatter;
  final List<Segment> segments;

  Template(this.frontMatter, this.segments);

  String toMarkdown(String language, Map<String, String> translations) {
    final buf = StringBuffer();
    buf.writeln('---');
    for (final e in frontMatter.entries) {
      final key = e.key;
      String value;
      if (key == 'title') {
        value = translations['title'] ?? e.value;
      } else if (key == 'language') {
        value = language;
      } else {
        value = e.value;
      }
      buf.writeln('$key: $value');
    }
    buf.writeln('---');
    for (final s in segments) {
      switch (s.type) {
        case 'h1':
          final t = translations[s.key!] ?? s.text!;
          buf.writeln('# $t');
        case 'h2':
          final t = translations[s.key!] ?? s.text!;
          buf.writeln('## $t');
        case 'bullet':
          final t = translations[s.key!] ?? s.text!;
          buf.writeln('${s.bulletMarker}$t');
        case 'tableRow':
          final cells = <String>[];
          for (var i = 0; i < s.cells!.length; i++) {
            cells.add(translations[s.cellKeys![i]] ?? s.cells![i]);
          }
          buf.writeln('| ${cells.join(' | ')} |');
        case 'tableDelimiter':
        case 'htmlComment':
        case 'raw':
          buf.writeln(s.raw!);
        case 'slideSeparator':
          buf.writeln('---');
      }
    }
    if (!buf.toString().endsWith('\n')) {
      buf.writeln();
    }
    return buf.toString();
  }
}

bool _isTableDelimiter(String line) {
  final stripped = line.replaceAll(RegExp(r'[|\-:\s]'), '');
  return stripped.isEmpty && line.contains('-');
}

Template parseTemplate(String path) {
  final file = File(path);
  if (!file.existsSync()) fail('bronbestand niet gevonden: $path');
  final lines = file.readAsLinesSync();

  final frontMatter = <String, String>{};
  var i = 0;
  if (lines.isNotEmpty && lines[0] == '---') {
    i = 1;
    while (i < lines.length && lines[i] != '---') {
      final line = lines[i];
      final colon = line.indexOf(':');
      if (colon > 0) {
        final key = line.substring(0, colon).trim();
        final value = line.substring(colon + 1).trim();
        frontMatter[key] = value;
      }
      i++;
    }
    if (i < lines.length && lines[i] == '---') i++;
  }

  final segments = <Segment>[];
  var slide = 0;
  var h1Count = 0;
  var h2Count = 0;
  var bulletCount = 0;
  var tableRowCount = 0;

  final bulletExp = RegExp(r'^- (\[([ xX])\] )?(.*)$');

  for (; i < lines.length; i++) {
    final line = lines[i];

    if (line == '---') {
      segments.add(Segment.slideSeparator());
      slide++;
      h1Count = 0;
      h2Count = 0;
      bulletCount = 0;
      tableRowCount = 0;
      continue;
    }

    if (line.startsWith('<!--') && line.endsWith('-->')) {
      segments.add(Segment.htmlComment(line));
      continue;
    }

    if (line.startsWith('# ')) {
      final text = line.substring(2);
      final key = 's${slide}_h1_${h1Count++}';
      segments.add(Segment.h1(text, key));
      continue;
    }

    if (line.startsWith('## ')) {
      final text = line.substring(3);
      final key = 's${slide}_h2_${h2Count++}';
      segments.add(Segment.h2(text, key));
      continue;
    }

    if (line.startsWith('|') && line.endsWith('|')) {
      if (_isTableDelimiter(line)) {
        segments.add(Segment.tableDelimiter(line));
      } else {
        final trimmed = line.substring(1, line.length - 1);
        final parts = trimmed.split('|').map((s) => s.trim()).toList();
        final keys = <String>[];
        for (var c = 0; c < parts.length; c++) {
          keys.add('s${slide}_t_${tableRowCount}_$c');
        }
        tableRowCount++;
        segments.add(Segment.tableRow(parts, keys));
      }
      continue;
    }

    final bulletMatch = bulletExp.firstMatch(line);
    if (bulletMatch != null) {
      final checkbox = bulletMatch.group(2);
      final text = bulletMatch.group(3)!;
      final marker = checkbox == null ? '- ' : '- [$checkbox] ';
      final key = 's${slide}_b_${bulletCount++}';
      segments.add(Segment.bullet(text, marker, key));
      continue;
    }

    segments.add(Segment.rawLine(line));
  }

  return Template(frontMatter, segments);
}

Set<String> _collectKnownKeys(Template tmpl) {
  final known = <String>{};
  if (tmpl.frontMatter.containsKey('title')) known.add('title');
  for (final s in tmpl.segments) {
    if (s.key != null) known.add(s.key!);
    if (s.cellKeys != null) known.addAll(s.cellKeys!);
  }
  return known;
}

Map<String, String> _extractTranslations(Template tmpl) {
  final map = <String, String>{};
  if (tmpl.frontMatter.containsKey('title')) {
    map['title'] = tmpl.frontMatter['title']!;
  }
  for (final s in tmpl.segments) {
    switch (s.type) {
      case 'h1':
      case 'h2':
      case 'bullet':
        map[s.key!] = s.text!;
      case 'tableRow':
        for (var i = 0; i < s.cells!.length; i++) {
          map[s.cellKeys![i]] = s.cells![i];
        }
    }
  }
  return map;
}

void doExport(String id, String? out) {
  final tmpl = parseTemplate('assets/templates/$id.en.md');
  final map = _extractTranslations(tmpl);
  if (map.isEmpty) fail('geen vertaalbare strings gevonden in $id');
  final sorted = Map<String, String>.from(
    Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  );
  final json = '${const JsonEncoder.withIndent('  ').convert(sorted)}\n';
  if (out == null) {
    stdout.write(json);
  } else {
    File(out).writeAsStringSync(json);
    stderr.writeln('template_l10n_po: ${sorted.length} strings → $out');
  }
}

void doImport(String id, String lang, String inPath) {
  if (!supportedLangs.contains(lang)) {
    fail('onbekende taal "$lang"');
  }
  final file = File(inPath);
  if (!file.existsSync()) fail('invoerbestand niet gevonden: $inPath');
  final Map<String, dynamic> incoming;
  try {
    incoming = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException catch (e) {
    fail('$inPath is geen geldige JSON: $e');
  }

  final tmpl = parseTemplate('assets/templates/$id.en.md');
  final known = _collectKnownKeys(tmpl);
  final unknown = incoming.keys.where((k) => !known.contains(k)).toList();
  if (unknown.isNotEmpty) {
    fail(
      '${unknown.length} onbekende sleutel(s); sleutels moeten passen bij '
      'de huidige Engelse bron:\n  ${unknown.take(5).join('\n  ')}',
    );
  }

  final translations = <String, String>{};
  for (final e in incoming.entries) {
    if (e.value is! String) {
      fail('sleutel "${e.key}" heeft geen string-waarde');
    }
    translations[e.key] = e.value as String;
  }

  final out = tmpl.toMarkdown(lang, translations);
  final outFile = File('assets/templates/$id.$lang.md');
  outFile.writeAsStringSync(out);
  stderr.writeln('template_l10n_po: ${outFile.path}');
}

void doSkeleton(String id, String lang) {
  if (!supportedLangs.contains(lang)) {
    fail('onbekende taal "$lang"');
  }
  final tmpl = parseTemplate('assets/templates/$id.en.md');
  final out = tmpl.toMarkdown(lang, <String, String>{});
  final outFile = File('assets/templates/$id.$lang.md');
  outFile.writeAsStringSync(out);
  stderr.writeln('template_l10n_po: ${outFile.path}');
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/template_l10n_po.dart export <id> [out.json]\n'
      '       dart run tool/template_l10n_po.dart import <id> <taal> <in.json>\n'
      '       dart run tool/template_l10n_po.dart skeleton <id> <taal>',
    );
    exit(64);
  }
  final cmd = args[0];
  switch (cmd) {
    case 'export':
      if (args.length < 2) fail('export vraagt <id>');
      doExport(args[1], args.length > 2 ? args[2] : null);
    case 'import':
      if (args.length < 4) fail('import vraagt <id> <taal> <in.json>');
      doImport(args[1], args[2], args[3]);
    case 'skeleton':
      if (args.length < 3) fail('skeleton vraagt <id> <taal>');
      doSkeleton(args[1], args[2]);
    default:
      fail('onbekend commando "$cmd"');
  }
}
