// Adds new `d('…')` source strings to every language's additions overlay in
// one go — the mechanical half of localisation that used to be hand-work.
//
// Usage:
//   dart run tool/add_l10n.dart <spec.json>
//
// Spec format:
//   {
//     "additions": {
//       "<Dutch source string>": { "en": "…", "de": "…", … all 30 non-nl … },
//       …
//     },
//     "unchanged": ["Heatmap", "Combo"]   // optional: loanwords kept identical
//   }
//
// For each addition the tool inserts the translation into every
// `_dutchSourceAdd<Lang>` map (skipping a language that already carries the key
// in either its overlay or its base map — so it never creates a duplicate), then
// runs `dart format` on the touched files so the result is always check-clean.
// Each "unchanged" term is added to the guard-test whitelists instead of being
// translated. Re-running is safe: everything already present is left untouched.
import 'dart:convert';
import 'dart:io';

// Same order/codes as _dutchSourceStrings in app_localizations.dart (nl is the
// source language and needs no translation).
const langs = [
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
];

String cap(String code) => code[0].toUpperCase() + code.substring(1);

/// A Dart single-quoted string literal for [value] (escapes `\` and `'`).
String dartStr(String value) =>
    "'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

void fail(String message) {
  stderr.writeln('add_l10n: $message');
  exit(1);
}

void main(List<String> args) {
  if (args.length != 1) {
    fail('usage: dart run tool/add_l10n.dart <spec.json>');
  }
  final specFile = File(args.single);
  if (!specFile.existsSync()) fail('spec not found: ${args.single}');
  final spec = jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;

  final additions =
      (spec['additions'] as Map?)?.cast<String, dynamic>() ?? const {};
  final unchanged = [
    for (final t in (spec['unchanged'] as List? ?? const [])) t.toString(),
  ];

  // Validate every addition covers exactly the 30 target languages up front, so
  // a gap fails here (with a clear message) rather than deep in `make check`.
  additions.forEach((source, value) {
    final t = (value as Map).cast<String, dynamic>();
    final missing = langs.where((l) => !t.containsKey(l)).toList();
    final extra = t.keys.where((k) => k != 'nl' && !langs.contains(k)).toList();
    if (missing.isNotEmpty) {
      fail('"$source" is missing translations for: ${missing.join(', ')}');
    }
    if (extra.isNotEmpty) {
      fail('"$source" has unknown language codes: ${extra.join(', ')}');
    }
  });

  final touched = <String>{};
  var inserted = 0;
  var skipped = 0;

  for (final code in langs) {
    final file = File('lib/l10n/translations/$code.dart');
    if (!file.existsSync()) fail('missing language file: ${file.path}');
    var text = file.readAsStringSync();
    final anchor = 'const _dutchSourceAdd${cap(code)} = ';
    final anchorAt = text.indexOf(anchor);
    if (anchorAt < 0) fail('no overlay map in ${file.path} (run migration?)');
    // Insertion point: just after the newline that ends the declaration line.
    final insertAt = text.indexOf('\n', anchorAt) + 1;

    final lines = <String>[];
    additions.forEach((source, value) {
      final t = (value as Map).cast<String, dynamic>();
      // Skip if this language already carries the key anywhere in the file
      // (overlay or base map) — avoids duplicate keys.
      if (text.contains('${dartStr(source)}:')) {
        skipped++;
        return;
      }
      lines.add('  ${dartStr(source)}: ${dartStr(t[code].toString())},');
      inserted++;
    });
    if (lines.isEmpty) continue;
    text =
        '${text.substring(0, insertAt)}${lines.join('\n')}\n'
        '${text.substring(insertAt)}';
    file.writeAsStringSync(text);
    touched.add(file.path);
  }

  if (unchanged.isNotEmpty) {
    _addToWhitelists(unchanged, touched);
  }

  // Guarantee format-clean output — the gate that is easy to forget by hand.
  if (touched.isNotEmpty) {
    final fmt = Process.runSync('dart', ['format', ...touched]);
    if (fmt.exitCode != 0) fail('dart format failed:\n${fmt.stderr}');
  }

  stdout.writeln(
    'add_l10n: ${additions.length} string(s) × ${langs.length} languages — '
    '$inserted inserted, $skipped already present. '
    '${unchanged.length} loanword(s) whitelisted. '
    'Touched ${touched.length} file(s).',
  );
  stdout.writeln('Run `make l10n-check` to verify.');
}

/// Add loanwords to the two guard-test whitelists so an identical-in-every-
/// language term (Heatmap, Combo, …) doesn't trip the coverage tests.
void _addToWhitelists(List<String> terms, Set<String> touched) {
  final test = File('test/app_localizations_test.dart');
  if (!test.existsSync()) fail('whitelist test not found: ${test.path}');
  final original = test.readAsStringSync();
  var text = original;
  for (final set in ['unchangedInEnglish', 'unchangedInAllLanguages']) {
    final at = text.indexOf('$set = {');
    if (at < 0) fail('whitelist set `$set` not found in ${test.path}');
    final insertAt = text.indexOf('\n', at) + 1;
    final additions = [
      for (final term in terms)
        if (!_setContains(text, at, dartStr(term))) '      ${dartStr(term)},',
    ];
    if (additions.isEmpty) continue;
    text =
        '${text.substring(0, insertAt)}${additions.join('\n')}\n'
        '${text.substring(insertAt)}';
  }
  if (text == original) return; // every loanword already whitelisted
  test.writeAsStringSync(text);
  touched.add(test.path);
}

/// Whether the `{ … }` block starting at [setAt] already lists [literal].
bool _setContains(String text, int setAt, String literal) {
  final open = text.indexOf('{', setAt);
  final close = text.indexOf('};', open);
  if (open < 0 || close < 0) return false;
  return text.substring(open, close).contains(literal);
}
