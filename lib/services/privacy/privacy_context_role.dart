// Verdachte, aangever of getuige — en meestal: onbekend.
//
// Artikel 10 gaat over strafrechtelijke gegevens, en tot fase 14 behandelde de
// scanner elk zo'n gegeven hetzelfde. "Verdachte M. de Vries" en "aangeefster
// M. de Vries" leverden een identieke melding op, terwijl dat juridisch en
// menselijk twee volstrekt verschillende dingen zijn — en de tweede is degene
// voor wie een lek het hardst aankomt.
//
// ── Waarom drieweg, met onbekend als standaard ──────────────────────────────
//
// De verleiding is een tweeweg: verdachte of niet. Dat is precies verkeerd. Als
// je moet gokken, is de kostbare fout niet "ik weet het niet" maar "ik noem een
// aangeefster een verdachte" — en een tweeweg dwíngt die fout af, want er is geen
// derde vakje om in te vallen. Vandaar [PrivacyPersonRole.unknown] als default,
// en vandaar dat ambiguïteit erin terugvalt in plaats van in de meest
// waarschijnlijke lezing.
//
// Dat is geen bescheidenheidsfiguur. VACCINE (WWW 2019) meet dat *subject*
// detectie — "van wie is dit gegeven?" — op Engelstalige e-mail F1 48,35% haalt
// tegen 90,20% voor attribuutdetectie. Ongeveer de helft. Een mechanisme dat op
// die basis stellig doet over iemands rol in een strafzaak, doet meer kwaad dan
// het oplost.
//
// ── De mechaniek ────────────────────────────────────────────────────────────
//
// ConText (Chapman e.a., 2007), oorspronkelijk voor klinische teksten: een
// triggerwoord opent een bereik dat tot het einde van de mededeling loopt, tenzij
// een terminatiewoord het eerder afkapt. Wij passen twee dingen aan:
//
//   * het bereik is de mededeling (§5.6), niet een tekenvenster — dezelfde
//     eenheid als de redactie gebruikt, en om dezelfde reden: dat is wat de
//     auteur als één uitspraak heeft opgeschreven;
//   * staan er triggers van méér dan één rol in dezelfde mededeling, dan is de
//     uitkomst `unknown`. "De verdachte en de aangeefster kenden elkaar" krijgt
//     dus geen rol, en dat is de juiste uitkomst — er staan er twee.

import '../../models/privacy_finding.dart';
import 'privacy_special_rules.dart';

/// Triggerwoorden per rol.
///
/// NL/EN/DE, en bewust smal gehouden. Elk woord dat hier bij komt, moet
/// eenduidig zijn: `betrokkene` staat er niet in, want dat betekent in de ene
/// zin de verdachte en in de andere het slachtoffer.
const Map<PrivacyPersonRole, List<String>> personRoleTriggers = {
  PrivacyPersonRole.suspect: [
    'verdacht',
    'verdachte',
    'dader',
    'aangehouden',
    'veroordeeld',
    'gedetineerde',
    'gearresteerd',
    'tenlastegelegd',
    'suspect',
    'perpetrator',
    'convicted',
    'arrested',
    'defendant',
    'verdächtige',
    'täter',
    'angeklagte',
  ],
  PrivacyPersonRole.reporter: [
    'aangever',
    'aangeefster',
    'aangifte',
    'slachtoffer',
    'benadeelde',
    'melder',
    'meldster',
    'gedupeerde',
    'victim',
    'complainant',
    'reported by',
    'opfer',
    'geschädigte',
    'anzeigenerstatter',
  ],
  PrivacyPersonRole.witness: [
    'getuige',
    'getuigenverklaring',
    'witness',
    'zeuge',
    'zeugin',
  ],
};

/// Woorden die het bereik van een trigger afkappen.
///
/// Zonder deze zou "de verdachte verklaarde dat de aangeefster loog" één rol
/// over de hele zin uitsmeren. Een voegwoord betekent dat er een nieuwe
/// mededeling begint, ook al staat er geen punt.
const List<String> roleTerminators = [
  ' maar ',
  ' terwijl ',
  ' hoewel ',
  ' daarentegen ',
  ' echter ',
  ' but ',
  ' whereas ',
  ' although ',
  ' aber ',
  ' während ',
];

/// De rol die bij een treffer op [matchStart] hoort binnen [text].
///
/// Geeft [PrivacyPersonRole.unknown] wanneer er geen trigger staat, of wanneer
/// er meer dan één rol in beeld is. Dat tweede geval is geen tekortkoming maar
/// het ontwerp: bij twijfel geen rol.
PrivacyPersonRole personRoleFor(String text, int matchStart, int matchEnd) {
  if (text.isEmpty) return PrivacyPersonRole.unknown;
  final span = statementSpan(text, matchStart, matchEnd);
  final statement = text.substring(span.start, span.end).toLowerCase();
  final scope = _scopeAround(statement, matchStart - span.start);

  final found = <PrivacyPersonRole>{};
  for (final entry in personRoleTriggers.entries) {
    for (final trigger in entry.value) {
      if (findPrivacyTerm(scope, trigger) >= 0) {
        found.add(entry.key);
        break;
      }
    }
  }
  return found.length == 1 ? found.single : PrivacyPersonRole.unknown;
}

/// Het stuk mededeling waarin een trigger nog telt.
///
/// Loopt van het dichtstbijzijnde terminatiewoord vóór de treffer tot het
/// dichtstbijzijnde erna. Zo blijft "de verdachte verklaarde dat de aangeefster
/// loog" netjes in tweeën, ook zonder leesteken ertussen.
String _scopeAround(String statement, int offset) {
  var from = 0;
  var to = statement.length;
  for (final terminator in roleTerminators) {
    final before = statement.lastIndexOf(terminator, offset);
    if (before >= 0 && before + terminator.length > from) {
      from = before + terminator.length;
    }
    final after = statement.indexOf(terminator, offset);
    if (after >= 0 && after < to) to = after;
  }
  if (from > to) return '';
  return statement.substring(from, to);
}
