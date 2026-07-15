import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/slide_quality_localization.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide_quality.dart';

/// Covers the slide-quality issue → localized message mapping
/// (lib/l10n/slide_quality_localization.dart). Each issue kind, severity,
/// category and privacy rule id is formatted, in both Dutch and English, so the
/// exhaustive switches are fully exercised.
void main() {
  const l10n = AppLocalizations(Locale('nl'));

  // Every test re-runs in NL and EN; restore the default afterwards.
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  void inBothLanguages(void Function() body) {
    for (final code in const ['nl', 'en']) {
      AppLocalizations.setActiveLanguageCode(code);
      body();
    }
  }

  SlideQualityIssue issue(
    SlideQualityIssueKind kind, {
    SlideQualityCategory category = SlideQualityCategory.content,
    MarkdownValidationSeverity severity = MarkdownValidationSeverity.warning,
    Map<String, String> args = const {},
    int slideIndex = 0,
    String? field,
  }) => SlideQualityIssue(
    slideIndex: slideIndex,
    kind: kind,
    category: category,
    severity: severity,
    field: field,
    args: args,
  );

  group('count summary and export reason', () {
    test('reports "no issues" when the result is clean', () {
      inBothLanguages(() {
        final summary = formatSlideQualityCountSummary(
          l10n,
          const SlideQualityResult([]),
        );
        expect(summary, isNotEmpty);
      });
    });

    test('joins error, warning and info counts', () {
      final result = SlideQualityResult([
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.error,
        ),
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.warning,
        ),
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.informational,
        ),
      ]);
      inBothLanguages(() {
        final summary = formatSlideQualityCountSummary(l10n, result);
        expect(summary, contains('1'));
        // errors, warnings and tips are all represented.
        expect(summary.split(',').length, 3);
      });
    });

    test('export reason names the blocking counts', () {
      final result = SlideQualityResult([
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.error,
        ),
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.warning,
        ),
      ]);
      inBothLanguages(() {
        final reason = formatQualityExportReason(l10n, result);
        expect(reason, isNotEmpty);
        expect(reason, contains('1'));
      });
    });
  });

  group('severity and category helpers', () {
    test('severity colour, icon and label cover every severity', () {
      for (final severity in MarkdownValidationSeverity.values) {
        expect(slideQualitySeverityColor(severity), isA<Color>());
        expect(slideQualitySeverityIcon(severity), isA<IconData>());
        inBothLanguages(() {
          expect(slideQualitySeverityLabel(l10n, severity), isNotEmpty);
        });
      }
    });

    test('category label covers every category', () {
      for (final category in SlideQualityCategory.values) {
        inBothLanguages(() {
          expect(slideQualityCategoryLabel(l10n, category), isNotEmpty);
        });
      }
    });
  });

  group('performed-checks list', () {
    test('omits the privacy check when privacy scanning is off', () {
      inBothLanguages(() {
        final without = slideQualityPerformedChecks(
          l10n,
          privacyEnabled: false,
        );
        final with_ = slideQualityPerformedChecks(l10n, privacyEnabled: true);
        expect(with_.length, without.length + 1);
        // Each entry is fully populated.
        for (final check in with_) {
          expect(check.title, isNotEmpty);
          expect(check.detail, isNotEmpty);
          expect(check.params, isNotEmpty);
        }
      });
    });
  });

  group('formatSlideQualityIssue covers every issue kind', () {
    // Sensible args for the kinds that interpolate parameters.
    final argsByKind = <SlideQualityIssueKind, Map<String, String>>{
      SlideQualityIssueKind.missingAltCaption: {'label': 'Afbeelding'},
      SlideQualityIssueKind.themeContrast: {
        'label': 'Thema',
        'ratio': '3.1',
        'threshold': '4.5',
        'largeText': 'false',
      },
      SlideQualityIssueKind.footerContrast: {
        'label': 'Footer',
        'ratio': '2.9',
        'threshold': '3.0',
        'largeText': 'true',
      },
      SlideQualityIssueKind.checklistContrast: {
        'label': 'Checklist',
        'ratio': '3.5',
        'threshold': '4.5',
        'largeText': 'false',
      },
      SlideQualityIssueKind.slideContrast: {
        'label': 'Slide',
        'ratio': '2.0',
        'threshold': '4.5',
      },
      SlideQualityIssueKind.imageContrastUnverified: {},
      SlideQualityIssueKind.titleImageContrast: {'ratio': '2.2'},
      SlideQualityIssueKind.chartMissingDescription: {},
      SlideQualityIssueKind.mediaMissingDescription: {'label': 'Video'},
      SlideQualityIssueKind.missingMediaFile: {
        'label': 'Afbeelding',
        'path': 'images/x.png',
      },
      SlideQualityIssueKind.textDensityWarning: {'percent': '80%'},
      SlideQualityIssueKind.textDensityCritical: {'percent': '55%'},
      SlideQualityIssueKind.tableDensityMinimum: {'rows': '12', 'cols': '6'},
      SlideQualityIssueKind.codeDensityHigh: {'lines': '40'},
      SlideQualityIssueKind.freeMarkdownDensityHigh: {'lines': '35'},
      SlideQualityIssueKind.titleDensityHigh: {'chars': '120'},
      SlideQualityIssueKind.quoteDensityHigh: {'chars': '200'},
      SlideQualityIssueKind.bulletCountHigh: {'count': '9'},
      SlideQualityIssueKind.bulletCountCritical: {'count': '14'},
      SlideQualityIssueKind.bulletWordCountHigh: {'words': '80'},
      SlideQualityIssueKind.bulletWordCountCritical: {'words': '140'},
      SlideQualityIssueKind.bulletAverageLengthHigh: {'average': '12'},
      SlideQualityIssueKind.bulletMultiSentence: {},
      SlideQualityIssueKind.bulletNestingDeep: {'level': '4'},
      SlideQualityIssueKind.bulletColumnImbalance: {'left': '8', 'right': '1'},
      SlideQualityIssueKind.questionNotAnswerable: {},
      SlideQualityIssueKind.privacyIdentifier: {
        'rule': 'nl.bsn',
        'sample': 'j…l',
      },
      SlideQualityIssueKind.privacyFinancial: {
        'rule': 'fin.iban',
        'sample': 'N…9',
      },
      SlideQualityIssueKind.privacyContact: {
        'rule': 'contact.email',
        'sample': 'a…m',
      },
      SlideQualityIssueKind.privacyDigital: {
        'rule': 'struct.url_token',
        'sample': 't…n',
      },
      SlideQualityIssueKind.privacySecret: {
        'rule': 'secret.aws',
        'sample': 'A…Z',
      },
      SlideQualityIssueKind.privacySpecialCategory: {
        'rule': 'special.health',
        'sample': 'z…g',
      },
      SlideQualityIssueKind.privacyBulk: {
        'rule': 'bulk.repeat',
        'sample': 'm…a',
      },
      SlideQualityIssueKind.privacyStructural: {
        'rule': 'struct.user_path',
        'sample': 'u…r',
      },
    };

    test('produces a non-empty message for each kind in both languages', () {
      // Guard against the map drifting out of sync with the enum.
      expect(argsByKind.keys.toSet(), SlideQualityIssueKind.values.toSet());

      inBothLanguages(() {
        for (final kind in SlideQualityIssueKind.values) {
          final message = formatSlideQualityIssue(
            l10n,
            issue(kind, args: argsByKind[kind]!),
          );
          expect(
            message.trim(),
            isNotEmpty,
            reason: '$kind produced an empty message',
          );
        }
      });
    });

    test('privacy escalation suffix differs for a linked special category', () {
      AppLocalizations.setActiveLanguageCode('nl');
      // A special-category finding that is NOT merely informational escalates,
      // hitting the _privacySuffix special branch.
      final escalated = formatSlideQualityIssue(
        l10n,
        issue(
          SlideQualityIssueKind.privacySpecialCategory,
          severity: MarkdownValidationSeverity.error,
          args: {'rule': 'special.health', 'sample': 'z…g'},
        ),
      );
      // The informational variant takes the softer suffix branch instead.
      final informational = formatSlideQualityIssue(
        l10n,
        issue(
          SlideQualityIssueKind.privacySpecialCategory,
          severity: MarkdownValidationSeverity.informational,
          args: {'rule': 'special.health', 'sample': 'z…g'},
        ),
      );
      expect(escalated, isNot(equals(informational)));
    });
  });

  group('privacyRuleLabel covers every rule family', () {
    const ruleIds = [
      // Explicit Dutch/contact/financial rules.
      'nl.bsn',
      'fin.iban',
      'contact.email',
      'contact.phone',
      'contact.address',
      'contact.postcode_nl',
      'contact.name',
      // Special categories (AVG art. 9/10).
      'special.health',
      'special.criminal',
      'special.religion',
      'special.union',
      'special.biometric',
      'special.politics',
      'special.ethnicity',
      'special.sexlife',
      'special.genetic',
      'nl.parketnummer',
      // Bulk and structural.
      'bulk.table_column',
      'bulk.repeat',
      'struct.user_path',
      'struct.url_token',
      'struct.url_pii',
      'struct.share_link',
      'struct.mailto',
      'struct.data_uri',
      // National number names (the _euNumberNames branch).
      'be.rijksregister',
      'de.steuer_id',
      'fr.nir',
      'pl.pesel',
      'uk.nhs',
      // Named secret rules.
      'secret.private_key',
      'secret.jwt',
      'secret.connection_string',
      'secret.password_plain',
      // Vendor secret rules (the startsWith('secret.') branch).
      'secret.aws',
      'secret.github',
      'secret.stripe',
      // Unknown vendor secret still resolves via the startsWith branch.
      'secret.unknownvendor',
    ];

    test('every known rule id resolves to a non-empty label', () {
      inBothLanguages(() {
        for (final id in ruleIds) {
          expect(
            privacyRuleLabel(l10n, id).trim(),
            isNotEmpty,
            reason: 'rule $id gave an empty label',
          );
        }
      });
    });

    test('an unknown rule id falls back to the raw id', () {
      inBothLanguages(() {
        expect(privacyRuleLabel(l10n, 'totally.unknown'), 'totally.unknown');
      });
    });
  });

  group('slideQualitySeverityForField', () {
    SlideQualityResult resultWith(List<SlideQualityIssue> issues) =>
        SlideQualityResult(issues);

    test('returns null when nothing matches the slide/field', () {
      final severity = slideQualitySeverityForField(
        result: resultWith([
          issue(SlideQualityIssueKind.bulletMultiSentence, field: 'other'),
        ]),
        slideIndex: 0,
        field: 'textColor',
      );
      expect(severity, isNull);
    });

    test('promotes to the most severe matching issue', () {
      final result = resultWith([
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.informational,
          field: 'textColor',
        ),
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.warning,
          field: 'textColor',
        ),
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.error,
          field: 'textColor',
        ),
      ]);
      expect(
        slideQualitySeverityForField(
          result: result,
          slideIndex: 0,
          field: 'textColor',
        ),
        MarkdownValidationSeverity.error,
      );
    });

    test('returns warning when the worst match is a warning', () {
      final result = resultWith([
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.informational,
          field: 'textColor',
        ),
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.warning,
          field: 'textColor',
        ),
      ]);
      expect(
        slideQualitySeverityForField(
          result: result,
          slideIndex: 0,
          field: 'textColor',
        ),
        MarkdownValidationSeverity.warning,
      );
    });

    test('returns informational when only tips match', () {
      final result = resultWith([
        issue(
          SlideQualityIssueKind.bulletMultiSentence,
          severity: MarkdownValidationSeverity.informational,
          field: 'textColor',
        ),
      ]);
      expect(
        slideQualitySeverityForField(
          result: result,
          slideIndex: 0,
          field: 'textColor',
        ),
        MarkdownValidationSeverity.informational,
      );
    });
  });
}
