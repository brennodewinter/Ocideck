// Generates machine-translated `.<lang>.md` variants of the bundled, user-facing
// documentation for the languages OciDeck ships docs in (#1181).
//
// OciDeck's rule is "content is Dutch + English, the interface is every
// language": the docs are authored in English and shipped in Dutch, and a reader
// in any other interface language gets the English base with a "you are reading
// the source" notice. So this tool targets a short, explicit set
// ([shippedDocLanguages]), not all 31 languages. The app resolves
// `docs/NAME.<lang>.md` when it is bundled and falls back to the English base
// otherwise (see [DocumentationService]).
//
// It does NOT ship a translation engine of its own — OciDeck is local-first and
// network-free at runtime, so translation is a build-time step with a *pluggable*
// engine you point at from the command line. The generated files are committed
// artefacts, like the l10n overlays.
//
//   dart run tool/translate_docs.dart --translator 'my-translator'   # generate
//   dart run tool/translate_docs.dart --stub                         # identity, for tests/dry-runs
//   dart run tool/translate_docs.dart --check                        # verify shipped variants are consistent + registered
//
// The `--translator` command is run once per (document, language). The English
// Markdown is written to its stdin; its stdout is taken as the translation. The
// target language code is passed both as its first argument and as the
// `OCIDECK_TARGET_LANG` environment variable, so a translator can key on either.
//
// Two documents are deliberately NEVER machine-translated: PRIVACY.md and
// SECURITY_DESIGN.md. They make legal and security promises where a mistranslated
// sentence is a mistranslated promise; those stay English-only until a human
// translates them. See [excludedDocs].
//
// Mermaid diagrams need a HUMAN pass and are NOT rewritten here (#1278). A
// ```mermaid block travels through the translator as an ordinary code block, so —
// like every code block — the translator leaves it untouched and its label text
// stays English while the prose around it is translated. We deliberately do not
// extract-and-reinsert the labels in this tool: mermaid has a dozen node shapes
// and a different text syntax per diagram type (flowchart brackets, sequence
// `participant … as`, gantt/pie/er/state), interleaved with lines that must NOT be
// touched (`classDef`, `style`, `click`, `linkStyle`). A partial extractor would
// be exactly the fragile, half-working parser that corrupts a diagram's syntax —
// the very risk the translator sidesteps by skipping code blocks in the first
// place. So a translated diagram's labels are translated by hand (node IDs and
// syntax intact), and `tool/check_translated_mermaid.dart` is the gate that forces
// it: it fails when a variant carries a mermaid block byte-identical to the base.
//
// Each generated file is prefixed with a visible "machine translation" banner
// (itself run through the translator) so a reader is never misled into taking a
// machine rendering of a promise as authoritative — the English source wins.

import 'dart:convert';
import 'dart:io';

// Only the Flutter-free language registry — importing AppLocalizations or
// DocumentationService would drag in `package:flutter/material.dart` and
// `dart:ui`, which the standalone Dart VM this tool runs on cannot compile.
import 'package:ocideck/l10n/language_registry.dart';

/// The bundled, user-facing documents that get machine-translated. These are the
/// "Gebruiker" section of the in-app reader minus the legally sensitive ones
/// (see [excludedDocs]); the technical/developer docs stay English.
const List<String> translatableDocs = [
  'docs/USER_GUIDE.md',
  'docs/SHORTCUTS.md',
  'docs/FILE_FORMAT.md',
  'docs/README.md',
  'docs/FAQ.md',
  'docs/TROUBLESHOOTING_GUIDE.md',
  'docs/ACCESSIBILITY.md',
  'docs/KNOWN_LIMITATIONS.md',
  'docs/GLOSSARY.md',
];

/// Never machine-translated: a mistranslated promise is still a promise. These
/// stay English-only until a human translates them (#1181).
const Set<String> excludedDocs = {'docs/PRIVACY.md', 'docs/SECURITY_DESIGN.md'};

/// `(doc, lang)` pairs that have been human-reviewed and must not be overwritten
/// by the machine translator. The consistency checker ([docVariantProblems])
/// still validates them, so a reviewed variant that falls behind its source is
/// caught — only the banner and the machine rendering are skipped (#1965).
const Set<String> humanReviewedVariants = {'docs/SHORTCUTS.md:nl'};

/// The canonical banner prepended to every generated variant, before it is run
/// through the translator so the reader sees it in their own language. The
/// English source line is kept verbatim underneath so the authoritative-source
/// statement is legible even if the translation of the banner itself is poor.
const String bannerSourceLine =
    'Machine translation — the English source document is authoritative.';

/// The languages OciDeck ships translated documentation for, besides the English
/// base (`docs/NAME.md`).
///
/// OciDeck's rule is "content is Dutch + English, the interface is every
/// language": the bundled docs are authored in English and shipped in Dutch, and
/// a reader in any of the other interface languages gets the English base with a
/// "you are reading the source" notice (see `DocumentationService`). So this is a
/// short, explicit list — not every interface language. To ship one more, add its
/// code here and generate the variants with `make translate-docs`; every code
/// must be a real interface language, which [_runCheck] verifies against
/// [kLanguageNames]. The English base is implicit and never appears here.
const List<String> shippedDocLanguages = ['nl'];

/// `docs/USER_GUIDE.md` + `de` → `docs/USER_GUIDE.de.md`. Mirrors
/// `DocumentationService._variantKey` so the app resolves exactly what this writes.
String variantPath(String baseAsset, String languageCode) {
  final dot = baseAsset.lastIndexOf('.');
  return '${baseAsset.substring(0, dot)}.$languageCode${baseAsset.substring(dot)}';
}

/// Prepends the machine-translation banner to a translated body. [translatedBanner]
/// is the banner sentence in the target language (identity for `--stub`); the
/// English source line always follows so the promise is legible either way.
String withBanner(String translatedBanner, String translatedBody) {
  final b = StringBuffer()
    ..writeln('> 🤖 $translatedBanner')
    ..writeln('>')
    ..writeln('> _$bannerSourceLine _')
    ..writeln();
  return '$b${translatedBody.trimLeft()}';
}

/// Inserts `- <variant>` asset lines into [pubspec] directly after each base
/// document's asset line, preserving indentation, skipping any already present.
/// Pure and idempotent so it can be unit-tested and re-run safely.
String registerVariants(
  String pubspec,
  List<String> baseDocs,
  List<String> languages,
) {
  final lines = pubspec.split('\n');
  final out = <String>[];
  for (final line in lines) {
    out.add(line);
    final match = RegExp(r'^(\s*)-\s+(\S+\.md)\s*$').firstMatch(line);
    if (match == null) continue;
    final indent = match.group(1)!;
    final asset = match.group(2)!;
    if (!baseDocs.contains(asset)) continue;
    for (final lang in languages) {
      final variant = variantPath(asset, lang);
      final entry = '$indent- $variant';
      if (!pubspec.contains('- $variant')) out.add(entry);
    }
  }
  return out.join('\n');
}

// A returned int from `main` is ignored by the Dart VM — only `exit()` or
// `exitCode` sets the process status. This wrapper propagates `_run`'s code so
// the `--check` gate can actually fail CI (it silently exited 0 before).
Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final stub = args.contains('--stub');
  final check = args.contains('--check');
  final translator = _optionValue(args, '--translator');

  if (check) return _runCheck();

  if (!stub && translator == null) {
    stderr.writeln(
      'translate_docs: give --translator "<command>" (reads Markdown on stdin, '
      'writes the translation on stdout) or --stub for an identity dry-run.',
    );
    return 2;
  }

  final languages = shippedDocLanguages;
  Future<String> translate(String text, String lang) async =>
      stub ? text : _runTranslator(translator!, text, lang);

  var written = 0;
  for (final doc in translatableDocs) {
    if (excludedDocs.contains(doc)) continue; // belt and braces
    final base = File(doc);
    if (!base.existsSync()) {
      stderr.writeln('translate_docs: missing base document $doc');
      return 1;
    }
    final body = base.readAsStringSync();
    for (final lang in languages) {
      if (humanReviewedVariants.contains('$doc:$lang')) continue;
      final banner = await translate(bannerSourceLine, lang);
      final translated = await translate(body, lang);
      File(
        variantPath(doc, lang),
      ).writeAsStringSync(withBanner(banner.trim(), translated));
      written++;
    }
  }

  final pubspecFile = File('pubspec.yaml');
  pubspecFile.writeAsStringSync(
    registerVariants(
      pubspecFile.readAsStringSync(),
      translatableDocs,
      languages,
    ),
  );

  stdout.writeln(
    'translate_docs: wrote $written variant(s) across ${languages.length} '
    'language(s) and registered them in pubspec.yaml.'
    '${stub ? ' (--stub: identity copies, not real translations)' : ''}',
  );
  return 0;
}

/// The `docs/NAME.<lang>.md` variant languages that actually sit on disk for a
/// translatable [baseDoc] (`docs/NAME.md`), whatever their language.
List<String> _variantLangsOnDisk(String baseDoc) {
  const prefix = 'docs/';
  final name = baseDoc.substring(prefix.length, baseDoc.length - '.md'.length);
  final re = RegExp('^${RegExp.escape(name)}\\.([a-z]{2,3})\\.md\$');
  final dir = Directory(prefix);
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync())
      if (entity is File)
        if (re.firstMatch(entity.uri.pathSegments.last) case final m?)
          m.group(1)!,
  ];
}

/// One heading of a Markdown document: its level (`## ` is 2) and its text.
typedef MarkdownHeading = ({int level, String text});

/// The headings of [markdown], skipping fenced code blocks.
///
/// The fence walk is not decoration. FILE_FORMAT and the guides are full of
/// examples in which `# Title` is the *content* of a block and not a heading of
/// the document; counting those would make the structure check compare noise
/// with noise. A fence opens on three or more backticks/tildes at the start of a
/// line (up to three spaces of indent) and closes only on at least as many of
/// the same character with nothing behind them, so a ```` ``` ```` shown inside
/// a longer fence does not close the real one.
List<MarkdownHeading> markdownHeadings(String markdown) {
  final headings = <MarkdownHeading>[];
  final fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*(.*)$');
  final headingLine = RegExp(r'^ {0,3}(#{1,6})\s+(\S.*?)\s*#*\s*$');
  String? fenceChar;
  var fenceLength = 0;
  for (final line in const LineSplitter().convert(markdown)) {
    if (fenceLine.firstMatch(line) case final fence?) {
      final token = fence.group(1)!;
      if (fenceChar == null) {
        fenceChar = token[0];
        fenceLength = token.length;
      } else if (token[0] == fenceChar &&
          token.length >= fenceLength &&
          fence.group(2)!.trim().isEmpty) {
        fenceChar = null;
      }
      continue;
    }
    if (fenceChar != null) continue;
    if (headingLine.firstMatch(line) case final heading?) {
      headings.add((level: heading.group(1)!.length, text: heading.group(2)!));
    }
  }
  return headings;
}

/// The numbered section ids a document declares (`14.11`, `6.3.1`, `3.1b`).
///
/// Numbers survive translation where words do not, which is what makes them
/// usable as the identity of a section across languages. FILE_FORMAT is the
/// document that numbers its sections; for the others this is simply empty.
Set<String> markdownSectionNumbers(String markdown) {
  final numbered = RegExp(r'^([0-9]+(?:\.[0-9]+[a-z]?)*)[.)]?\s');
  return {
    for (final heading in markdownHeadings(markdown))
      if (numbered.firstMatch(heading.text) case final m?) m.group(1)!,
  };
}

/// How many headings [variant] is missing compared with [source], counted per
/// level so a translated document that merely *renames* a heading does not
/// register as drift — only a heading that is not there at all does.
int missingHeadingCount(
  List<MarkdownHeading> source,
  List<MarkdownHeading> variant,
) {
  final counts = <int, int>{};
  for (final heading in source) {
    counts[heading.level] = (counts[heading.level] ?? 0) + 1;
  }
  for (final heading in variant) {
    counts[heading.level] = (counts[heading.level] ?? 0) - 1;
  }
  return counts.values.where((n) => n > 0).fold(0, (a, b) => a + b);
}

/// Consistency problems with the shipped documentation variants (empty = OK).
///
/// The gate no longer demands a variant in every interface language — OciDeck
/// ships docs in English + Dutch (see [shippedDocLanguages]). It instead enforces
/// that what is shipped is coherent: (1) every [shippedDocLanguages] variant
/// exists and is registered; (2) no variant file sits on disk for a language we
/// do not ship; (3) no `pubspec.yaml` registration is dangling (file gone);
/// (4) no excluded document was translated. Public so a test can assert the repo
/// stays consistent.
List<String> docVariantProblems() {
  final problems = <String>[];
  final shipped = shippedDocLanguages;

  final unknown = shipped.where((c) => !kLanguageNames.containsKey(c)).toList();
  if (unknown.isNotEmpty) {
    problems.add(
      'shippedDocLanguages contains unknown language code(s): '
      '${unknown.join(', ')}',
    );
  }

  final pubspecLines = File('pubspec.yaml').readAsLinesSync();
  bool registered(String path) =>
      pubspecLines.any((l) => l.trim() == '- $path');

  for (final doc in translatableDocs) {
    // (1) every shipped variant must exist and be registered.
    for (final lang in shipped) {
      final variant = variantPath(doc, lang);
      if (!File(variant).existsSync()) {
        problems.add(
          'missing shipped variant $variant (run `make translate-docs`)',
        );
      } else if (!registered(variant)) {
        problems.add(
          'shipped variant not registered in pubspec.yaml: $variant',
        );
      }
    }
    // (2) a variant on disk for a language we do not ship is drift.
    for (final lang in _variantLangsOnDisk(doc)) {
      if (lang == kDocsBaseLanguage || shipped.contains(lang)) continue;
      problems.add(
        'untracked variant ${variantPath(doc, lang)}: add "$lang" to '
        'shippedDocLanguages or remove the file',
      );
    }
  }

  // (3) a `- docs/NAME.<lang>.md` registration whose file is gone.
  final regLine = RegExp(r'^\s*-\s+(docs/.+?)\.([a-z]{2,3})\.md\s*$');
  for (final line in pubspecLines) {
    if (regLine.firstMatch(line) case final m?) {
      final base = '${m.group(1)}.md';
      final path = '${m.group(1)}.${m.group(2)}.md';
      if (translatableDocs.contains(base) && !File(path).existsSync()) {
        problems.add('registered in pubspec.yaml but missing on disk: $path');
      }
    }
  }

  // (4) excluded documents must never carry a translation.
  for (final doc in excludedDocs) {
    for (final lang in _variantLangsOnDisk(doc)) {
      problems.add(
        'excluded document was translated (remove): ${variantPath(doc, lang)}',
      );
    }
  }

  // (5) a shipped variant must carry the same structure as its source. This is
  // the freshness half of the gate: rules (1)-(4) only ask whether a variant
  // exists, which is how §14.9 of FILE_FORMAT could be absent from the Dutch
  // file for a day with every gate green (#1568). Headings are compared per
  // level and section numbers by identity, because both survive translation
  // while the words do not.
  for (final doc in translatableDocs) {
    final source = File(doc);
    if (!source.existsSync()) continue;
    final sourceText = source.readAsStringSync();
    final sourceHeadings = markdownHeadings(sourceText);
    final sourceNumbers = markdownSectionNumbers(sourceText);
    for (final lang in shipped) {
      final variant = File(variantPath(doc, lang));
      if (!variant.existsSync()) continue; // already reported by rule (1).
      final variantText = variant.readAsStringSync();
      final missing = missingHeadingCount(
        sourceHeadings,
        markdownHeadings(variantText),
      );
      if (missing > 0) {
        problems.add(
          '${variantPath(doc, lang)} is missing $missing heading(s) that '
          '$doc has. Translate the new section into the variant in the same '
          'change — there is deliberately no baseline to raise.',
        );
      }
      final missingNumbers = (sourceNumbers.difference(
        markdownSectionNumbers(variantText),
      )).toList()..sort();
      if (missingNumbers.isNotEmpty) {
        problems.add(
          '${variantPath(doc, lang)} does not carry section number(s) '
          '${missingNumbers.join(', ')} from $doc. A section keeps its number '
          'in every language.',
        );
      }
    }
  }

  return problems;
}

/// Runs [docVariantProblems] and reports; non-zero (listing the problems) on any
/// gap so the gate actually fails — `main` propagates this exit code.
int _runCheck() {
  final problems = docVariantProblems();
  if (problems.isEmpty) {
    stdout.writeln(
      'translate_docs --check: shipped doc variants '
      '(${shippedDocLanguages.join(', ')}) are consistent and registered.',
    );
    return 0;
  }
  stderr.writeln('translate_docs --check found ${problems.length} problem(s):');
  for (final problem in problems) {
    stderr.writeln('  - $problem');
  }
  return 1;
}

Future<String> _runTranslator(String command, String text, String lang) async {
  final process = await Process.start(
    command,
    [lang],
    environment: {'OCIDECK_TARGET_LANG': lang},
    runInShell: true,
  );
  process.stdin.write(text);
  await process.stdin.close();
  final out = await process.stdout.transform(utf8.decoder).join();
  final code = await process.exitCode;
  if (code != 0) {
    final err = await process.stderr.transform(utf8.decoder).join();
    throw StateError(
      'translator "$command" failed for $lang (exit $code): $err',
    );
  }
  return out;
}

String? _optionValue(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return null;
}
