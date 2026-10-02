// Part of form_issue_localization.dart — see there.
//
// De berichtencatalogus voor de organisator (FORM_INTAKE.md §4.11, §7.2): wat er mis
// is met een binnengekomen inzending, in een zin die over de inzender gaat en niet
// tot hem spreekt. De invuller leest "Je hebt 90 woorden geschreven"; de organisator
// leest "90 woorden; minstens 150 nodig", met de naam van het veld ervoor.
//
// Waar de zin van de invuller al neutraal is (een aantal, een getalgrens, een datum,
// een patroon, een bestandsgrootte) wordt die hergebruikt: dezelfde zin vertalen we
// niet twee keer. Een part van de catalogus van de invuller, omdat de hulpfuncties
// daar privé zijn en samen met de zinnen moeten kunnen meebewegen.
part of 'form_issue_localization.dart';

/// De zin voor [problem], voor de organisator. Een code zonder zin (een auteurscode,
/// die nooit in een inzending voorkomt) krijgt een algemene zin — beter dan een lege
/// plek of een kale code.
String formOrganiserMessage(AppLocalizations l10n, FormProblem problem) =>
    formOrganiserMessageOrNull(l10n, problem) ??
    l10n.d('Er klopt iets niet aan deze inzending.');

/// De zin voor [problem], of `null` voor een code die geen inzending kan raken.
String? formOrganiserMessageOrNull(
  AppLocalizations l10n,
  FormProblem problem,
) =>
    _orgValue(l10n, problem) ??
    _orgImage(l10n, problem) ??
    _orgAnswer(l10n, problem) ??
    _orgSubmission(l10n, problem);

/// De regels over de waarde.
String? _orgValue(AppLocalizations l10n, FormProblem problem) {
  final f = problem.facts;
  switch (problem.code) {
    case FormIssueCode.requiredEmpty:
      return l10n.d('Verplicht, maar leeg gelaten.');
    case FormIssueCode.tooFewWords:
      return _forItem(
        l10n,
        f,
        _fill(l10n.d('{actual} woorden; minstens {min} nodig.'), f),
      );
    case FormIssueCode.tooManyWords:
      return _forItem(
        l10n,
        f,
        _fill(l10n.d('{actual} woorden; hoogstens {max} toegestaan.'), f),
      );
    case FormIssueCode.tooShort:
      return _fill(l10n.d('{actual} tekens; minstens {min} nodig.'), f);
    case FormIssueCode.tooLong:
      return _fill(l10n.d('{actual} tekens; hoogstens {max} toegestaan.'), f);
    case FormIssueCode.notAnOption:
      return _fill(l10n.d('“{value}” staat niet in de lijst met opties.'), f);
    case FormIssueCode.countOutOfRange:
      return _fill(_count(l10n, f), f);
    case FormIssueCode.badNumber:
      return _fill(l10n.d('“{value}” is geen getal.'), f);
    case FormIssueCode.numberOutOfRange:
      return _fill(_numberRange(l10n, f), f);
    case FormIssueCode.badDate:
      return switch (f['reason']) {
        'before-min' || 'after-max' => _fill(_date(l10n, f), f),
        _ => _fill(
          l10n.d('“{value}” is geen datum in de vorm jaar-maand-dag.'),
          f,
        ),
      };
    case FormIssueCode.badPattern:
      return _pattern(l10n, f);
    default:
      return null;
  }
}

/// De regels over een foto.
String? _orgImage(AppLocalizations l10n, FormProblem problem) {
  final f = problem.facts;
  switch (problem.code) {
    case FormIssueCode.imageTooSmall:
      return _fill(
        l10n.d('Foto van {actual} pixels breed; er zijn {min} gevraagd.'),
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
      return l10n.d('Het bestand van de foto ontbreekt in de inzending.');
    case FormIssueCode.imageMissingAlt:
      return l10n.d('De beschrijving van de foto ontbreekt.');
    case FormIssueCode.imageMissingCredit:
      return l10n.d('De maker van de foto ontbreekt.');
    case FormIssueCode.imageUnchecked:
      return l10n.d('De foto is niet gecontroleerd.');
    case FormIssueCode.imageHeicUnverified:
      return l10n.d(
        'HEIC-foto: niet gecontroleerd of gezuiverd; er kan een locatie in staan.',
      );
    case FormIssueCode.imageUnexpectedFaces:
      return _fill(
        l10n.d(
          'Op deze foto staan {actual} gezichten; verwacht werd {expected}. Dit is alleen een herinnering.',
        ),
        f,
      );
    default:
      return null;
  }
}

/// De vorm en de veiligheid van het antwoord, en de toestemming.
String? _orgAnswer(AppLocalizations l10n, FormProblem problem) {
  switch (problem.code) {
    case FormIssueCode.consentNotGiven:
      return l10n.d('Toestemming niet gegeven.');
    case FormIssueCode.answerMalformed:
      return _malformed(l10n, null);
    case FormIssueCode.answerContainsMarker:
      return l10n.d(
        'Het antwoord bevat een regel die op een besturingscode van het formulier lijkt.',
      );
    case FormIssueCode.answerContainsHtml:
      return l10n.d('Het antwoord bevat HTML.');
    case FormIssueCode.answerUnclosedFence:
      return l10n.d('Het antwoord bevat een niet-afgesloten codeblok.');
    case FormIssueCode.answerBadImage:
      return l10n.d(
        'Het antwoord noemt een afbeelding die niet bij deze inzending hoort.',
      );
    case FormIssueCode.answerBadLink:
      return l10n.d('Het antwoord bevat een link die niet is toegestaan.');
    default:
      return null;
  }
}

/// De inzending als geheel tegen het gepubliceerde formulier: welk formulier, welke
/// versie, wat er in de tekst is veranderd, en of de opbouw nog klopt.
String? _orgSubmission(AppLocalizations l10n, FormProblem problem) {
  final f = problem.facts;
  switch (problem.code) {
    case FormIssueCode.templateUnknown:
      return l10n.d('Dit formulier of deze versie staat niet in de werkmap.');
    case FormIssueCode.templateTextAltered:
      return switch (f['reason']) {
        'hash' => l10n.d(
          'De inzender werkte met een andere tekst van het formulier dan de gepubliceerde.',
        ),
        'consent' => l10n.d(
          'De toestemming in het manifest klopt niet met het gepubliceerde formulier.',
        ),
        _ =>
          problem.fieldId == null
              ? l10n.d(
                  'De tekst van het formulier is veranderd buiten de antwoorden.',
                )
              : l10n.d('De tekst van het formulier is veranderd bij dit veld.'),
      };
    case FormIssueCode.fieldNotInForm:
      return l10n.d('Dit veld bestaat niet in het gepubliceerde formulier.');
    case FormIssueCode.fieldMissing:
      return l10n.d('Dit veld ontbreekt in de inzending.');
    case FormIssueCode.formVersionMismatch:
      return _fill(
        l10n.d(
          'Inzending van versie {submission}; gepubliceerd is versie {published}.',
        ),
        f,
      );
    case FormIssueCode.rulesTooNew:
      return l10n.d('Het formulier vraagt een nieuwere versie van OciDeck.');
    case FormIssueCode.structureDamaged:
      return switch (f['reason']) {
        'published-form' => l10n.d(
          'Het gepubliceerde formulier in de werkmap is niet bruikbaar.',
        ),
        'form-id' => l10n.d('De inzending hoort bij een ander formulier.'),
        'rules-too-new' => l10n.d(
          'Het formulier vraagt een nieuwere versie van OciDeck.',
        ),
        _ => l10n.d('De opbouw van de inzending is beschadigd.'),
      };
    default:
      return null;
  }
}
