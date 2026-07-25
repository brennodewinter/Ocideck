import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

/// Sibling of `readme_docs_links_test.dart`, for the Markdown documents at the
/// **repository root** (`AUTHORS.md`, `SECURITY.md`, `SOURCE.md`, …) rather than
/// under `docs/`. Every root-level `.md` — except `README.md` itself, which is
/// the page doing the linking — must have a direct link in `README.md`, so a new
/// top-level document cannot sit in the repo invisible from its own front page.
///
/// Together the two tests keep the whole documentation surface reachable from
/// `README.md`: `docs/*.md` there, root `*.md` here. The app-reader guard
/// (`docs_registration_test`) covers only the `docs/` set, so these root files
/// have no other guard — this is their only one.
void main() {
  final languageCodes = AppLocalizations.languageNames.keys.toSet();

  // `NAME.<lang>.md` variants are alternative translations of an existing base
  // document and must not each demand their own README link.
  bool isTranslatedVariant(String name) {
    final parts = name.split('.');
    return parts.length >= 3 &&
        parts[parts.length - 1] == 'md' &&
        languageCodes.contains(parts[parts.length - 2]);
  }

  // Top-level `*.md` in the repo root, by bare filename. Not recursive: `docs/`
  // and other subdirectories are guarded elsewhere. `README.md` is excluded — it
  // is the file doing the linking, not a file that needs to be linked.
  List<String> rootMarkdown() {
    return Directory('.')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/').split('/').last)
        .where((n) => n.endsWith('.md'))
        .where((n) => n != 'README.md' && !isTranslatedVariant(n))
        .toList()
      ..sort();
  }

  final readme = File('README.md').readAsStringSync();

  // A direct link whose href is that root file, with an optional `./` prefix and
  // optional `#anchor`: `](SECURITY.md)`, `](./SOURCE.md)`,
  // `](CONTRIBUTING.md#setup)`. A `docs/`-prefixed href does not count — those
  // point at a different document, guarded by readme_docs_links_test.
  bool linkedInReadme(String name) {
    return RegExp(
      '\\]\\((\\./)?${RegExp.escape(name)}(#[^)]*)?\\)',
    ).hasMatch(readme);
  }

  test('every root-level .md has a direct link in README.md', () {
    final docs = rootMarkdown();
    expect(docs, isNotEmpty, reason: 'No root .md found — broken scan.');
    final missing = docs.where((n) => !linkedInReadme(n)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          'These root-level Markdown files are not directly linked from '
          'README.md. Add each to the documentation table under '
          '`## Documentation`, or to the section it belongs with: $missing',
    );
  });
}
