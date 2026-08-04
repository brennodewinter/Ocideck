// Generates machine-translated `.<lang>.md` variants of the bundled, user-facing
// documentation, so a reader whose interface is not English gets the manual in
// their own language instead of the English base (#1181).
//
// The app already resolves `docs/NAME.<lang>.md` when it is bundled and falls
// back to the English base otherwise (see [DocumentationService]); this tool
// produces those variants. It does NOT ship a translation engine of its own —
// OciDeck is local-first and network-free at runtime, so translation is a
// build-time step with a *pluggable* engine you point at from the command line.
// The generated files are committed artefacts, like the l10n overlays.
//
//   dart run tool/translate_docs.dart --translator 'my-translator'   # generate
//   dart run tool/translate_docs.dart --stub                         # identity, for tests/dry-runs
//   dart run tool/translate_docs.dart --check                        # verify variants exist + are registered
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
// Each generated file is prefixed with a visible "machine translation" banner
// (itself run through the translator) so a reader is never misled into taking a
// machine rendering of a promise as authoritative — the English source wins.

import 'dart:convert';
import 'dart:io';

import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/documentation_service.dart';

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

/// The canonical banner prepended to every generated variant, before it is run
/// through the translator so the reader sees it in their own language. The
/// English source line is kept verbatim underneath so the authoritative-source
/// statement is legible even if the translation of the banner itself is poor.
const String bannerSourceLine =
    'Machine translation — the English source document is authoritative.';

/// The target language codes: every app language except the English base and —
/// defensively — any code that is not a plain language (none today). Read from
/// [AppLocalizations] so a new app language is picked up automatically, per the
/// project's "don't hardcode the language list" rule.
List<String> targetLanguages() => AppLocalizations.languageNames.keys
    .where((c) => c != DocumentationService.baseLanguage)
    .toList();

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

Future<int> main(List<String> args) async {
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

  final languages = targetLanguages();
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

/// Verifies every expected variant exists and is registered, and that no
/// excluded document was translated. Returns a non-zero code listing gaps.
int _runCheck() {
  final languages = targetLanguages();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final missingFiles = <String>[];
  final missingPubspec = <String>[];
  for (final doc in translatableDocs) {
    for (final lang in languages) {
      final variant = variantPath(doc, lang);
      if (!File(variant).existsSync()) missingFiles.add(variant);
      if (!pubspec.contains('- $variant')) missingPubspec.add(variant);
    }
  }
  final leakedExcluded = [
    for (final doc in excludedDocs)
      for (final lang in languages)
        if (File(variantPath(doc, lang)).existsSync()) variantPath(doc, lang),
  ];
  if (missingFiles.isEmpty &&
      missingPubspec.isEmpty &&
      leakedExcluded.isEmpty) {
    stdout.writeln(
      'translate_docs --check: all variants present and registered.',
    );
    return 0;
  }
  if (missingFiles.isNotEmpty) {
    stderr.writeln(
      'Missing variant files (${missingFiles.length}); run '
      'translate_docs with a --translator. e.g. ${missingFiles.first}',
    );
  }
  if (missingPubspec.isNotEmpty) {
    stderr.writeln(
      'Variants not registered in pubspec.yaml '
      '(${missingPubspec.length}).',
    );
  }
  if (leakedExcluded.isNotEmpty) {
    stderr.writeln(
      'Excluded documents were translated (remove): '
      '${leakedExcluded.join(', ')}',
    );
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
