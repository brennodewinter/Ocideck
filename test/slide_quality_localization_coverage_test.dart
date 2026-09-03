import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/slide_quality_localization.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/l10n/slide_quality_navigation.dart';
import 'package:ocideck/models/slide.dart';
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
      SlideQualityIssueKind.externalMediaFile: {
        'label': 'Afbeelding',
        'path': '/elders/x.png',
      },
      SlideQualityIssueKind.themeLogoMissing: {'path': 'asset:images/x.png'},
      SlideQualityIssueKind.themeLogoDarkMissing: {'background': '#0F172A'},
      SlideQualityIssueKind.textDensityWarning: {'percent': '80%'},
      SlideQualityIssueKind.textDensityCritical: {'percent': '55%'},
      SlideQualityIssueKind.splitRunDragged: {
        'percent': '20%',
        'own': '85%',
        'page': '5',
        'offender': '4',
      },
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
      SlideQualityIssueKind.questionAnswerCountHigh: {
        'count': '20',
        'maximum': '8',
      },
      SlideQualityIssueKind.questionNotAnswerable: {},
      SlideQualityIssueKind.emptySlide: {},
      SlideQualityIssueKind.danglingJump: {'label': 'Naar prijzen'},
      SlideQualityIssueKind.findingUnknownSection: {'section': 'Notes'},
      SlideQualityIssueKind.privacyImage: {'rule': 'image.face', 'sample': '2'},
      SlideQualityIssueKind.privacyImageUnreadable: {'rule': 'image.face'},
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
      SlideQualityIssueKind.improvementOrphanId: {'id': 'X-01'},
      SlideQualityIssueKind.improvementUnusedId: {'id': 'Y-01'},
      SlideQualityIssueKind.calloutInvalidGeometry: {'ref': '(A)'},
      SlideQualityIssueKind.calloutOrphanReference: {'ref': '(A)'},
      SlideQualityIssueKind.calloutDuplicateReference: {'ref': '(A)'},
      SlideQualityIssueKind.calloutMissingAnchor: {},
      SlideQualityIssueKind.calloutCrossingArrows: {},
      SlideQualityIssueKind.calloutTargetOutOfView: {'ref': '(A)'},
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

    test('no message runs the percentage into the next word', () {
      // De dichtheidsmeldingen worden aan elkaar geplakt uit voorvoegsel +
      // getal + achtervoegsel. Ontbreekt de spatie op die naad, dan leest de
      // zin als "(55%van de ontwerpgrootte)": onzichtbaar in de bron, meteen
      // zichtbaar op het scherm. De Nederlandse tekst ís de opzoeksleutel, dus
      // zo'n gat wordt in één klap naar alle talen gekopieerd — vandaar dat
      // deze test ze allemaal langsloopt en niet alleen NL en EN.
      final glued = RegExp(r'%\p{L}', unicode: true);
      for (final code in AppLocalizations.languageNames.keys) {
        AppLocalizations.setActiveLanguageCode(code);
        for (final kind in SlideQualityIssueKind.values) {
          final message = formatSlideQualityIssue(
            l10n,
            issue(kind, args: argsByKind[kind]!),
          );
          expect(
            glued.hasMatch(message),
            isFalse,
            reason:
                '$code/$kind plakt het percentage tegen het volgende '
                'woord: $message',
          );
        }
      }
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

  group('slideQualityFieldLabel', () {
    SlideQualityIssue withField(String? field, {SlideQualitySpan? span}) =>
        SlideQualityIssue(
          slideIndex: 0,
          kind: SlideQualityIssueKind.privacyContact,
          category: SlideQualityCategory.privacy,
          severity: MarkdownValidationSeverity.warning,
          field: field,
          span: span,
        );

    test('vertaalt de veldnaam van de scanner naar een leesbaar label', () {
      AppLocalizations.setActiveLanguageCode('nl');
      expect(slideQualityFieldLabel(l10n, withField('notes')), 'Notities');
      AppLocalizations.setActiveLanguageCode('en');
      expect(slideQualityFieldLabel(l10n, withField('notes')), 'Notes');
    });

    test('zet het volgnummer erbij voor een samengesteld veld', () {
      // `Opsomming` laat nog steeds zoeken; `Opsomming 4` wijst aan.
      inBothLanguages(() {
        expect(
          slideQualityFieldLabel(
            l10n,
            withField(
              'bullets',
              span: const SlideQualitySpan(start: 0, end: 3, fragmentIndex: 3),
            ),
          ),
          endsWith(' 4'),
        );
      });
    });

    test('wijst een tabelcel aan met rij en kolom, niet met een celnummer', () {
      // De scanner bewaart één doorlopende index; getoond als volgnummer werd
      // dat "Tabel 14" — een getal dat nergens op de slide staat.
      const slide = Slide(
        id: 't1',
        type: SlideType.table,
        tableRows: [
          ['Naam', 'E-mail', 'Rol'],
          ['a', 'b', 'c'],
          ['d', 'e', 'f'],
          ['g', 'h', 'i'],
          ['j', 'k', 'l'],
        ],
      );
      // index 13 = rij 4 (0-gebaseerd), kolom 1 bij drie kolommen.
      final label = slideQualityFieldLabel(
        l10n,
        withField(
          'tableRows',
          span: const SlideQualitySpan(start: 0, end: 3, fragmentIndex: 13),
        ),
        slide: slide,
      );
      expect(label, isNot(contains('14')));
      expect(label, contains('5'));
      expect(label, contains('2'));
    });

    test('de koprij krijgt geen rijnummer', () {
      const slide = Slide(
        id: 't2',
        type: SlideType.table,
        tableRows: [
          ['Naam', 'E-mail'],
          ['a', 'b'],
        ],
      );
      final label = slideQualityFieldLabel(
        l10n,
        withField(
          'tableRows',
          span: const SlideQualitySpan(start: 0, end: 3, fragmentIndex: 1),
        ),
        slide: slide,
      );
      expect(label, contains('2'));
      expect(label, isNot(contains('1,')));
    });

    test('zonder de dia liever geen aanduiding dan een verkeerde', () {
      // Geen tabelbreedte, dus geen rij en kolom te berekenen. Dan mag er geen
      // getal staan dat de gebruiker toch niet kan plaatsen.
      inBothLanguages(() {
        final label = slideQualityFieldLabel(
          l10n,
          withField(
            'tableRows',
            span: const SlideQualitySpan(start: 0, end: 3, fragmentIndex: 13),
          ),
        );
        expect(label, isNotNull);
        expect(label, isNot(contains('14')));
      });
    });

    test('elk deckbreed frontmatter-veld heeft een leesbaar label', () {
      // Zonder label komt de melding zonder plaatsaanduiding in het paneel.
      inBothLanguages(() {
        for (final field in kDeckInfoFields) {
          expect(
            slideQualityFieldLabel(l10n, withField(field)),
            isNotNull,
            reason: 'veld $field heeft geen label',
          );
        }
      });
    });

    test('een enkelvoudig veld krijgt geen volgnummer', () {
      inBothLanguages(() {
        final label = slideQualityFieldLabel(
          l10n,
          withField('title', span: const SlideQualitySpan(start: 0, end: 3)),
        );
        expect(label, isNotNull);
        expect(label, isNot(endsWith(' 1')));
      });
    });

    test('een onbekend of ontbrekend veld geeft niets terug', () {
      // Liever geen plaatsaanduiding dan een verkeerde: `textColor` is een
      // themaveld en hoort niet in de veldenlijst van een slide.
      inBothLanguages(() {
        expect(slideQualityFieldLabel(l10n, withField(null)), isNull);
        expect(slideQualityFieldLabel(l10n, withField('')), isNull);
        expect(slideQualityFieldLabel(l10n, withField('textColor')), isNull);
      });
    });
  });

  group('run-scope-suffix bij samengevatte split-run-meldingen (#1289)', () {
    test('voegt de reeks-omvang toe zodra runPages is gezet', () {
      inBothLanguages(() {
        final base = formatSlideQualityIssue(
          l10n,
          issue(
            SlideQualityIssueKind.bulletAverageLengthHigh,
            category: SlideQualityCategory.textDensity,
            args: const {'average': '20'},
          ),
        );
        final withRun = formatSlideQualityIssue(
          l10n,
          issue(
            SlideQualityIssueKind.bulletAverageLengthHigh,
            category: SlideQualityCategory.textDensity,
            args: const {'average': '20', 'runPages': '5'},
          ),
        );
        // De samengevatte melding begint met de gewone tekst en zegt er eerlijk
        // bij op hoeveel pagina's van de reeks ze staat.
        expect(withRun, startsWith(base));
        expect(withRun.length, greaterThan(base.length));
        expect(withRun, contains('5'));
      });
    });
  });
}
