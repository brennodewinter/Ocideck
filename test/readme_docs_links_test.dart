import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

/// Guards that every current-state document under `docs/` also has a **direct
/// link in `README.md`**. The sibling `docs_registration_test.dart` keeps those
/// same docs reachable *inside the app* (bundled asset + reader tile); this test
/// keeps them reachable from the *front page* of the repository.
///
/// The two guards close two different gaps. The app-reader guard means a new doc
/// always ships to users; without this README guard, that same new doc can still
/// be invisible to anyone reading the repo — reachable only by digging into the
/// `docs/README.md` index. #843 linked the eight docs that had drifted into
/// exactly that state; this test stops the drift from recurring.
///
/// The asymmetry with design docs is deliberate and mirrors the README's own
/// policy: general docs (`docs/*.md`) get a direct link, while design docs
/// (`docs/design/**`) are reached through the design-notes index in
/// `docs/README.md` rather than listed one by one on the front page. So this
/// test requires a direct link for general docs, and for design docs only that
/// the index pointer still exists.
void main() {
  final languageCodes = AppLocalizations.languageNames.keys.toSet();

  // `NAME.<lang>.md` variants are alternative translations of an existing base
  // document, picked up automatically by DocumentationService — they are not
  // separate documents and must not each demand their own README link.
  bool isTranslatedVariant(String path) {
    final name = path.split('/').last;
    final parts = name.split('.');
    return parts.length >= 3 &&
        parts[parts.length - 1] == 'md' &&
        languageCodes.contains(parts[parts.length - 2]);
  }

  List<String> markdownIn(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .where((p) => p.endsWith('.md') && !isTranslatedVariant(p))
        .toList()
      ..sort();
  }

  final readme = File('README.md').readAsStringSync();

  // A direct link is a Markdown link whose href is that doc, with or without a
  // `#section` anchor: `](docs/NAME.md)` or `](docs/NAME.md#anchor)`. The link
  // text is irrelevant — `[Privacy](docs/PRIVACY.md)` and
  // `[`docs/PRIVACY.md`](docs/PRIVACY.md)` both count.
  bool linkedInReadme(String path) {
    return RegExp('\\]\\(${RegExp.escape(path)}(#[^)]*)?\\)').hasMatch(readme);
  }

  test('every general doc in docs/ has a direct link in README.md', () {
    final docs = markdownIn('docs');
    expect(docs, isNotEmpty, reason: 'No general docs found — broken scan.');
    final missing = docs.where((p) => !linkedInReadme(p)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          'These docs/ files are not directly linked from README.md. Add each '
          'to the documentation table under `## Documentation` (linking it '
          'anywhere in README.md also satisfies this guard): $missing',
    );
  });

  test(
    'README.md keeps the design-notes index pointer that reaches design docs',
    () {
      // Design docs are reached through this index rather than one-by-one links
      // on the front page, so the front page must at least point at the index.
      expect(
        linkedInReadme('docs/README.md'),
        isTrue,
        reason:
            'README.md no longer links docs/README.md — the design documents '
            '(docs/design/**) are reached through that index, so without this '
            'pointer they become unreachable from the front page.',
      );
    },
  );
}
