// De berichtencatalogus voor de organisator (FORM_INTAKE.md §4.11, §7.2): voor elke
// code die een binnengekomen inzending kan raken een zin over de inzender, in elke
// taal, zonder dat er een plaatsvervanger of een kale code overblijft.

import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/form_issue_localization.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

FormProblem p(
  FormIssueCode code, [
  Map<String, Object?> facts = const {},
  String? field = 'x',
]) => FormProblem(code, fieldId: field, facts: facts);

/// De codes van de auteur: die komen nooit in een inzending voor, want een formulier
/// met zo'n fout wordt niet gepubliceerd.
const authorCodes = {
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

/// Van elke code die een inzending kan raken, elke variant die de catalogus kent.
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
  p(FormIssueCode.numberOutOfRange, {'min': '1', 'max': '9'}),
  p(FormIssueCode.numberOutOfRange, {'min': '1'}),
  p(FormIssueCode.numberOutOfRange, {'max': '9'}),
  p(FormIssueCode.numberOutOfRange, {'reason': 'step', 'step': '5'}),
  p(FormIssueCode.badDate, {'value': 'morgen'}),
  p(FormIssueCode.badDate, {'reason': 'before-min', 'min': '2026-11-01'}),
  p(FormIssueCode.badDate, {'reason': 'after-max', 'max': '2026-11-01'}),
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
  p(FormIssueCode.answerMalformed, {'reason': 'one-line'}),
  p(FormIssueCode.answerContainsMarker),
  p(FormIssueCode.answerContainsHtml),
  p(FormIssueCode.answerUnclosedFence),
  p(FormIssueCode.answerBadImage),
  p(FormIssueCode.answerBadLink),
  p(FormIssueCode.templateUnknown, {'form': 'kook', 'version': 2}, null),
  p(FormIssueCode.templateTextAltered, {'reason': 'hash'}, null),
  p(FormIssueCode.templateTextAltered, {'reason': 'consent'}, null),
  p(FormIssueCode.templateTextAltered, {'region': 'naam', 'differing': 2}),
  p(FormIssueCode.templateTextAltered, {
    'region': 'outside-fields',
    'differing': 1,
  }, null),
  p(FormIssueCode.fieldNotInForm),
  p(FormIssueCode.fieldMissing),
  p(FormIssueCode.formVersionMismatch, {'published': 3, 'submission': 2}, null),
  p(FormIssueCode.rulesTooNew, {'form': 'kook', 'rules': 99}, null),
  p(FormIssueCode.structureDamaged, {'reason': 'published-form'}, null),
  p(FormIssueCode.structureDamaged, {'reason': 'form-id'}, null),
  p(FormIssueCode.structureDamaged, {'reason': 'rules-too-new'}, null),
  p(FormIssueCode.structureDamaged, {'reason': 'broken'}, null),
];

AppLocalizations l(String code) => AppLocalizations(Locale(code));

void main() {
  final nl = l('nl');
  String say(FormProblem problem) => formOrganiserMessage(nl, problem);

  group('zinnen in het Nederlands', () {
    test('gaan over de inzender, niet tot hem', () {
      expect(
        say(p(FormIssueCode.tooFewWords, {'min': 150, 'actual': 90})),
        '90 woorden; minstens 150 nodig.',
      );
      expect(
        say(p(FormIssueCode.tooLong, {'max': 60, 'actual': 81})),
        '81 tekens; hoogstens 60 toegestaan.',
      );
      expect(
        say(p(FormIssueCode.requiredEmpty)),
        'Verplicht, maar leeg gelaten.',
      );
      expect(
        say(p(FormIssueCode.consentNotGiven)),
        'Toestemming niet gegeven.',
      );
      for (final problem in samples) {
        final message = say(problem);
        expect(
          message,
          isNot(contains(RegExp(r'\b(je|jouw|jij)\b'))),
          reason: message,
        );
      }
    });

    test('een punt van een lijst zegt welk punt', () {
      expect(
        say(p(FormIssueCode.tooFewWords, {'min': 3, 'actual': 1, 'item': 2})),
        'Punt 2: 1 woorden; minstens 3 nodig.',
      );
    });

    test(
      'een datum buiten de grenzen noemt de grens, een slechte datum de vorm',
      () {
        expect(
          say(
            p(FormIssueCode.badDate, {
              'reason': 'before-min',
              'min': '2026-11-01',
            }),
          ),
          'De datum moet op of na 2026-11-01 liggen.',
        );
        expect(
          say(p(FormIssueCode.badDate, {'value': 'morgen'})),
          '“morgen” is geen datum in de vorm jaar-maand-dag.',
        );
      },
    );

    test('een antwoord van de verkeerde vorm krijgt één neutrale zin', () {
      for (final reason in [
        'one-line',
        'not-a-table',
        'consent-box',
        'wat-dan-ook',
      ]) {
        expect(
          say(p(FormIssueCode.answerMalformed, {'reason': reason})),
          'Dit antwoord heeft niet de vorm die bij deze vraag hoort.',
        );
      }
    });

    test(
      'een verandering in de tekst van het formulier kiest de zin naar waar',
      () {
        expect(
          say(p(FormIssueCode.templateTextAltered, {'reason': 'hash'}, null)),
          'De inzender werkte met een andere tekst van het formulier dan de gepubliceerde.',
        );
        expect(
          say(
            p(FormIssueCode.templateTextAltered, {'reason': 'consent'}, null),
          ),
          'De toestemming in het manifest klopt niet met het gepubliceerde formulier.',
        );
        expect(
          say(p(FormIssueCode.templateTextAltered, {'region': 'naam'})),
          'De tekst van het formulier is veranderd bij dit veld.',
        );
        expect(
          say(p(FormIssueCode.templateTextAltered, {'region': 'notice'}, null)),
          'De tekst van het formulier is veranderd buiten de antwoorden.',
        );
      },
    );

    test('een beschadigde opbouw kiest de zin naar de reden', () {
      String of(String reason) =>
          say(p(FormIssueCode.structureDamaged, {'reason': reason}, null));
      expect(of('published-form'), contains('gepubliceerde formulier'));
      expect(of('form-id'), 'De inzending hoort bij een ander formulier.');
      expect(
        of('rules-too-new'),
        'Het formulier vraagt een nieuwere versie van OciDeck.',
      );
      expect(of('wat-dan-ook'), 'De opbouw van de inzending is beschadigd.');
    });

    test('een versieverschil noemt beide versies', () {
      expect(
        say(
          p(FormIssueCode.formVersionMismatch, {
            'published': 3,
            'submission': 2,
          }),
        ),
        'Inzending van versie 2; gepubliceerd is versie 3.',
      );
    });
  });

  group('de indeling van de codes', () {
    test('elke code is of voor een inzending of voor de auteur', () {
      final noMessage = {
        for (final code in FormIssueCode.values)
          if (formOrganiserMessageOrNull(nl, FormProblem(code)) == null) code,
      };
      expect(noMessage, authorCodes);
    });

    test('een auteurscode krijgt de algemene zin, nooit een kale code', () {
      for (final code in authorCodes) {
        final message = say(FormProblem(code));
        expect(message, 'Er klopt iets niet aan deze inzending.');
        expect(message, isNot(contains(code.wireName)));
      }
    });
  });

  group('in elke taal', () {
    final codes = AppLocalizations.languageNames.keys.toList();

    test('elke zin is gevuld en laat geen plaatsvervanger of code achter', () {
      for (final code in codes) {
        final loc = l(code);
        for (final problem in samples) {
          final message = formOrganiserMessage(loc, problem);
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
        'lib/l10n/form_organiser_localization.dart',
      ).readAsStringSync();
      final keys = {
        for (final m in RegExp(r"l10n\s*\.d\(\s*'([^']*)'").allMatches(source))
          m.group(1)!,
      };
      expect(keys.length, greaterThanOrEqualTo(30));
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
