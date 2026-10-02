// De berichtencatalogus van het formulier (FORM_INTAKE.md §8): voor elke code die
// de invuller kan raken een zin die zegt wat er mis is en wat hij ermee kan, in
// elke taal, zonder dat er een plaatsvervanger of een kale code overblijft.

import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/form_issue_localization.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

FormProblem p(FormIssueCode code, [Map<String, Object?> facts = const {}]) =>
    FormProblem(code, fieldId: 'x', facts: facts);

/// Van elke code die de invuller raakt, elke variant die de catalogus kent.
final samples = <FormProblem>[
  p(FormIssueCode.requiredEmpty),
  p(FormIssueCode.tooFewWords, {'min': 150, 'actual': 90}),
  p(FormIssueCode.tooFewWords, {'min': 3, 'actual': 1, 'item': 2}),
  p(FormIssueCode.tooManyWords, {'max': 300, 'actual': 412}),
  p(FormIssueCode.tooManyWords, {'max': 10, 'actual': 12, 'item': 4}),
  p(FormIssueCode.tooShort, {'min': 20, 'actual': 5}),
  p(FormIssueCode.tooLong, {'max': 60, 'actual': 81}),
  p(FormIssueCode.notAnOption, {'value': 'iets'}),
  p(FormIssueCode.countOutOfRange, {'min': 3, 'max': 6, 'actual': 1}),
  p(FormIssueCode.countOutOfRange, {'min': 3, 'actual': 1}),
  p(FormIssueCode.countOutOfRange, {'max': 6, 'actual': 9}),
  p(FormIssueCode.badNumber, {'value': 'abc'}),
  p(FormIssueCode.numberOutOfRange, {'min': '1', 'max': '9', 'value': '12'}),
  p(FormIssueCode.numberOutOfRange, {'min': '1', 'value': '0'}),
  p(FormIssueCode.numberOutOfRange, {'max': '9', 'value': '12'}),
  p(FormIssueCode.numberOutOfRange, {
    'reason': 'step',
    'step': '5',
    'value': '7',
  }),
  p(FormIssueCode.badDate, {'value': 'morgen'}),
  p(FormIssueCode.badDate, {
    'reason': 'before-min',
    'min': '2026-11-01',
    'value': '2026-10-01',
  }),
  p(FormIssueCode.badDate, {
    'reason': 'after-max',
    'max': '2026-11-01',
    'value': '2026-12-01',
  }),
  for (final name in ['email', 'url', 'phone', 'postcode-nl', 'onbekend'])
    p(FormIssueCode.badPattern, {'pattern': name}),
  p(FormIssueCode.imageTooSmall, {'min': 2000, 'actual': 1600}),
  p(FormIssueCode.imageTooLarge, {'max': 4194304, 'actual': 5000000}),
  p(FormIssueCode.imageFormat, {'reason': 'not-allowed'}),
  p(FormIssueCode.imageFormat, {'reason': 'mismatch'}),
  p(FormIssueCode.imageMissingFile),
  p(FormIssueCode.imageMissingAlt),
  p(FormIssueCode.imageMissingCredit),
  p(FormIssueCode.imageUnchecked),
  p(FormIssueCode.imageHeicUnverified),
  p(FormIssueCode.imageUnexpectedFaces, {'expected': '1', 'actual': 3}),
  p(FormIssueCode.consentNotGiven),
  p(FormIssueCode.structureDamaged, {'reason': 'broken'}),
  p(FormIssueCode.structureDamaged, {'reason': 'rules-too-new'}),
  for (final reason in [
    'one-line',
    'not-a-task-list',
    'unordered-item',
    'ordered-item',
    'not-a-list',
    'not-a-table',
    'header-mismatch',
    'rule-row',
    'row-shape',
    'duplicate-image',
    'not-an-image',
    'consent-box-missing',
    'consent-box',
    'iets-onbekends',
  ])
    p(FormIssueCode.answerMalformed, {'reason': reason}),
  p(FormIssueCode.answerContainsMarker),
  p(FormIssueCode.answerContainsHtml),
  p(FormIssueCode.answerUnclosedFence),
  p(FormIssueCode.answerBadImage),
  p(FormIssueCode.answerBadLink),
  p(FormIssueCode.formVersionMismatch, {'published': 3, 'submission': 2}),
];

/// De codes die bij de organisator of de auteur horen: hun zinnen komen met het
/// oppervlak dat ze toont. Een nieuwe code moet hier of in de catalogus komen —
/// niet stilzwijgend in de algemene zin vallen.
const organiserOrAuthorCodes = {
  FormIssueCode.templateTextAltered,
  FormIssueCode.templateUnknown,
  FormIssueCode.fieldNotInForm,
  FormIssueCode.fieldMissing,
  FormIssueCode.rulesTooNew,
  FormIssueCode.ruleMalformed,
  FormIssueCode.duplicateFieldId,
  FormIssueCode.unpairedMarker,
  FormIssueCode.unknownType,
  FormIssueCode.markerMalformed,
  FormIssueCode.markerMisplaced,
  FormIssueCode.noticeMissing,
  FormIssueCode.formAttributeMissing,
  FormIssueCode.unknownMarker,
  FormIssueCode.unknownRule,
};

AppLocalizations l(String code) => AppLocalizations(Locale(code));

void main() {
  final nl = l('nl');

  group('zinnen in het Nederlands', () {
    test('een woordenmelding noemt wat er is en wat er nodig is', () {
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.tooFewWords, {'min': 150, 'actual': 90}),
        ),
        'Je hebt 90 woorden geschreven; er zijn er minstens 150 nodig.',
      );
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.tooManyWords, {'max': 300, 'actual': 412}),
        ),
        'Je hebt 412 woorden geschreven; er mogen er hoogstens 300 zijn.',
      );
    });

    test('een woordenmelding bij één punt van een lijst zegt welk punt', () {
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.tooFewWords, {'min': 3, 'actual': 1, 'item': 2}),
        ),
        'Punt 2: Je hebt 1 woorden geschreven; er zijn er minstens 3 nodig.',
      );
    });

    test('een aantal kiest de zin naar de grenzen die er zijn', () {
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.countOutOfRange, {'min': 3, 'max': 6, 'actual': 1}),
        ),
        'Het aantal is nu 1; het moet tussen 3 en 6 liggen.',
      );
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.countOutOfRange, {'min': 3, 'actual': 1}),
        ),
        'Het aantal is nu 1; het moet minstens 3 zijn.',
      );
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.countOutOfRange, {'max': 6, 'actual': 9}),
        ),
        'Het aantal is nu 9; het mag hoogstens 6 zijn.',
      );
    });

    test('een getal, een stap en een datum noemen hun grens', () {
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.numberOutOfRange, {
            'reason': 'step',
            'step': '5',
            'value': '7',
          }),
        ),
        'Het getal moet een veelvoud zijn van 5.',
      );
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.numberOutOfRange, {'min': '1', 'max': '9'}),
        ),
        'Het getal moet tussen 1 en 9 liggen.',
      );
      expect(
        formIssueMessage(
          nl,
          p(FormIssueCode.badDate, {
            'reason': 'after-max',
            'max': '2026-11-01',
          }),
        ),
        'De datum moet op of vóór 2026-11-01 liggen.',
      );
    });

    test(
      'een foto van 5 MB bij een grens van 4 MB zet twee verschillende getallen',
      () {
        // 4194304 is precies 4 MiB; 4300000 is 4,1 MiB: naar boven afgerond is dat 5.
        expect(
          formIssueMessage(
            nl,
            p(FormIssueCode.imageTooLarge, {'max': 4194304, 'actual': 4300000}),
          ),
          'Deze foto is 5 MB; het maximum is 4 MB.',
        );
        // Een grens onder 1 MB blijft 1: "maximum 0 MB" zou onzin zijn.
        expect(
          formIssueMessage(
            nl,
            p(FormIssueCode.imageTooLarge, {'max': 500000, 'actual': 900000}),
          ),
          'Deze foto is 1 MB; het maximum is 1 MB.',
        );
        expect(
          formIssueMessage(nl, p(FormIssueCode.imageTooLarge)),
          'Deze foto is – MB; het maximum is – MB.',
        );
      },
    );

    test('wat de invuller zelf typte wordt ingekort', () {
      final long = 'x' * 100;
      final message = formIssueMessage(
        nl,
        p(FormIssueCode.notAnOption, {'value': long}),
      );
      expect(message, contains('${'x' * 39}…'));
      expect(message, isNot(contains('x' * 41)));
      expect(
        formIssueMessage(nl, p(FormIssueCode.notAnOption, {'value': 'a' * 40})),
        contains('a' * 40),
        reason: 'precies de grens blijft heel',
      );
    });

    test(
      'een antwoord dat zijn vorm kwijt is krijgt de zin van zijn groep',
      () {
        String of(String reason) => formIssueMessage(
          nl,
          p(FormIssueCode.answerMalformed, {'reason': reason}),
        );
        expect(of('one-line'), startsWith('Hier past één regel'));
        expect(of('unordered-item'), of('not-a-list'));
        expect(of('header-mismatch'), of('row-shape'));
        expect(of('consent-box'), of('consent-box-missing'));
        expect(of('duplicate-image'), isNot(of('not-an-image')));
        expect(
          of('wat-dan-ook'),
          startsWith('Dit antwoord heeft niet de vorm'),
        );
      },
    );

    test('een onbekend patroon valt terug op de algemene vormzin', () {
      expect(
        formIssueMessage(nl, p(FormIssueCode.badPattern, {'pattern': 'x'})),
        startsWith('Dit antwoord heeft niet de vorm'),
      );
    });
  });

  group('de indeling van de codes', () {
    test('elke code is of voor de invuller of voor organisator en auteur', () {
      final noMessage = {
        for (final code in FormIssueCode.values)
          if (formIssueMessageOrNull(nl, FormProblem(code)) == null) code,
      };
      expect(noMessage, organiserOrAuthorCodes);
    });

    test(
      'een code van de organisator krijgt de algemene zin, nooit een kale code',
      () {
        for (final code in organiserOrAuthorCodes) {
          final message = formIssueMessage(nl, FormProblem(code));
          expect(message, startsWith('Er klopt iets niet aan dit formulier'));
          expect(message, isNot(contains(code.wireName)));
        }
      },
    );
  });

  group('in elke taal', () {
    final codes = AppLocalizations.languageNames.keys.toList();

    test('elke zin is gevuld en laat geen plaatsvervanger of code achter', () {
      for (final code in codes) {
        final loc = l(code);
        for (final problem in samples) {
          final message = formIssueMessage(loc, problem);
          final where = '$code ${problem.code.wireName} ${problem.facts}';
          expect(message.trim(), isNotEmpty, reason: where);
          expect(
            RegExp(r'\{[a-zA-Z]+\}').hasMatch(message),
            isFalse,
            reason: 'plaatsvervanger over in "$message" ($where)',
          );
          expect(
            message.contains(problem.code.wireName),
            isFalse,
            reason: 'kale code in "$message" ($where)',
          );
        }
      }
    });

    test('elke vertaling draagt dezelfde plaatsvervangers als de bron', () {
      final source = File(
        'lib/l10n/form_issue_localization.dart',
      ).readAsStringSync();
      final keys = {
        for (final m in RegExp(r"l10n\s*\.d\(\s*'([^']*)'").allMatches(source))
          m.group(1)!,
      };
      // Eén bron per zin: de catalogus telt er minstens vijftig.
      expect(keys.length, greaterThanOrEqualTo(50));
      final holder = RegExp(r'\{[a-zA-Z]+\}');
      for (final key in keys) {
        final wanted = {for (final m in holder.allMatches(key)) m.group(0)!};
        for (final code in codes) {
          final translated = AppLocalizations.sourceFor(code, key);
          final got = {
            for (final m in holder.allMatches(translated)) m.group(0)!,
          };
          expect(
            got,
            wanted,
            reason: '$code vertaalt "$key" met andere plaatsvervangers',
          );
        }
      }
    });
  });
}
