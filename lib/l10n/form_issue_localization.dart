// De berichtencatalogus van het formulier (FORM_INTAKE.md §8): voor elke
// uitkomst van de validatie één zin in de taal van de invuller, die zegt wat er
// mis is én wat hij ermee kan. Een kale code ("too-few-words") komt nooit voor
// zijn ogen.
//
// De engine in `packages/ocideck_form_core` kent geen taal; zij levert een
// `FormProblem` met een code en feiten (`min`, `actual`, `reason`, …). Hier wordt
// daar een zin van gemaakt. Elke zin is één `l10n.d`-bron met
// `{plaatsvervangers}`, zodat de vertaling de woordvolgorde zelf bepaalt — er
// wordt dus nooit een zin uit losse stukken opgebouwd.
//
// Deze catalogus bedient de invuller: de codes die zijn eigen antwoorden kunnen
// raken. De codes van de organisator (`template-text-altered`, `field-missing`, …)
// en van de auteur (`rule-malformed`, …) krijgen hun zinnen bij het oppervlak dat
// ze toont; [formIssueMessageOrNull] geeft voor die `null`, zodat een nieuwe code
// niet ongemerkt een verkeerde zin krijgt (zie `form_issue_localization_test.dart`).

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'app_localizations.dart';

/// De zin voor [problem]. Een code die deze catalogus niet bedient krijgt een
/// algemene zin — beter dan een lege plek of een kale code.
String formIssueMessage(AppLocalizations l10n, FormProblem problem) =>
    formIssueMessageOrNull(l10n, problem) ??
    l10n.d(
      'Er klopt iets niet aan dit formulier. Neem contact op met degene die het heeft gemaakt.',
    );

/// De zin voor [problem], of `null` wanneer de code niet voor de invuller is.
String? formIssueMessageOrNull(AppLocalizations l10n, FormProblem problem) {
  final f = problem.facts;
  switch (problem.code) {
    case FormIssueCode.requiredEmpty:
      return l10n.d(
        'Dit veld is verplicht. Vul het in om te kunnen versturen.',
      );
    case FormIssueCode.tooFewWords:
      return _forItem(
        l10n,
        f,
        _fill(
          l10n.d(
            'Je hebt {actual} woorden geschreven; er zijn er minstens {min} nodig.',
          ),
          f,
        ),
      );
    case FormIssueCode.tooManyWords:
      return _forItem(
        l10n,
        f,
        _fill(
          l10n.d(
            'Je hebt {actual} woorden geschreven; er mogen er hoogstens {max} zijn.',
          ),
          f,
        ),
      );
    case FormIssueCode.tooShort:
      return _fill(
        l10n.d(
          'Je hebt {actual} tekens geschreven; er zijn er minstens {min} nodig.',
        ),
        f,
      );
    case FormIssueCode.tooLong:
      return _fill(
        l10n.d(
          'Je hebt {actual} tekens geschreven; er mogen er hoogstens {max} zijn.',
        ),
        f,
      );
    case FormIssueCode.notAnOption:
      return _fill(
        l10n.d('“{value}” staat niet in de lijst. Kies een van de opties.'),
        f,
      );
    case FormIssueCode.countOutOfRange:
      return _fill(_count(l10n, f), f);
    case FormIssueCode.badNumber:
      return _fill(
        l10n.d(
          '“{value}” is geen getal. Gebruik alleen cijfers, eventueel met een komma of punt voor de decimalen.',
        ),
        f,
      );
    case FormIssueCode.numberOutOfRange:
      return _fill(_numberRange(l10n, f), f);
    case FormIssueCode.badDate:
      return _fill(_date(l10n, f), f);
    case FormIssueCode.badPattern:
      return _pattern(l10n, f);
    case FormIssueCode.imageTooSmall:
      return _fill(
        l10n.d(
          'Deze foto is {actual} pixels breed; hier zijn er {min} gevraagd. Waarschijnlijk is hij kleiner geworden doordat hij via een berichtenapp is verstuurd. Heb je het origineel nog, gebruik dan dat. Zo niet, stuur hem dan toch mee: de organisatie neemt contact met je op.',
        ),
        f,
      );
    case FormIssueCode.imageTooLarge:
      return _fill(
        l10n.d('Deze foto is {actual} MB; het maximum is {max} MB.'),
        {
          'actual': _megabytes(f['actual'], up: true),
          'max': _megabytes(f['max']),
        },
      );
    case FormIssueCode.imageFormat:
      return f['reason'] == 'mismatch'
          ? l10n.d(
              'De inhoud van dit bestand past niet bij het bestandstype dat erachter staat.',
            )
          : l10n.d('Dit bestandstype is hier niet toegestaan.');
    case FormIssueCode.imageMissingFile:
      return l10n.d(
        'Het bestand van deze foto is niet meer te vinden. Voeg de foto opnieuw toe.',
      );
    case FormIssueCode.imageMissingAlt:
      return l10n.d('Beschrijf in een korte zin wat er op de foto te zien is.');
    case FormIssueCode.imageMissingCredit:
      return l10n.d('Geef aan van wie de foto is.');
    case FormIssueCode.imageUnchecked:
      return l10n.d(
        'Deze foto is nog niet gecontroleerd. Wacht even of voeg hem opnieuw toe.',
      );
    case FormIssueCode.imageHeicUnverified:
      return l10n.d(
        'Deze foto is een HEIC-bestand. OciDeck kan dat hier niet controleren of schoonmaken, dus het wordt verstuurd zoals het is. Er kan in staan waar de foto is genomen. Wil je dat niet delen, kies dan in de camera-instellingen “Meest compatibel” of deel de foto als JPEG en voeg hem opnieuw toe.',
      );
    case FormIssueCode.imageUnexpectedFaces:
      return _fill(
        l10n.d(
          'Op deze foto staan {actual} gezichten; verwacht werd {expected}. Dit is alleen een herinnering.',
        ),
        f,
      );
    case FormIssueCode.consentNotGiven:
      return l10n.d(
        'Zet het vinkje om akkoord te gaan; zonder toestemming kun je niet versturen.',
      );
    case FormIssueCode.structureDamaged:
      return f['reason'] == 'rules-too-new'
          ? l10n.d(
              'Dit formulier vraagt een nieuwere versie van OciDeck. Werk de app bij om het in te vullen.',
            )
          : l10n.d(
              'Er is per ongeluk iets in het formulier zelf veranderd. Herstel het formulier; je antwoorden blijven staan.',
            );
    case FormIssueCode.answerMalformed:
      return _malformed(l10n, f['reason']);
    case FormIssueCode.answerContainsMarker:
      return l10n.d(
        'Deze regel lijkt op een besturingscode van het formulier en mag niet in een antwoord staan. Pas hem aan.',
      );
    case FormIssueCode.answerContainsHtml:
      return l10n.d(
        'HTML mag niet in een antwoord. Gebruik gewone tekst en eenvoudige opmaak.',
      );
    case FormIssueCode.answerUnclosedFence:
      return l10n.d('Een codeblok is niet afgesloten. Sluit het af met ```.');
    case FormIssueCode.answerBadImage:
      return l10n.d(
        'Alleen foto’s die je in dit formulier toevoegt kunnen in een antwoord; een afbeelding van het internet kan niet.',
      );
    case FormIssueCode.answerBadLink:
      return l10n.d(
        'Alleen links die met https:// beginnen en e-mailadressen mogen in een antwoord.',
      );
    case FormIssueCode.formVersionMismatch:
      return _fill(
        l10n.d(
          'Dit bestand is gemaakt met een andere versie van het formulier (versie {submission}; nu geldt versie {published}). Controleer je antwoorden.',
        ),
        f,
      );
    case FormIssueCode.templateTextAltered:
    case FormIssueCode.templateUnknown:
    case FormIssueCode.fieldNotInForm:
    case FormIssueCode.fieldMissing:
    case FormIssueCode.rulesTooNew:
    case FormIssueCode.ruleMalformed:
    case FormIssueCode.duplicateFieldId:
    case FormIssueCode.unpairedMarker:
    case FormIssueCode.unknownType:
    case FormIssueCode.markerMalformed:
    case FormIssueCode.markerMisplaced:
    case FormIssueCode.noticeMissing:
    case FormIssueCode.formAttributeMissing:
    case FormIssueCode.unknownMarker:
    case FormIssueCode.unknownRule:
      return null;
  }
}

/// Zet de feiten in de plaatsvervangers van [template]. Een feit dat de zin niet
/// noemt wordt overgeslagen; een plaatsvervanger zonder feit blijft staan (en
/// valt dan in de test op). Alleen wat de invuller zelf typte (`value`) wordt
/// ingekort: een melding hoort op één regel te passen, maar een zin die hier als
/// feit binnenkomt (`bericht`) mag nooit worden afgekapt.
String _fill(String template, Map<String, Object?> facts) {
  var out = template;
  facts.forEach((key, value) {
    out = out.replaceAll(
      '{$key}',
      key == 'value' ? _typed('$value') : '$value',
    );
  });
  return out;
}

String _typed(String text) =>
    text.length <= 40 ? text : '${text.substring(0, 39)}…';

/// Voor een woordenmelding bij één punt van een lijst: "Punt 3: …".
String _forItem(AppLocalizations l10n, Map<String, Object?> f, String message) {
  final item = f['item'];
  if (item == null) return message;
  return _fill(l10n.d('Punt {item}: {bericht}'), {
    'item': item,
    'bericht': message,
  });
}

String _count(AppLocalizations l10n, Map<String, Object?> f) {
  final hasMin = f['min'] != null;
  final hasMax = f['max'] != null;
  if (hasMin && hasMax) {
    return l10n.d(
      'Het aantal is nu {actual}; het moet tussen {min} en {max} liggen.',
    );
  }
  return hasMax
      ? l10n.d('Het aantal is nu {actual}; het mag hoogstens {max} zijn.')
      : l10n.d('Het aantal is nu {actual}; het moet minstens {min} zijn.');
}

String _numberRange(AppLocalizations l10n, Map<String, Object?> f) {
  if (f['reason'] == 'step') {
    return l10n.d('Het getal moet een veelvoud zijn van {step}.');
  }
  final hasMin = f['min'] != null;
  final hasMax = f['max'] != null;
  if (hasMin && hasMax) {
    return l10n.d('Het getal moet tussen {min} en {max} liggen.');
  }
  return hasMax
      ? l10n.d('Het getal mag hoogstens {max} zijn.')
      : l10n.d('Het getal moet minstens {min} zijn.');
}

String _date(
  AppLocalizations l10n,
  Map<String, Object?> f,
) => switch (f['reason']) {
  'before-min' => l10n.d('De datum moet op of na {min} liggen.'),
  'after-max' => l10n.d('De datum moet op of vóór {max} liggen.'),
  _ => l10n.d(
    '“{value}” is geen datum. Schrijf de datum als jaar-maand-dag, bijvoorbeeld 2026-11-01.',
  ),
};

String _pattern(AppLocalizations l10n, Map<String, Object?> f) =>
    switch (f['pattern']) {
      'email' => l10n.d('Dit is geen geldig e-mailadres.'),
      'url' => l10n.d('Dit is geen geldig webadres. Begin met https://.'),
      'phone' => l10n.d('Dit is geen geldig telefoonnummer.'),
      'postcode-nl' => l10n.d(
        'Dit is geen geldige Nederlandse postcode, zoals 1234 AB.',
      ),
      _ => _malformed(l10n, null),
    };

/// De zin bij een antwoord dat niet de vorm van zijn veldtype heeft. De redenen
/// komen uit `parseAnswer`; elke groep is één zin, omdat de invuller niet hoeft te
/// weten welke van de drie lijstfouten hij maakte.
String _malformed(AppLocalizations l10n, Object? reason) => switch (reason) {
  'one-line' => l10n.d('Hier past één regel. Haal de regeleinden weg.'),
  'not-a-task-list' => l10n.d(
    'Gebruik alleen de keuzevakjes van deze vraag: één vakje per optie.',
  ),
  'unordered-item' || 'ordered-item' || 'not-a-list' => l10n.d(
    'Schrijf elk punt op een eigen regel, met een streepje of een nummer ervoor.',
  ),
  'not-a-table' || 'header-mismatch' || 'rule-row' || 'row-shape' => l10n.d(
    'De tabel klopt niet meer: laat de kopregel zoals hij was en geef elke rij evenveel kolommen.',
  ),
  'duplicate-image' => l10n.d('Dezelfde foto staat hier twee keer.'),
  'not-an-image' => l10n.d(
    'In dit veld horen alleen foto’s, geen losse tekst.',
  ),
  'consent-box-missing' || 'consent-box' => l10n.d(
    'Het vakje voor je toestemming is beschadigd. Herstel het formulier.',
  ),
  _ => l10n.d('Dit antwoord heeft niet de vorm die bij deze vraag hoort.'),
};

/// Hele megabytes. De grootte van de foto naar boven afgerond en de grens naar
/// beneden (en nooit onder de 1), zodat de melding nooit twee gelijke getallen
/// naast elkaar zet: "5 MB; het maximum is 4 MB" is waar, "4 MB; het maximum is
/// 4 MB" klopt voor de lezer niet. Een onbekend getal geeft een streepje.
String _megabytes(Object? bytes, {bool up = false}) {
  if (bytes is! int) return '–';
  final mb = bytes / 1048576;
  return '${up ? mb.ceil() : (mb.floor() < 1 ? 1 : mb.floor())}';
}
