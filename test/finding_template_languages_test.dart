import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/finding_template.dart';
import 'package:ocideck/services/finding_template_library.dart';
import 'package:ocideck/services/finding_templates/all.dart';

/// The bundled finding templates exist in every language OciDeck speaks, and a
/// template is a **mixed document**: the prose is ours and gets translated, but
/// the section headings are `FindingSpec` parse anchors, the CWE line is a MITRE
/// citation, the severity is FIRST's published band label, and the vector and
/// references are tokens (PENTEST_MIAUW §12.1).
///
/// Translating any of the fixed parts breaks something *quietly*: a translated
/// `## Description` still renders fine in the picker, but the section arrives
/// empty in the finding. These tests make that loud.
void main() {
  const fallback = FindingTemplateLibrary.fallbackLanguage;
  final slugs = findingTemplateSources[fallback]!.keys.toSet();

  test('every language OciDeck speaks has templates', () {
    expect(
      findingTemplateSources.keys.toSet(),
      equals(AppLocalizations.languageNames.keys.toSet()),
      reason:
          'A language with no template file falls back to English silently. '
          'Add lib/services/finding_templates/<code>.dart, or drop the language.',
    );
  });

  test('every language carries the full set of templates', () {
    findingTemplateSources.forEach((code, sources) {
      expect(
        sources.keys.toSet(),
        equals(slugs),
        reason:
            '$code is missing or has extra templates. Every language ships the '
            'same slugs, so the picker offers the same set to everyone.',
      );
    });
  });

  group('the fixed parts stay fixed', () {
    /// A front-matter value from the raw template source.
    String field(String source, String key) => source
        .split('\n')
        .firstWhere((l) => l.startsWith('$key: '), orElse: () => '')
        .substring(key.length + 2)
        .trim();

    test('severity, CVSS and CWE are identical in every language', () {
      for (final slug in slugs) {
        final reference = findingTemplateSources[fallback]![slug]!;
        findingTemplateSources.forEach((code, sources) {
          final source = sources[slug]!;
          for (final key in [
            'severity',
            'cvss_vector',
            'cvss_version',
            'cwe',
          ]) {
            expect(
              field(source, key),
              equals(field(reference, key)),
              reason:
                  '$code/$slug changed `$key`. The CWE line is a MITRE citation '
                  'and the severity is FIRST\'s published band label — the same '
                  'label a finding stores for itself. Translating either makes '
                  'the template disagree with the finding beside it.',
            );
          }
        });
      }
    });

    test('every language uses the English section anchors', () {
      const anchors = [
        FindingSpec.sectionDescription,
        FindingSpec.sectionConfirmation,
        FindingSpec.sectionImpact,
        FindingSpec.sectionRecommendation,
      ];
      findingTemplateSources.forEach((code, sources) {
        sources.forEach((slug, source) {
          for (final anchor in anchors) {
            expect(
              source.contains('## $anchor'),
              isTrue,
              reason:
                  '$code/$slug is missing the anchor "## $anchor". The heading '
                  'shown to the reader is resolved at render time from the '
                  'report language; the one in the file is a parse anchor and '
                  'must stay English (§3.1).',
            );
          }
        });
      });
    });
  });

  test('every template in every language parses with all four sections', () {
    // The test that would catch a translated anchor even if the check above
    // were fooled: a section the parser cannot find comes back empty.
    findingTemplateSources.forEach((code, sources) {
      sources.forEach((slug, source) {
        final t = FindingTemplate.parse(source, id: slug);
        expect(t.title, isNotEmpty, reason: '$code/$slug lost its title');
        expect(t.cvssVector, isNotEmpty, reason: '$code/$slug lost its vector');
        expect(t.cweId, isNotNull, reason: '$code/$slug lost its CWE id');
        for (final s in {
          'description': t.description,
          'confirmation': t.confirmation,
          'impact': t.impact,
          'recommendation': t.recommendation,
        }.entries) {
          expect(
            s.value.trim(),
            isNotEmpty,
            reason:
                '$code/$slug has an empty ${s.key}. Most likely its "## …" '
                'anchor was translated, so the parser never found the section.',
          );
        }
      });
    });
  });

  group('resolution follows the report language', () {
    final library = FindingTemplateLibrary.instance;

    test('a known language yields that language', () {
      final nl = library.bundledFor('nl');
      final en = library.bundledFor('en');
      expect(nl.length, en.length);
      expect(nl.first.title, isNot(en.first.title));
    });

    test('an unrecorded or unknown language yields English', () {
      for (final code in ['', 'zz']) {
        final got = library.bundledFor(code);
        expect(
          got.map((t) => t.title),
          library.bundledFor('en').map((t) => t.title),
        );
      }
    });

    test('the prose really is translated, not merely present', () {
      final nl = library.bundledFor('nl').first;
      final en = library.bundledFor('en').first;
      expect(nl.description, isNot(en.description));
      // …while the citation beside it is untouched.
      expect(nl.cweName, equals(en.cweName));
      expect(nl.cvssVector, equals(en.cvssVector));
    });
  });
}
