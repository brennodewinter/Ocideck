import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/finding_spec.dart';

/// A finding's section headings live a double life: the **anchor** written to
/// disk is stable English so the Markdown round-trip does not depend on the
/// reading language (PENTEST_MIAUW §3.1), while the **displayed** heading is
/// resolved into the report's language (§12.3).
///
/// Two invariants make that safe, and both are load-bearing rather than tidy:
///
/// 1. Every anchor has a Dutch source string, or a section silently renders in
///    English forever while the rest of the report is translated.
/// 2. Each source's **English** translation is byte-identical to its anchor. The
///    whole fallback rests on this: a deck with no recorded language resolves
///    through `en` and must land back on the exact anchor, so an unrecorded
///    language renders precisely what the file already said.
void main() {
  test('every section anchor has a Dutch source string', () {
    const anchors = [
      FindingSpec.sectionDescription,
      FindingSpec.sectionConfirmation,
      FindingSpec.sectionImpact,
      FindingSpec.sectionRecommendation,
    ];

    expect(
      FindingSpec.sectionSources.keys.toSet(),
      equals(anchors.toSet()),
      reason:
          'FindingSpec.sectionSources must cover exactly the section anchors. '
          'A new section needs its Dutch source here (and 31 translations), or '
          'it renders English regardless of the report language.',
    );
  });

  test('each source resolves back to its own anchor in English', () {
    FindingSpec.sectionSources.forEach((anchor, dutchSource) {
      expect(
        AppLocalizations.sourceFor('en', dutchSource),
        equals(anchor),
        reason:
            'The English translation of "$dutchSource" must be exactly the '
            'anchor "$anchor". A deck with no recorded language resolves via '
            'the en fallback, so if these drift, findings render a heading the '
            'file never contained.',
      );
    });
  });

  test('an unrecorded report language renders the anchor unchanged', () {
    // The real call the previews make. Empty is the default for every deck that
    // predates the language field, so it must be a no-op.
    FindingSpec.sectionSources.forEach((anchor, dutchSource) {
      expect(
        AppLocalizations.sourceFor('', dutchSource),
        equals(anchor),
        reason: 'An empty language must not change what a finding renders.',
      );
    });
  });

  test('a recorded language renders that language', () {
    expect(
      AppLocalizations.sourceFor('nl', FindingSpec.sectionSources.values.first),
      equals('Beschrijving'),
    );
    // Any of the ~30 languages resolves; German stands in for the rest.
    final de = AppLocalizations.sourceFor('de', 'Beschrijving');
    expect(de, isNot('Beschrijving'));
    expect(de, isNot('Description'));
  });
}
