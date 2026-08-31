// Guards that a deck template in `assets/templates/` does not carry English
// text where its own language is expected.
//
// ── The gap this closes ─────────────────────────────────────────────────────
//
// A template is a Markdown document per language (`<id>.<lang>.md`, see
// `TemplateContentService`). The translation round trip runs through
// `tool/template_l10n_po.dart`, and that tool only peels out five things:
// `title:`, `# `, `## `, bullets and table rows. Everything else travels along
// as a `raw` segment — numbered lists, block quotes, `###` headings, plain
// paragraphs, and the bodies of fenced blocks. Whatever the English base said,
// the translation kept saying.
//
// That was not theory. Before this gate landed, 47 raw lines in twelve
// templates stood in English in 27 languages each, and nine templates carried
// English answers, chart series and meter labels inside their ```question,
// ```chart and ```cockpit blocks. The three l10n gates never saw it: they watch
// `lib/l10n/translations/`, not `assets/`.
//
// ── What is compared, and why Dutch is the yardstick ────────────────────────
//
// Per line, not per segment — a raw line is exactly what the exporter does not
// know about, so a segment-shaped check would look right past it.
//
// A line counts as untranslated when it stands verbatim in the English base AND
// does *not* stand verbatim in the Dutch one. That second half is what keeps
// this gate honest. Dutch is the source language of the content, so a line that
// is the same in Dutch is the authored form, not a translation gap: the SIPOC
// table head (`| Supplier | Input | Process | Output | Customer |`, which spells
// the acronym), `Destination METAR/TAF`, `ATIS / QNH`, `Sterile cockpit`,
// `Check-out`, the language-neutral mermaid diagram in `technical`, and
// `**Scope object:**` — which `FindingSpec` parses as a key and must stay put.
// Comparing against English alone would flag all of those and the gate would be
// noise; comparing against Dutch as well means the whole class is silent
// without a single exception entry.
//
// ── Why two words ───────────────────────────────────────────────────────────
//
// Same reasoning as the sister gates on the translation tables: a single word
// is identical across languages far too often to carry evidence (`Status`,
// `Design`, `Budget`, `Sprint`). Two words of three or more Latin letters is
// where a line starts to say something, and the exceptions below stay countable.
// Measured on the tree of this change: threshold 1 finds 340 lines and is wrong
// about most of them; threshold 2 finds the 4 in [allowedCognates].
//
// ── Klingon ─────────────────────────────────────────────────────────────────
//
// `tlh` is skipped. `TemplateContentService.languagesWithContent` deliberately
// leaves Klingon on the English fallback until its template corpus has had a
// reliable human translation, and the four `.tlh.md` files that do exist are
// English copies. Including it would mean a permanently red gate for a decision
// that was made on purpose.
//
// Usage:
//   dart run tool/check_untranslated_templates.dart          # the gate
//   dart run tool/check_untranslated_templates.dart --list   # every hit
//
// Deliberately dependency-free, like the other static gates: it imports only
// `dart:io` so `dart run` never has to compile the app package.

import 'dart:io';

/// The directory holding one Markdown document per template and language.
const String templatesDir = 'assets/templates';

/// The language the content is authored in. A line that is identical here is
/// the authored form, not an untranslated one.
const String sourceLanguage = 'nl';

/// The language the translator translates *from*.
const String baseLanguage = 'en';

/// Languages that do not ship translated template content.
///
/// See the header: Klingon is on the English fallback by design.
const Set<String> skippedLanguages = {'tlh'};

/// From how many words an identical line counts as untranslated.
const int minimumWords = 2;

/// How many untranslated lines still stand. RATCHET: may fall, never rise.
const int untranslatedBaseline = 0;

/// Lines that are allowed to be identical to English in one specific language,
/// because the English words *are* that language's words.
///
/// Keyed on (language, line), like `test/l10n_untranslated_test.dart` and unlike
/// the block-keyed whitelist in `tool/check_translated_mermaid.dart`. The reason
/// is the same one that test gives: a Danish `Standard:` says nothing about
/// Greek, where an English line would be a real miss. A per-line exemption would
/// silence every language at once and hide the next gap.
///
/// The bar is strict: the line must contain no ordinary word that this language
/// says differently. "It was hard to translate" is not a reason — translate it.
const Set<(String, String)> allowedCognates = {
  // `Standard` is the word in each of these languages (Dutch says `Norm`, which
  // is why the line differs from the source and lands here at all). What follows
  // it is two standard names.
  ('da', '- Standard: ISO 27001 / NIS2 / …'),
  ('de', '- Standard: ISO 27001 / NIS2 / …'),
  ('et', '- Standard: ISO 27001 / NIS2 / …'),
  ('gsw', '- Standard: ISO 27001 / NIS2 / …'),
  ('hr', '- Standard: ISO 27001 / NIS2 / …'),
  ('mt', '- Standard: ISO 27001 / NIS2 / …'),
  ('pap', '- Standard: ISO 27001 / NIS2 / …'),
  ('ro', '- Standard: ISO 27001 / NIS2 / …'),
  ('sl', '- Standard: ISO 27001 / NIS2 / …'),
  ('sv', '- Standard: ISO 27001 / NIS2 / …'),
  // Swedish writes exactly this: `total` and `budget` are both Swedish words.
  ('sv', '| Total budget | … | … | … |'),
  // A chart series name inside a ```chart block. `Budget` is the word in each
  // of these languages (Dutch says `Begroting`); `Incidents` is French.
  ('da', '      "name": "Budget",'),
  ('de', '      "name": "Budget",'),
  ('fr', '      "name": "Budget",'),
  ('gsw', '      "name": "Budget",'),
  ('it', '      "name": "Budget",'),
  ('sv', '      "name": "Budget",'),
  ('fr', '      "name": "Incidents",'),
};

/// One line of a translated template that stayed English.
class UntranslatedLine {
  const UntranslatedLine({
    required this.template,
    required this.language,
    required this.line,
  });

  /// The template id (`pitch`, `miauwReport`, …).
  final String template;

  /// The language whose document carries the English line.
  final String language;

  /// The line itself, trimmed of trailing whitespace.
  final String line;

  /// The path a reader should open to fix it.
  String get path => '$templatesDir/$template.$language.md';
}

/// The lines of [markdown] that a reader sees, keyed for comparison.
///
/// Front matter is dropped except `title:` — the rest (`marp: true`,
/// `theme: ocideck`) is machine configuration and identical by definition.
Set<String> comparableLines(String markdown) {
  final lines = markdown.split('\n');
  var index = 0;
  final result = <String>{};
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    index = 1;
    while (index < lines.length && lines[index].trim() != '---') {
      final line = lines[index];
      if (line.startsWith('title:')) result.add(line.trimRight());
      index++;
    }
    index++;
  }
  for (; index < lines.length; index++) {
    final line = lines[index].trimRight();
    if (line.trim().isEmpty) continue;
    result.add(line);
  }
  return result;
}

/// Whether [line] carries enough words to make identity meaningful.
///
/// De `title:`-sleutel telt niet mee. Hij staat er in elke taal, dus zonder deze
/// aftrek haalt een titel van één woord de drempel op zijn eigen sleutelnaam —
/// en dan meldt de poort het Italiaanse `title: Report` wel en de kop
/// `# Report` eronder niet. Dezelfde waarde, twee uitkomsten: dat is geen
/// drempel maar toeval.
bool carriesWords(String line) {
  final value = line.startsWith('title:') ? line.substring(6) : line;
  return RegExp(r'[A-Za-z]{3,}').allMatches(value).length >= minimumWords;
}

/// Every template id that has both a base and a source document on disk.
List<String> templateIds(String root) {
  final dir = Directory('$root/$templatesDir');
  if (!dir.existsSync()) return const [];
  final ids = <String>{};
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('.$baseLanguage.md')) continue;
    ids.add(name.substring(0, name.length - '.$baseLanguage.md'.length));
  }
  final sorted = ids.toList()..sort();
  return sorted;
}

/// The languages a template ships a document in, base and source excluded.
List<String> translatedLanguages(String root, String id) {
  final dir = Directory('$root/$templatesDir');
  final languages = <String>{};
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.startsWith('$id.') || !name.endsWith('.md')) continue;
    final middle = name.substring(id.length + 1, name.length - 3);
    if (middle.contains('.')) continue; // a different template with a longer id
    if (middle == baseLanguage || middle == sourceLanguage) continue;
    if (skippedLanguages.contains(middle)) continue;
    languages.add(middle);
  }
  final sorted = languages.toList()..sort();
  return sorted;
}

/// Every line that stayed English, over all templates under [root].
List<UntranslatedLine> findUntranslated(String root) {
  final hits = <UntranslatedLine>[];
  for (final id in templateIds(root)) {
    final baseFile = File('$root/$templatesDir/$id.$baseLanguage.md');
    final sourceFile = File('$root/$templatesDir/$id.$sourceLanguage.md');
    if (!sourceFile.existsSync()) continue;
    final english = comparableLines(baseFile.readAsStringSync());
    final dutch = comparableLines(sourceFile.readAsStringSync());
    final suspect = english.difference(dutch).where(carriesWords).toSet();
    if (suspect.isEmpty) continue;
    for (final language in translatedLanguages(root, id)) {
      final file = File('$root/$templatesDir/$id.$language.md');
      for (final line in comparableLines(file.readAsStringSync())) {
        if (!suspect.contains(line)) continue;
        if (allowedCognates.contains((language, line))) continue;
        hits.add(
          UntranslatedLine(template: id, language: language, line: line),
        );
      }
    }
  }
  hits.sort((a, b) {
    final byTemplate = a.template.compareTo(b.template);
    if (byTemplate != 0) return byTemplate;
    final byLanguage = a.language.compareTo(b.language);
    if (byLanguage != 0) return byLanguage;
    return a.line.compareTo(b.line);
  });
  return hits;
}

void main(List<String> args) {
  final hits = findUntranslated('.');

  if (args.contains('--list')) {
    for (final hit in hits) {
      stdout.writeln('${hit.path}: ${hit.line}');
    }
    stdout.writeln('${hits.length} line(s).');
    return;
  }

  if (hits.length <= untranslatedBaseline) {
    stdout.writeln(
      'check-untranslated-templates: OK — ${hits.length} English line(s) in a '
      'translated template, baseline $untranslatedBaseline.',
    );
    return;
  }

  stderr.writeln(
    'check-untranslated-templates: ${hits.length} English line(s) in a '
    'translated template, baseline $untranslatedBaseline.',
  );
  for (final hit in hits.take(20)) {
    stderr.writeln('  ${hit.path}: ${hit.line}');
  }
  if (hits.length > 20) {
    stderr.writeln('  … and ${hits.length - 20} more (--list shows them all).');
  }
  stderr
    ..writeln('')
    ..writeln(
      'These lines stand in the English base and not in the Dutch source, so '
      'they are a translation gap, not an authored form. Most of them are the '
      'lines tool/template_l10n_po.dart carries as `raw`: numbered lists, '
      'quotes, ### headings, paragraphs and fenced blocks. Translate them in '
      'place, or — if the English words genuinely are that language\'s words — '
      'add the (language, line) pair to allowedCognates in '
      'tool/check_untranslated_templates.dart with the reason.',
    );
  exit(1);
}
