// Eén taal uit de Dart-bestanden halen en er weer in terugzetten, via een plat
// sleutel/waarde-bestand — zodat een vertaler nooit Dart hoeft te zien.
//
// Usage:
//   dart run tool/l10n_po.dart export <lang> [out.json]
//   dart run tool/l10n_po.dart import <lang> <in.json>
//
// Waarom dit bestaat: de strings wonen in 32 Dart `part`-bestanden van elk
// ~3.000 regels. Een Ierse of Maltese moedertaalspreker die één slechte zin wil
// verbeteren moest daarvoor Dart-syntaxis, een `part`-bestand en `make check`
// overleven. Die drempel duwt precies de bijdrage weg die dit project het
// hardst nodig heeft — moedertaalcontrole op 31 talen — en duwt richting
// machinevertaling (#633).
//
// Het formaat is JSON en geen PO. PO is de standaard in vertaalland, maar het
// draagt hier niets extra's: er zijn geen meervoudsvormen, geen contexten en
// geen fuzzy-vlaggen in dit corpus, en JSON is met elk gereedschap te openen
// zonder dat iemand gettext moet installeren. Wél in PO-geest: de Nederlandse
// bronstring ís de sleutel, dus een vertaler ziet altijd waar hij een vertaling
// van maakt.
//
// Wat dit gereedschap NIET doet, en met opzet:
//
//   * sleutels toevoegen of weghalen. Een `import` die een onbekende sleutel
//     tegenkomt weigert het hele bestand. Nieuwe strings horen bij de code die
//     ze introduceert en gaan via `add_l10n.dart`, dat ze in álle 31 talen
//     afdwingt. Zou import wél toevoegen, dan kon een vertaalronde stilletjes
//     een string in 30 talen laten ontbreken;
//   * de `t()`-map aanraken. Die heeft een eigen sleutelruimte — `t('slides')`
//     en `d('slides')` zijn twee verschillende dingen — en hoort bij de
//     interface-structuur, niet bij het vertaalwerk.
import 'dart:convert';
import 'dart:io';

/// Zelfde volgorde/codes als `add_l10n.dart`; `nl` is de brontaal.
const langs = [
  'en', 'it', 'de', 'fr', 'es', 'fy', 'pap', 'la', 'id', 'pl', 'uk', 'gsw',
  'el', 'da', 'sv', 'hr', 'cs', 'fi', 'bg', 'lv', 'lt', 'mt', 'et', 'hu',
  'ga', 'pt', 'ro', 'sl', 'sk', 'tlh', 'tr', //
];

String cap(String code) => code[0].toUpperCase() + code.substring(1);

Never fail(String message) {
  stderr.writeln('l10n_po: $message');
  exit(1);
}

/// Het deel van [text] waar de Nederlandse bronsleutels wonen — vanaf de
/// declaratie van `_dutchSource<Lang>`, dus de primaire map plus de overlay.
///
/// Identiek afgebakend aan `add_l10n.dart`, en om dezelfde reden: de
/// `t()`-map staat ervóór en heeft een eigen sleutelruimte.
String dutchSourceRegion(String text, String code) {
  final at = text.indexOf('const _dutchSource${cap(code)} = ');
  return at < 0 ? text : text.substring(at);
}

/// Sleutel → waarde uit een `_dutchSource…`-map.
///
/// Leest ook een paar dat `dart format` na de dubbele punt over twee regels
/// brak: de witruimte ertussen mag een regeleinde bevatten. Juist de lange
/// waarden worden gebroken, en dat zijn de zinnen waar een vertaler aan werkt.
final _pair = RegExp(
  r"^\s*'((?:[^'\\]|\\.)*)':\s*'((?:[^'\\]|\\.)*)',\s*$",
  multiLine: true,
);

String unescapeDart(String literal) => literal
    .replaceAll(r'\n', '\n')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\$', r'$')
    .replaceAll(r'\\', r'\');

/// Een Dart-literal met enkele quotes voor [value] — dezelfde regels als in
/// `add_l10n.dart`, inclusief het `$`-teken, dat anders als interpolatie leest.
String dartLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

Map<String, String> readTranslations(String path, String code) {
  final file = File(path);
  if (!file.existsSync()) fail('taalbestand niet gevonden: $path');
  final region = dutchSourceRegion(file.readAsStringSync(), code);
  return {
    for (final m in _pair.allMatches(region))
      unescapeDart(m.group(1)!): unescapeDart(m.group(2)!),
  };
}

void doExport(String code, String? out) {
  final map = readTranslations('lib/l10n/translations/$code.dart', code);
  if (map.isEmpty) fail('geen vertalingen gevonden voor $code');
  final sorted = Map.fromEntries(
    map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  final json = '${const JsonEncoder.withIndent('  ').convert(sorted)}\n';
  if (out == null) {
    stdout.write(json);
  } else {
    File(out).writeAsStringSync(json);
    stderr.writeln('l10n_po: ${sorted.length} strings → $out');
  }
}

void doImport(String code, String path) {
  final file = File(path);
  if (!file.existsSync()) fail('invoerbestand niet gevonden: $path');
  final Map<String, dynamic> incoming;
  try {
    incoming = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException catch (e) {
    fail('$path is geen geldige JSON: $e');
  }

  final target = File('lib/l10n/translations/$code.dart');
  if (!target.existsSync()) fail('taalbestand niet gevonden: ${target.path}');
  var text = target.readAsStringSync();
  final regionAt = text.length - dutchSourceRegion(text, code).length;

  final known = readTranslations(target.path, code);
  final unknown = incoming.keys.where((k) => !known.containsKey(k)).toList();
  if (unknown.isNotEmpty) {
    // Weigeren en niet negeren: een onbekende sleutel betekent bijna altijd dat
    // de vertaler op een oudere versie werkte, en dan is stilzwijgend
    // doorgaan de manier waarop zijn werk half landt.
    fail(
      '${unknown.length} onbekende sleutel(s); voeg nieuwe strings toe met '
      'add_l10n.dart, niet hiermee:\n  ${unknown.take(5).join('\n  ')}',
    );
  }

  var changed = 0;
  final region = text.substring(regionAt);
  final updated = region.replaceAllMapped(_pair, (m) {
    final key = unescapeDart(m.group(1)!);
    final value = incoming[key];
    if (value == null || value is! String) return m.group(0)!;
    if (value == unescapeDart(m.group(2)!)) return m.group(0)!;
    changed++;
    final indent = RegExp(r'^\s*').firstMatch(m.group(0)!)!.group(0)!;
    return "$indent'${m.group(1)}': ${dartLiteral(value)},";
  });
  text = text.substring(0, regionAt) + updated;
  target.writeAsStringSync(text);
  stderr.writeln('l10n_po: $changed string(s) bijgewerkt in ${target.path}');
  if (changed > 0) {
    Process.runSync('dart', ['format', target.path]);
  }
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/l10n_po.dart export <lang> [out.json]\n'
      '       dart run tool/l10n_po.dart import <lang> <in.json>',
    );
    exit(64);
  }
  final code = args[1];
  if (!langs.contains(code)) {
    fail('onbekende taal "$code"; kies uit: ${langs.join(', ')}');
  }
  switch (args.first) {
    case 'export':
      doExport(code, args.length > 2 ? args[2] : null);
    case 'import':
      if (args.length < 3) fail('import vraagt een invoerbestand');
      doImport(code, args[2]);
    default:
      fail('onbekend commando "${args.first}"; kies export of import');
  }
}
