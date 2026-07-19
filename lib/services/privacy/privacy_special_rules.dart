// Bijzondere persoonsgegevens (AVG art. 9 en 10).
//
// Hier zit de grootste vals-positieven-val van de hele scanner, en het is niet
// eens een subtiele: een slide *óver* de AVG noemt "gezondheidsgegevens" zonder
// er een te bevatten. Een privacyles, een DPIA-presentatie, een
// verwerkingsregister — allemaal vol met precies de woorden die we zoeken. Een
// trefwoordscanner die daarop waarschuwt, is binnen een dag uitgezet.
//
// ── De co-occurrence-escalator ───────────────────────────────────────────────
//
// De oplossing is dat een trefwoord op zichzelf níéts meldt dat de gebruiker
// onderbreekt. "Diagnose", "vakbond", "verdachte" leveren hooguit een
// informatieve hint op.
//
// Pas wanneer op dezelfde slide óók een DIRECT IDENTIFICEREND gegeven staat — een
// BSN, een e-mailadres, een nationaal nummer — gaat de melding omhoog: dan is het
// bijzondere gegeven herleidbaar tot een persoon, en dát is precies wat artikel 9
// beschermt.
//
//   slide over privacywetgeving:      "gezondheidsgegevens"          → stil
//   dossierslide:  "Jan, BSN 728398242, diagnose F32.1"              → melding
//
// Zonder die koppeling is trefwoorddetectie ruis. Mét die koppeling vangt ze
// precies het geval waar het om gaat.
//
// ── Waar de trefwoorden staan ───────────────────────────────────────────────
//
// Niet meer hier. Sinds fase 12 leven ze in `privacy_lexicon_data.dart`, waar
// elke term zelf zegt hoe hij gezocht wil worden, in welke taal hij staat en hoe
// specifiek hij is. Dit bestand houdt over wat géén woordenlijst is: de matcher,
// de notatieregels (genetisch, ICD-10, ATC, parketnummer), het bereik van een
// mededeling, en de persoonskoppelingspoort.

import '../../models/privacy_finding.dart';
import '../../models/privacy_lexicon.dart';

/// Vanaf welke lengte een term als voorvoegsel mag matchen.
///
/// Onder deze grens zitten in de praktijk alleen acroniemen — `hiv`, `ggz`,
/// `vog` — en juist die moeten als héél woord matchen. Anders vindt `vog` de
/// vogels, en dat is geen hypothetisch voorbeeld: dat deed hij.
const int kMinPrefixTermLength = 4;

/// Of dit teken bij een woord hoort. Latijnse accenttekens tellen mee, zodat
/// `patiënt` één woord is en niet drie.
bool _isWordChar(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0xC0 && c <= 0x24F);

/// Zoekt [term] in [lowerText] op een woordgrens. Geeft -1 als hij er niet staat.
///
/// Dit verving een kale `indexOf`, en het verschil is groter dan het lijkt. Twee
/// modi, met de termlengte als grens:
///
///   * **kort** (< [kMinPrefixTermLength]): alleen als héél woord, dus met een
///     grens aan beide kanten. `vog` vindt `VOG`, niet `vogels`;
///   * **lang**: op woordbegin, met een vrij achtervoegsel. Nederlandse
///     morfologie is vrijwel volledig suffigerend, dus `verdacht` hoort
///     `verdachte` en `verdachten` te vinden — en die miste de oude matcher,
///     want de lijst bevat alleen de zelfstandige vorm.
///
/// Wat dit **niet** oplost: homoniemen. `arrest` is een strafrechtelijke term én
/// een uitspraak van de Hoge Raad, en geen woordgrens ter wereld ziet het
/// verschil. Daar is de persoonskoppelingspoort voor.
int findPrivacyTerm(String lowerText, String term) {
  if (term.isEmpty) return -1;
  return findPrivacyTermIn(
    lowerText,
    term,
    term.length < kMinPrefixTermLength
        ? PrivacyTermMatch.word
        : PrivacyTermMatch.prefix,
  );
}

/// Zoekt [term] in [lowerText] met een expliciet opgegeven modus.
///
/// Sinds fase 12 komt die modus uit het lexicon in plaats van uit de termlengte,
/// en dat scheelt in beide richtingen. `arrest` is zes letters — lang genoeg om
/// onder de oude regel als voorvoegsel te matchen — maar moet als héél woord
/// gezocht worden, want het is ook een uitspraak van de Hoge Raad. Omgekeerd
/// hoort `ziekteverzuim` juist middenin een samenstelling gevonden te worden
/// (`ziekteverzuimcijfers`), en dat kon de oude matcher helemaal niet.
int findPrivacyTermIn(String lowerText, String term, PrivacyTermMatch match) {
  if (term.isEmpty) return -1;
  var from = 0;
  while (from <= lowerText.length - term.length) {
    final at = lowerText.indexOf(term, from);
    if (at < 0) return -1;
    final end = at + term.length;
    final startsWord = at == 0 || !_isWordChar(lowerText.codeUnitAt(at - 1));
    final endsWord =
        end >= lowerText.length || !_isWordChar(lowerText.codeUnitAt(end));

    final ok = switch (match) {
      PrivacyTermMatch.word => startsWord && endsWord,
      PrivacyTermMatch.prefix => startsWord,
      // Een samenstellingsdeel mag overal zitten. De veiligheid komt hier niet
      // van een woordgrens maar van de termlengte — zie [kMinCompoundLength].
      PrivacyTermMatch.compound => true,
    };
    if (ok) return at;
    from = at + 1;
  }
  return -1;
}

/// Genetische gegevens herkennen we aan hun notatie, niet aan een trefwoord.
///
/// dbSNP-identificatoren (`rs334`) en HGVS-varianten (`c.1521_1523delCTT`,
/// `p.Val600Glu`) zijn onmiskenbaar genetisch en komen in gewone tekst niet voor.
/// Dat maakt ze een van de weinige art. 9-regels met een laag FP-risico.
final List<({String id, RegExp pattern})> geneticPatterns = [
  // dbSNP: rs334 (sikkelcel), rs1801133. Drie cijfers is het minimum — `rs12`
  // zou te veel gewone tekst raken.
  (id: 'special.genetic', pattern: RegExp(r'\brs\d{3,}\b')),
  // HGVS op DNA-niveau: c.35G>A, c.1521_1523delCTT.
  (
    id: 'special.genetic',
    pattern: RegExp(
      r'\b[cgmn]\.\d+[+\-_\d]*(?:[ACGT]>[ACGT]|del[ACGT]*|dup[ACGT]*|ins[ACGT]*)\b',
    ),
  ),
  // HGVS op eiwitniveau: p.Val600Glu. Bewust met de drieletterige aminozuurcode,
  // want `p.42` is gewoon een paginanummer.
  (
    id: 'special.genetic',
    pattern: RegExp(r'\bp\.[A-Z][a-z]{2}\d+(?:[A-Z][a-z]{2}|\*|fs|=)\b'),
  ),
];

/// Medische codestelsels: ICD-10-diagnosecodes en ATC-geneesmiddelcodes.
///
/// Deze twee zijn het tegenovergestelde van de trefwoorden: ze zíjn het gegeven
/// (rol `value`), niet een aanwijzing ernaar. `F32.1` is een diagnose, punt.
///
/// **En ze zijn allebei zwaar FP-gevoelig**, wat de reden is dat ze pas nu komen
/// en niet in de eerste ronde. `A12` is een ICD-10-code én een tabelverwijzing én
/// een zaalnummer én een vitamine. `J01CA04` is amoxicilline én een
/// artikelnummer. Zonder contextwoord binnen [kContextWindow] tekens vuren ze
/// daarom niet — precies zoals het BSN dat niet doet, en om precies dezelfde
/// reden.
final List<({String id, RegExp pattern, List<String> contextWords})>
medicalCodePatterns = [
  (
    id: 'special.icd10',
    // Letter (niet U, die is voor noodgevallen gereserveerd) + twee cijfers,
    // optioneel een punt en één of twee cijfers.
    pattern: RegExp(r'\b[A-TV-Z]\d{2}(?:\.\d{1,2})?\b'),
    contextWords: [
      'icd',
      'icd-10',
      'diagnose',
      'hoofddiagnose',
      'nevendiagnose',
      'diagnosis',
      'diagnosecode',
    ],
  ),
  (
    id: 'special.atc',
    // Anatomische hoofdgroep + twee cijfers + twee letters + twee cijfers.
    pattern: RegExp(r'\b[A-V]\d{2}[A-Z]{2}\d{2}\b'),
    contextWords: [
      'atc',
      'geneesmiddel',
      'medicijn',
      'medicatie',
      'medication',
      'preparaat',
      'voorschrift',
    ],
  ),
];

/// Het Nederlandse parketnummer: `01/234567-19`.
///
/// Strafrechtelijke gegevens (art. 10), en een formaat dat in gewone tekst niet
/// voorkomt. Geen checksum, dus nooit meer dan `waarschijnlijk` — maar het
/// patroon is distinctief genoeg om zonder contextwoord te vuren.
final RegExp parketnummerPattern = RegExp(r'\b\d{2}/\d{6}-\d{2}\b');

/// De mededeling waarin een treffer staat: van regelbegin tot regeleinde.
///
/// Dit is de reikwijdte waarmee een bijzonder persoonsgegeven wordt weggehaald,
/// en de reden is dat een bijzonder gegeven geen wóórd is maar een uitspraak.
/// Lak je alleen het trefwoord weg, dan blijft er dit staan:
///
///     Marieke de Vries meldde zich ziek met een ████████
///
/// De naam staat er nog, de ziekmelding staat er nog, en `diabetes-` staat er
/// zelfs letterlijk nog. Er is niets weggehaald — er is een woord bedekt. Dat is
/// precies de fout die dit hele ontwerp wil voorkomen: niet beschikbaar is niet
/// beschikbaar.
///
/// Waarom de regel en niet de zin? Omdat zinsgrenzen niet te vertrouwen zijn.
/// "Zie dhr. Jansen. De diagnose is diabetes." splitst een puntdetector op de
/// afkorting, en dan valt de naam búíten de redactie — en dat is de gevaarlijke
/// kant om ernaast te zitten. Een regel is wat de auteur als één mededeling heeft
/// opgeschreven: één bullet, één tabelcel, één alinea. Te ruim redigeren is
/// hinderlijk; te krap redigeren is een lek.
({int start, int end}) statementSpan(String text, int start, int end) {
  var from = text.lastIndexOf('\n', start > 0 ? start - 1 : 0);
  from = from < 0 ? 0 : from + 1;

  var to = text.indexOf('\n', end);
  if (to < 0) to = text.length;

  // Omliggende witruimte hoort niet bij de mededeling: die meenemen zou het blok
  // laten kleven aan het woord ervoor.
  while (from < start && _isSpace(text.codeUnitAt(from))) {
    from++;
  }
  while (to > end && _isSpace(text.codeUnitAt(to - 1))) {
    to--;
  }
  return (start: from, end: to);
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

/// Welke bevindingen tellen als "direct identificerend" voor de escalator.
///
/// Een BSN, een nationaal nummer, een e-mailadres: gegevens die één persoon
/// aanwijzen. Een IBAN of een API-sleutel niet — die zeggen niets over wíé.
///
/// Deze koppeling geldt **slidebreed**: staat er ergens op de slide een BSN, dan
/// is het bijzondere gegeven op die slide daaraan te koppelen. Een slide is
/// klein genoeg dat dat opgaat.
bool identifiesAPerson(PrivacyFinding finding) {
  if (finding.confidence != PrivacyConfidence.certain) return false;
  return finding.family == PrivacyFamily.identifier ||
      finding.ruleId == 'contact.email';
}

/// Wijst deze bevinding een persoon aan met een naam?
///
/// De tweede, zwakkere koppelingsroute, en de poort waar de artikel 10-detectie
/// op wachtte. Zolang alleen [identifiesAPerson] telde, gebeurde er bij de meest
/// voorkomende formulering — "Marieke de Vries wordt verdacht van diefstal" —
/// precies niets: geen BSN op de slide, dus niemand om het gegeven aan te
/// koppelen, dus bleef de melding informatief.
///
/// `possible` telt bewust níét mee: dat is de drempel waaronder een naam een gok
/// is, en een gok mag geen andere melding omhoog trekken.
bool namesAPerson(PrivacyFinding finding) =>
    finding.ruleId == 'contact.name' &&
    finding.confidence != PrivacyConfidence.possible;

/// Reikt de naamkoppeling tot deze treffer?
///
/// **Een naam koppelt niet slidebreed, maar tot het einde van zijn mededeling** —
/// en dat verschil is niet theoretisch. Een naam is geen identificator maar een
/// toeschrijving, en een toeschrijving reikt zo ver als de zin waarin ze staat.
/// Zonder die grens gebeurt er dit: een vrij-markdownveld met een handleiding
/// erin noemt bovenaan iemands naam, en tilt daarmee élk trefwoord in de
/// duizend regels eronder naar een harde melding. Dat is precies gebeurd, en de
/// vals-positievencorpustest ving het.
///
/// De mededeling is dezelfde eenheid als bij redactie ([statementSpan]), en dat
/// is geen toeval: wat samen één uitspraak vormt, koppelt samen, en wordt samen
/// weggehaald.
bool nameLinkReaches(
  PrivacyFinding name,
  PrivacyFinding target,
  String fragmentText,
) {
  if (name.field != target.field) return false;
  if (name.fragmentIndex != target.fragmentIndex) return false;
  if (fragmentText.isEmpty) return false;
  final span = statementSpan(fragmentText, target.start, target.end);
  return name.start >= span.start && name.end <= span.end;
}
